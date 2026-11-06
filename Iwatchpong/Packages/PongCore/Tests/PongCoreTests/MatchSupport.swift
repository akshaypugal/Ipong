import Foundation
@testable import PongCore

extension MatchEngine {
    /// Run for `seconds` of game time, collecting events.
    @discardableResult
    func run(_ seconds: Double, step: Double = 1.0 / 120.0) -> [MatchEvent] {
        var all: [MatchEvent] = []
        var t = 0.0
        while t < seconds {
            update(step)
            all.append(contentsOf: drainEvents())
            t += step
        }
        return all
    }

    /// Run until the clock reaches `time`.
    @discardableResult
    func run(untilClock time: Double, step: Double = 1.0 / 240.0) -> [MatchEvent] {
        var all: [MatchEvent] = []
        var guardCount = 0
        while clock < time, guardCount < 200_000 {
            update(step)
            all.append(contentsOf: drainEvents())
            guardCount += 1
        }
        return all
    }

    /// Run until an event matches (or `limit` seconds pass).
    func run(until predicate: (MatchEvent) -> Bool, limit: Double = 30, step: Double = 1.0 / 120.0) -> [MatchEvent] {
        var all: [MatchEvent] = []
        var t = 0.0
        while t < limit {
            update(step)
            let es = drainEvents()
            all.append(contentsOf: es)
            if es.contains(where: predicate) { break }
            t += step
        }
        return all
    }
}

func isPoint(_ e: MatchEvent) -> Bool {
    if case .point = e { return true }
    return false
}

func pointInfo(_ events: [MatchEvent]) -> PointInfo? {
    for e in events { if case .point(let p) = e { return p } }
    return nil
}

func shots(_ events: [MatchEvent]) -> [ShotReport] {
    events.compactMap { if case .shot(let s) = $0 { return s } else { return nil } }
}

/// An opponent that returns nothing (or everything) so scenarios are deterministic.
func hopelessOpponent() -> OpponentProfile {
    var p = OpponentProfile.roster[0]
    p.consistency = -2
    p.reaction = 0.5
    return p
}

func flawlessOpponent() -> OpponentProfile {
    var p = OpponentProfile.roster[5]
    p.consistency = 3
    p.placement = 0.5
    return p
}

/// A ball the opponent just hit toward the human.
func incomingBall(speed: Double = 8, spin: SpinSpec = SpinSpec(top: 80), landing: (x: Double, z: Double) = (-0.9, 0.1),
                  arc: Arc = .low) -> BallState {
    let origin = Vec3(1.55, 0.3, 0)
    let sol = ShotSolver.solve(origin: origin, facing: .towardNear, speed: speed, spin: spin,
                               target: landing, arc: arc)
    return BallState(position: origin, velocity: sol.velocity, spin: Facing.towardNear.toWorld(spin.vector))
}

/// A scripted human player for whole-match simulations.
final class HumanBot {
    var paddle: SimulatedPaddle
    var rng: SeededRNG
    /// Std-dev of the timing error, seconds.
    var timingSigma: Double
    /// Strokes the bot uses for ordinary balls.
    var rallyInputs: [SimulatedInput]
    var serveInput: SimulatedInput = .forehandTopspin
    /// Fraction of incoming balls the bot actually swings at.
    var attentiveness = 1.0
    private var scheduled: (time: Double, input: SimulatedInput)?
    private var handledHintTime: Double = -1
    private var tossSent = false

    init(seed: UInt64 = 5, timingSigma: Double = 0.02,
         rallyInputs: [SimulatedInput] = [.forehandDrive, .forehandTopspin, .backhandDrive, .block]) {
        paddle = SimulatedPaddle(seed: seed)
        rng = SeededRNG(seed: seed &* 7 &+ 1)
        self.timingSigma = timingSigma
        self.rallyInputs = rallyInputs
    }

    func tick(_ engine: MatchEngine) {
        switch engine.phase {
        case .serveReady(.human):
            if !tossSent {
                tossSent = true
                engine.handle(paddle.event(for: .toss, at: engine.clock))
            }
        case .tossing(.human):
            tossSent = false
            if scheduled == nil, let h = engine.snapshot.hint {
                scheduled = (h.idealTime + rng.gaussian(sigma: timingSigma), serveInput)
            }
        case .rally:
            tossSent = false
            if let h = engine.snapshot.hint, h.idealTime != handledHintTime {
                handledHintTime = h.idealTime
                if rng.chance(attentiveness) {
                    let input = rallyInputs[Int(rng.next() % UInt64(rallyInputs.count))]
                    scheduled = (h.idealTime + rng.gaussian(sigma: timingSigma), input)
                }
            }
        default:
            tossSent = false
        }
        if let s = scheduled, engine.clock >= s.time {
            scheduled = nil
            engine.handle(paddle.event(for: s.input, at: engine.clock))
        }
    }
}

/// Plays a whole match with a bot; returns the outcome (nil if it did not finish).
func playMatch(opponent: OpponentProfile, bot: HumanBot, seed: UInt64, config: MatchConfig = MatchConfig(),
               upgrades: PlayerUpgrades = PlayerUpgrades(), maxSeconds: Double = 2400) -> (MatchOutcome?, MatchEngine) {
    let engine = MatchEngine(opponent: opponent, upgrades: upgrades, config: config, seed: seed)
    engine.start()
    var t = 0.0
    let dt = 1.0 / 120
    while t < maxSeconds, !engine.isOver {
        bot.tick(engine)
        engine.update(dt)
        _ = engine.drainEvents()
        t += dt
    }
    return (engine.outcome, engine)
}
