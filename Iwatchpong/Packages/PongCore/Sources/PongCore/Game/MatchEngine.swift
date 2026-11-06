import Foundation

public enum MatchMode: Sendable {
    case match
    case drill(DrillSpec)
}

/// The table-tennis game.
///
/// It consumes high-level `PaddleEvent`s (from the Watch or the simulated buttons),
/// advances a deterministic fixed-step simulation (`update`), and reports what
/// happened as `MatchEvent`s. Nothing in here knows about CoreMotion,
/// WatchConnectivity or SwiftUI.
///
/// **Latency compensation.** A swing arrives with `age`: how long ago the contact
/// happened (Watch detection delay + transport). The engine rolls the ball back to
/// the contact moment, applies the hit there, and re-simulates the flight up to
/// now, so being 150 ms late on the wire does not make you late on the ball.
public final class MatchEngine {
    public let config: MatchConfig
    public let opponent: OpponentProfile
    public let upgrades: PlayerUpgrades
    public let mode: MatchMode
    /// Right-handed players have their forehand on the right side of the table.
    public var rightHanded = true
    public var isPaused = false

    // MARK: Observable state
    public private(set) var phase: MatchPhase = .notStarted
    public private(set) var clock = 0.0
    public private(set) var score: ScoreKeeper
    public private(set) var stats = MatchStats()
    public private(set) var human = PlayerPose(x: -1.75)
    public private(set) var opp = PlayerPose(x: 1.75)
    public private(set) var ball = BallState(position: Vec3(0, 0.3, 0))
    public private(set) var ballVisible = false
    public private(set) var rallyCount = 0
    public private(set) var hint: StrikeHint?
    public private(set) var outcome: MatchOutcome?
    public private(set) var drillSuccesses = 0
    public private(set) var drillAttempts = 0

    // MARK: Internals
    private struct RallyState {
        var server: Player = .human
        var isServe = false
        var lastHitter: Player?
        var hits = 0
        var bounces: [CourtSide: Int] = [.near: 0, .far: 0]
        var netTouchedOnServe = false
        var nearBounceTime: Double?
        var lastHumanStroke: StrokeKind?
        var lastHumanSide: StrokeSide = .either
        var lastHumanBallZ = 0.0
        /// How hard the ball the human is about to face is to return.
        var incomingPressure = 0.0
    }

    private struct Pending {
        var winner: Player
        var reason: PointReason
        var deadline: Double
        /// A late swing may still cancel it (the human's missed ball).
        var cancellable: Bool
    }

    private struct StrikePlan {
        var bounceTime: Double
        var apexTime: Double
        var apexState: BallState
        /// When the ball was hit and where the receiver stood at that moment.
        var hitTime = 0.0
        var startZ = 0.0
    }

    private struct AIPlan {
        var hitTime: Double
        var decision: AIDecision
        var strike: StrikePlan
    }

    private struct Toss {
        var start: Double
        var ideal: Double
        var attemptsUsed = 0
    }

    private var rng: SeededRNG
    private var events: [MatchEvent] = []
    private var accumulator = 0.0
    private var history: [(t: Double, ball: BallState)] = []
    private var rally = RallyState()
    private var pending: Pending?
    private var phaseTimer = 0.0
    private var toss: Toss?
    private var strike: StrikePlan?
    private var aiPlan: AIPlan?
    private var serveAttempts = 0
    private var matchTime = 0.0
    private var feedIndex = 0
    private var tossRetriesLeft = 1

    private let step = BallPhysics.fixedStep
    private static let tossSpeed = 3.4
    private static let handHeight = 0.28

    public init(opponent: OpponentProfile, upgrades: PlayerUpgrades = PlayerUpgrades(),
                config: MatchConfig = MatchConfig(), mode: MatchMode = .match, seed: UInt64 = 1) {
        self.opponent = opponent
        self.upgrades = upgrades
        self.config = config
        self.mode = mode
        rng = SeededRNG(seed: seed)
        score = ScoreKeeper(pointsPerGame: config.pointsPerGame, gamesToWin: config.gamesToWin, firstServer: config.firstServer)
    }

    // MARK: - Public API

    public var isDrill: Bool {
        if case .drill = mode { return true }
        return false
    }

    public var drillSpec: DrillSpec? {
        if case .drill(let s) = mode { return s }
        return nil
    }

    public var isOver: Bool {
        switch phase {
        case .matchOver, .drillOver: return true
        default: return false
        }
    }

    public func start() {
        guard phase == .notStarted else { return }
        tossRetriesLeft = config.tossRetries
        if let spec = drillSpec, spec.kind == .serve {
            beginServeReady(.human)
        } else if isDrill {
            beginServeReady(.opponent)
        } else {
            beginServeReady(score.server)
        }
    }

    public func drainEvents() -> [MatchEvent] {
        let e = events
        events.removeAll(keepingCapacity: true)
        return e
    }

    public var snapshot: MatchSnapshot {
        MatchSnapshot(phase: phase, time: clock, ballVisible: ballVisible, ball: ball, human: human, opponent: opp,
                      humanPoints: score.humanPoints, opponentPoints: score.opponentPoints,
                      humanGames: score.humanGames, opponentGames: score.opponentGames,
                      server: rally.server, rally: rallyCount, hint: hint, gameNumber: score.gameNumber,
                      drillSuccesses: drillSuccesses, drillAttempts: drillAttempts)
    }

    /// Advance the game by `dt` seconds.
    public func update(_ dt: Double) {
        guard !isPaused, dt > 0 else { return }
        accumulator += min(dt, 0.1)
        while accumulator >= step {
            accumulator -= step
            fixedStep()
        }
    }

    /// Feed one gesture into the game. `age` is how long ago the physical motion happened.
    public func handle(_ event: PaddleEvent, age: Double = 0) {
        guard !isPaused else { return }
        let age = max(0, min(age, config.maxRollback))
        switch event {
        case .toss:
            if case .serveReady(.human) = phase { beginToss(.human) } else { events.append(.whiff(.notInPlay)) }
        case .swing(let swing):
            humanSwing(swing, age: age)
        }
    }

    // MARK: - Fixed step

    private func fixedStep() {
        clock += step
        matchTime += step
        stepPoses()

        switch phase {
        case .notStarted, .matchOver, .drillOver:
            break

        case .serveReady(let p):
            phaseTimer -= step
            if p == .opponent, phaseTimer <= 0 { beginToss(.opponent) }

        case .tossing(let p):
            stepBall()
            guard case .tossing = phase, let t = toss else { return }
            if p == .opponent {
                if clock >= t.ideal { opponentServe() }
            } else if ball.velocity.y < 0, ball.position.y < 0.08 {
                tossMissed()
            }

        case .rally:
            stepBall()
            guard case .rally = phase else { return }
            runOpponentPlan()
            checkBallPassed()
            if let p = pending, clock >= p.deadline { pending = nil; awardPoint(p.winner, p.reason) }

        case .pointOver:
            phaseTimer -= step
            if phaseTimer <= 0 { afterPoint() }

        case .gameOver:
            phaseTimer -= step
            if phaseTimer <= 0 {
                score.startNextGame()
                rallyCount = 0
                beginServeReady(score.server)
            }
        }
    }

    // MARK: - Poses

    private func stepPoses() {
        var humanTargetZ = 0.0
        var humanTargetX = -1.75
        var oppTargetZ = 0.0
        var oppTargetX = 1.75
        if case .rally = phase {
            if rally.lastHitter == .opponent, let s = strike {
                humanTargetZ = clock >= s.hitTime + config.humanReaction ? s.apexState.position.z : human.z
                humanTargetX = max(-2.8, min(-1.45, s.apexState.position.x - 0.3))
            }
            if rally.lastHitter == .human, let p = aiPlan {
                oppTargetZ = p.strike.apexState.position.z
                oppTargetX = max(1.45, min(2.8, p.strike.apexState.position.x + 0.3))
            }
        }
        if case .tossing(.human) = phase { humanTargetZ = human.z }
        human.z = approach(human.z, to: max(-1.2, min(1.2, humanTargetZ)), speed: upgrades.moveSpeed)
        human.x = approach(human.x, to: humanTargetX, speed: 2.5)
        opp.z = approach(opp.z, to: max(-1.2, min(1.2, oppTargetZ)), speed: opponent.speed)
        opp.x = approach(opp.x, to: oppTargetX, speed: 2.5)
    }

    private func approach(_ v: Double, to target: Double, speed: Double) -> Double {
        let d = target - v
        let m = speed * step
        return abs(d) <= m ? target : v + (d > 0 ? m : -m)
    }

    // MARK: - Serving

    private func handPosition(of p: Player) -> Vec3 {
        let pose = p == .human ? human : opp
        return Vec3(p == .human ? -1.55 : 1.55, Self.handHeight, pose.z)
    }

    private func beginServeReady(_ server: Player) {
        rally = RallyState()
        rally.server = server
        rally.isServe = true
        pending = nil
        strike = nil
        aiPlan = nil
        hint = nil
        toss = nil
        history.removeAll()
        serveAttempts = 0
        tossRetriesLeft = config.tossRetries
        rallyCount = 0
        ball = BallState(position: handPosition(of: server))
        ballVisible = true
        phase = .serveReady(server)
        phaseTimer = server == .opponent ? config.aiServeDelay : 0
        events.append(.serveReady(server))
    }

    private func beginToss(_ p: Player) {
        if isDrill, p == .opponent {
            machineFeed()
            return
        }
        var b = BallState(position: handPosition(of: p))
        b.velocity = Vec3(0, Self.tossSpeed, 0)
        ball = b
        history.removeAll()
        // Time for the ball to come back down to hand height.
        let g = 9.81
        let y0 = Self.handHeight
        let target = Self.handHeight + 0.02
        let disc = max(0, Self.tossSpeed * Self.tossSpeed - 2 * g * (target - y0))
        let ideal = (Self.tossSpeed + disc.squareRoot()) / g
        toss = Toss(start: clock, ideal: clock + ideal)
        phase = .tossing(p)
        events.append(.tossStarted(p))
        if p == .human {
            hint = StrikeHint(idealTime: clock + ideal, position: Vec3(-1.55, Self.handHeight, human.z))
        }
    }

    private func tossMissed() {
        events.append(.tossMissed(.human))
        hint = nil
        if tossRetriesLeft > 0 {
            tossRetriesLeft -= 1
            serveAttempts += 1
            ball = BallState(position: handPosition(of: .human))
            history.removeAll()
            phase = .serveReady(.human)
            toss = nil
            events.append(.serveReady(.human))
        } else {
            awardPoint(.opponent, .tossFault)
        }
    }

    private func opponentServe() {
        let decision = OpponentBrain.serve(profile: opponent, humanZ: human.z, rng: &rng)
        let swing = decision.swing
        performServe(by: .opponent, swing: swing, timingOffset: decision.contact.timingOffset,
                     mods: decision.mods, aim: decision.aim, contactState: ball)
    }

    private func humanServeSwing(_ s: SwingResult, age: Double) {
        guard let t = toss else { return }
        let tContact = clock - age
        let dt = tContact - t.ideal
        if dt < -0.45 {
            // Swung while the ball was still rising: too early.
            events.append(.whiff(.tooEarly))
            return
        }
        if dt > 0.20 {
            events.append(.whiff(.tooLate))
            return
        }
        let state = ballState(at: tContact)
        performServe(by: .human, swing: s, timingOffset: dt, mods: ShotModifiers(upgrades: upgrades),
                     aim: nil, contactState: state, age: age)
    }

    private func performServe(by p: Player, swing: SwingResult, timingOffset: Double, mods: ShotModifiers,
                              aim: Double?, contactState: BallState, age: Double = 0) {
        let facing = p.facing
        let plan = ShotModel.servePlan(swing: swing, timingOffset: timingOffset, mods: mods,
                                       aimOverride: aim.map { $0 * facing.sign }, rng: &rng)
        let origin = Vec3(contactState.position.x, max(0.1, min(0.5, contactState.position.y)), contactState.position.z)
        var speed = plan.speed
        var spinSpec = plan.spin
        var solution: LaunchSolution?
        // Serve assist: if the exact serve is physically impossible (e.g. heavy backspin at
        // low speed never crosses the net), relax pace and spin a little until a legal one exists.
        outer: for spinScale in [1.0, 0.7, 0.45] {
            for speedScale in [1.0, 1.15, 1.3, 0.85, 0.7] {
                let trySpeed = plan.speed * speedScale
                let trySpin = SpinSpec(top: plan.spin.top * spinScale, side: plan.spin.side * spinScale)
                if let s = ShotSolver.solveServe(origin: origin, facing: facing, speed: trySpeed, spin: trySpin,
                                                 target: (plan.target.x * facing.sign, plan.target.z * facing.sign)) {
                    solution = s
                    speed = trySpeed
                    spinSpec = trySpin
                    break outer
                }
            }
        }

        var b = BallState(position: origin)
        if let s = solution {
            b.velocity = s.velocity
            b.spin = facing.toWorld(spinSpec.vector)
        } else {
            // No legal serve at this pace: it goes flat into the table / net.
            b.velocity = facing.toWorld(Vec3(speed, 0.2, 0))
            b.spin = .zero
        }
        toss = nil
        hint = nil
        history.removeAll()
        ball = b
        phase = .rally
        rally.isServe = true
        rally.server = p
        rally.lastHitter = p
        rally.hits = 1
        rally.bounces = [.near: 0, .far: 0]
        rally.netTouchedOnServe = false
        rallyCount = 1
        if p == .human {
            rally.lastHumanStroke = swing.stroke
            rally.lastHumanSide = swing.side
            stats.serves += 1
            noteHumanShot(swing, speed: speed)
        }
        reportShot(by: p, swing: swing, plan: plan, speed: speed, isServe: true, timingOffset: timingOffset, target: solution?.landing)
        setSwingPose(p, swing: swing, at: clock - age, aim: plan.target.z * facing.sign)
        prepareReceiver(of: p, at: clock - age)
        if age > 0 { advanceBall(by: age) }
    }

    // MARK: - Human swings

    private func humanSwing(_ s: SwingResult, age: Double) {
        switch phase {
        case .serveReady(.human):
            // A swing without a toss: toss for the player and tell them.
            beginToss(.human)
            events.append(.whiff(.needToss))
        case .tossing(.human):
            humanServeSwing(s, age: age)
        case .rally:
            humanRallySwing(s, age: age)
        default:
            events.append(.whiff(.notInPlay))
        }
    }

    private func humanRallySwing(_ s: SwingResult, age: Double) {
        guard rally.lastHitter == .opponent else {
            events.append(.whiff(rally.lastHitter == .human ? .alreadyHit : .noBall))
            return
        }
        guard let plan = strike else {
            events.append(.whiff(.noBall))
            return
        }
        let tContact = clock - age
        // The ball must have bounced on this side already (real rules: no volleys).
        if tContact < plan.bounceTime - 0.02 {
            events.append(.whiff(.noBall))
            return
        }
        let ideal = plan.apexTime + ShotModel.idealOffset(for: s.stroke)
        let dt = tContact - ideal
        let window = ShotModel.baseTimingWindow * upgrades.timingWindowMultiplier
        if dt < -(window + 0.12) { events.append(.whiff(.tooEarly)); return }
        if dt > window + 0.14 { events.append(.whiff(.tooLate)); return }

        let state = ballState(at: tContact)
        let ballZ = state.position.z
        let forehandSign: Double = rightHanded ? 1 : -1
        let expected: StrokeSide = ballZ * forehandSign >= 0 ? .forehand : .backhand
        let wrongSide = s.side != .either && s.side != expected && abs(ballZ) > 0.18
        // The avatar only starts moving after the player's reaction time, at limited speed.
        let travelled = upgrades.moveSpeed * max(0, tContact - plan.hitTime - config.humanReaction)
        let dz = plan.apexState.position.z - plan.startZ
        let avatarZ = plan.startZ + (abs(dz) <= travelled ? dz : (dz > 0 ? travelled : -travelled))
        let reach = 0.42 + upgrades.reachBonus
        let deficit = max(0, abs(ballZ - avatarZ) - reach)
        if deficit > 0.55 {
            events.append(.whiff(.outOfReach))
            return
        }
        let contact = ContactInfo(timingOffset: dt, ballHeight: state.position.y, ballSpeed: state.speed,
                                  incomingTopspin: ShotModel.topspinAmount(of: state), reachDeficit: deficit,
                                  wrongSide: wrongSide, timeAvailable: plan.apexTime - plan.hitTime,
                                  pressure: max(0, rally.incomingPressure - 0.03 * Double(upgrades.control)))
        let mods = ShotModifiers(upgrades: upgrades)
        var shot = ShotModel.plan(swing: s, contact: contact, mods: mods, rng: &rng)
        // Unforced errors: even a decent contact sometimes nets or sails long. Training drills are forgiving.
        if !isDrill {
            let faultP = (0.03 + 0.7 * pow(max(0, 1 - shot.quality), 1.1)) * max(0.3, upgrades.errorMultiplier)
            if rng.chance(faultP) {
                shot = ShotModel.plan(swing: s, contact: contact, mods: mods, errorOverride: 1.1, rng: &rng)
            }
        }
        pending = pending.flatMap { $0.cancellable ? nil : $0 }       // a late swing saves a "missed" point

        rally.lastHumanStroke = s.stroke
        rally.lastHumanSide = s.side
        rally.lastHumanBallZ = ballZ
        applyShot(by: .human, swing: s, plan: shot, from: state, age: age, timingOffset: dt)
    }

    // MARK: - Applying a shot

    private func applyShot(by p: Player, swing: SwingResult, plan: ShotPlan, from state: BallState, age: Double,
                           timingOffset: Double, deliberateError: Bool = false) {
        let facing = p.facing
        let origin = Vec3(state.position.x, max(0.03, state.position.y), state.position.z)
        let worldTarget = (x: plan.target.x * facing.sign, z: plan.target.z * facing.sign)
        // Shot assist: a physically impossible aim (a very slow drop that cannot clear the net,
        // a fast chop that floats long) is played with a touch more or less pace or spin instead
        // of going into the net for no reason.
        var solution = ShotSolver.solve(origin: origin, facing: facing, speed: plan.speed, spin: plan.spin,
                                        target: worldTarget, arc: plan.arc)
        var finalSpin = plan.spin
        if !solution.reachedTarget {
            search: for spinScale in [1.0, 0.7, 0.4] {
                for speedScale in [1.15, 1.3, 1.5, 0.85, 0.7] {
                    let spin = SpinSpec(top: plan.spin.top * spinScale, side: plan.spin.side * spinScale)
                    let retry = ShotSolver.solve(origin: origin, facing: facing, speed: plan.speed * speedScale, spin: spin,
                                                 target: worldTarget, arc: plan.arc)
                    if retry.reachedTarget {
                        solution = retry
                        finalSpin = spin
                        break search
                    }
                }
            }
        }
        // The opponent watches its own shot: if it would not land, it re-aims safer (unless it is
        // an unforced error).
        if p == .opponent, !deliberateError, solution.landing == nil {
            let safe = (x: max(0.5, min(1.0, plan.target.x)) * facing.sign, z: plan.target.z * 0.4 * facing.sign)
            for scale in [1.0, 1.15, 0.9, 1.3] {
                let retry = ShotSolver.solve(origin: origin, facing: facing, speed: plan.speed * scale, spin: plan.spin,
                                             target: safe, arc: plan.arc)
                if retry.landing != nil { solution = retry; break }
            }
        }
        history.removeAll()
        if p == .opponent { pending = nil }       // a valid return cancels any "winner" in the making
        ball = BallState(position: origin, velocity: solution.velocity, spin: facing.toWorld(finalSpin.vector))
        rally.lastHitter = p
        rally.hits += 1
        rally.bounces = [.near: 0, .far: 0]
        rally.nearBounceTime = nil
        rally.isServe = false
        rallyCount += 1
        if rallyCount > 0, rallyCount % 5 == 0 { events.append(.rallyMilestone(rallyCount)) }
        stats.longestRally = max(stats.longestRally, rallyCount)
        if p == .human { noteHumanShot(swing, speed: plan.speed) }
        rally.incomingPressure = p == .opponent ? ShotModel.pressure(of: plan, stroke: swing.stroke) : 0
        reportShot(by: p, swing: swing, plan: plan, speed: plan.speed, isServe: false, timingOffset: timingOffset,
                   target: solution.landing)
        setSwingPose(p, swing: swing, at: clock - age, aim: plan.target.z * facing.sign)
        prepareReceiver(of: p, at: clock - age)
        if age > 0 { advanceBall(by: age) }
    }

    private func noteHumanShot(_ swing: SwingResult, speed: Double) {
        stats.record(stroke: swing.stroke, side: swing.side)
        stats.fastestShotKmh = max(stats.fastestShotKmh, speed * 3.6)
    }

    private func reportShot(by p: Player, swing: SwingResult, plan: ShotPlan, speed: Double, isServe: Bool,
                            timingOffset: Double, target: Vec3?) {
        if p == .human, plan.timing == .perfect { stats.perfectHits += 1 }
        let report = ShotReport(hitter: p, stroke: swing.stroke, side: swing.side, speedKmh: speed * 3.6,
                                topspin: clamp(plan.spin.top / ShotModel.maxSpin, -1, 1),
                                sidespin: clamp(plan.spin.side / ShotModel.maxSpin, -1, 1),
                                quality: plan.quality, timing: plan.timing, timingOffset: timingOffset,
                                power: plan.power, isServe: isServe, wrongSide: plan.wrongSide,
                                stretched: plan.stretched, target: target)
        events.append(.shot(report))
    }

    private func setSwingPose(_ p: Player, swing: SwingResult, at time: Double, aim: Double) {
        if p == .human {
            human.swingStart = time
            human.swingStroke = swing.stroke
            human.swingSide = swing.side
            human.swingDirection = aim
        } else {
            opp.swingStart = time
            opp.swingStroke = swing.stroke
            opp.swingSide = swing.side
            opp.swingDirection = aim
        }
    }

    // MARK: - Receiver planning

    /// After `hitter` struck the ball (at `time`), work out when/where the receiver will meet it.
    private func prepareReceiver(of hitter: Player, at time: Double) {
        let receiver = hitter.other
        strike = nil
        aiPlan = nil
        hint = nil
        if receiver == .human {
            guard var plan = predictStrike(from: ball, side: .near, at: time, isServe: rally.isServe) else { return }
            plan.hitTime = time
            plan.startZ = human.z
            strike = plan
            rally.nearBounceTime = nil
            hint = StrikeHint(idealTime: plan.apexTime + 0.02, position: plan.apexState.position)
            return
        }
        // The receiver is the opponent (a drill's ball machine never returns).
        guard !isDrill else { return }
        guard var plan = predictStrike(from: ball, side: .far, at: time, isServe: rally.isServe) else { return }
        plan.hitTime = time
        plan.startZ = opp.z
        let deficit = opponentReachDeficit(for: plan, from: time)
        let decision = OpponentBrain.decide(profile: opponent, ball: plan.apexState, apexX: plan.apexState.position.x,
                                            humanZ: human.z, reachDeficit: deficit,
                                            timeAvailable: plan.apexTime - time, rng: &rng)
        let hitTime = plan.apexTime + ShotModel.idealOffset(for: decision.swing.stroke)
        aiPlan = AIPlan(hitTime: hitTime, decision: decision, strike: plan)
    }

    /// How far the opponent has to stretch: lateral distance beyond what it can cover in time.
    private func opponentReachDeficit(for plan: StrikePlan, from time: Double) -> Double {
        let available = max(0, plan.apexTime - time - opponent.reaction)
        let travel = abs(plan.apexState.position.z - opp.z)
        return max(0, travel - (opponent.speed * available + 0.5))
    }

    /// Predicts the bounce and apex of the ball on `side` of the table.
    private func predictStrike(from state: BallState, side: CourtSide, at time: Double, isServe: Bool = false) -> StrikePlan? {
        var b = state
        var t = time
        var bounceTime: Double?
        var ownSideSeen = false
        var lastVy = b.velocity.y
        for _ in 0..<Int(2.6 / step) {
            let evs = BallPhysics.step(&b, dt: step)
            t += step
            for e in evs {
                switch e {
                case .tableBounce(let s, _, _):
                    if bounceTime == nil {
                        if s != side {
                            // A serve bounces on the server's own half first.
                            if isServe, !ownSideSeen { ownSideSeen = true; continue }
                            return nil
                        }
                        bounceTime = t
                    }
                case .netTouch(let kind):
                    if kind == .blocked { return nil }
                case .floorHit:
                    return nil
                }
            }
            if let bt = bounceTime, lastVy > 0, b.velocity.y <= 0 {
                return StrikePlan(bounceTime: bt, apexTime: t, apexState: b)
            }
            lastVy = b.velocity.y
        }
        return nil
    }

    // MARK: - Opponent

    private func runOpponentPlan() {
        guard let plan = aiPlan, rally.lastHitter == .human else { return }
        // Strike on schedule, or right now if the ball is about to get away.
        guard clock >= plan.hitTime || ball.position.x > 2.6 else { return }
        aiPlan = nil
        // The ball must have bounced on the far half.
        guard rally.bounces[.far, default: 0] >= 1 else { return }
        let decision = plan.decision
        let swing = decision.swing
        if decision.misses {
            // Swings and misses (or is too late): the ball carries on.
            setSwingPose(.opponent, swing: swing, at: clock, aim: 0)
            return
        }
        let state = ball
        let contact = decision.contact
        let aimLocal = decision.aim * Facing.towardNear.sign
        // Unforced errors are decided up front; otherwise the opponent controls the ball well.
        let errorOverride = decision.faulty ? 1.1 : decision.mods.baseError * 0.25
        let shot = ShotModel.plan(swing: swing, contact: contact, mods: decision.mods, aimOverride: aimLocal,
                                  errorOverride: errorOverride, rng: &rng)
        applyShot(by: .opponent, swing: swing, plan: shot, from: state, age: 0, timingOffset: contact.timingOffset,
                  deliberateError: decision.faulty)
    }

    // MARK: - Ball stepping and rules

    private func stepBall() {
        history.append((clock, ball))
        if history.count > 150 { history.removeFirst(history.count - 150) }
        let evs = BallPhysics.step(&ball, dt: step)
        for e in evs { process(e) }
    }

    /// Re-simulates `seconds` after a delayed hit (latency compensation).
    private func advanceBall(by seconds: Double) {
        let n = Int(seconds / step)
        guard n > 0 else { return }
        for i in 0..<n {
            guard case .rally = phase else { return }
            history.append((clock - seconds + Double(i + 1) * step, ball))
            let evs = BallPhysics.step(&ball, dt: step)
            for e in evs { process(e) }
        }
    }

    private func ballState(at t: Double) -> BallState {
        guard !history.isEmpty else { return ball }
        var best = history[0]
        var bd = abs(best.t - t)
        for e in history {
            let d = abs(e.t - t)
            if d < bd { best = e; bd = d }
        }
        return best.ball
    }

    private func process(_ e: PhysicsEvent) {
        guard case .rally = phase else { return }
        switch e {
        case .tableBounce(let side, let pos, _):
            events.append(.bounce(side: side, position: pos, isServe: rally.isServe))
            rally.bounces[side, default: 0] += 1
            guard let hitter = rally.lastHitter, pending == nil || pending!.cancellable else { return }
            let hitterSide = hitter.side
            let defenderSide = hitterSide.opposite
            if side == .near, hitter == .opponent, rally.bounces[.near] == 1 {
                rally.nearBounceTime = clock
                events.append(.ballOnYourSide)
            }

            if isDrill { drillBounce(side: side); return }

            if rally.isServe {
                if side == defenderSide {
                    if rally.bounces[hitterSide, default: 0] == 0 {
                        // Landed on the receiver's half without touching the server's: fault.
                        resolve(hitter.other, .serveFault, delay: 0.25)
                    } else if rally.netTouchedOnServe, rally.bounces[defenderSide] == 1 {
                        letServe()
                    }
                } else if rally.bounces[hitterSide, default: 0] > 1 {
                    resolve(hitter.other, .serveFault, delay: 0.25)
                }
                if side == defenderSide, rally.bounces[defenderSide, default: 0] >= 2 {
                    resolve(hitter, rally.hits <= 1 ? .ace : .winner, delay: hitter == .human ? 0.15 : 0.2)
                }
                return
            }

            if side == hitterSide {
                // Bounced on the hitter's own half after the hit.
                resolve(hitter.other, .ownSideBounce, delay: 0.25)
            } else if rally.bounces[defenderSide, default: 0] >= 2 {
                resolve(hitter, .doubleBounce, delay: hitter == .opponent ? config.missGrace * 0.5 : 0.2,
                        cancellable: hitter == .opponent)
            }

        case .netTouch(let kind):
            events.append(.netTouch(kind))
            if kind == .clip {
                if rally.isServe { rally.netTouchedOnServe = true }
            } else if let hitter = rally.lastHitter, pending == nil {
                if isDrill { drillFinish(.netOrOut); return }
                resolve(hitter.other, .net, delay: 0.3)
            }

        case .floorHit:
            guard let hitter = rally.lastHitter, pending == nil || pending!.cancellable else { return }
            if isDrill {
                drillFloor()
                return
            }
            let defenderSide = hitter.side.opposite
            if rally.isServe, rally.bounces[hitter.side, default: 0] == 0 {
                resolve(hitter.other, .serveFault, delay: 0.1)
            } else if rally.bounces[defenderSide, default: 0] >= 1 {
                let ace = rally.isServe || rally.hits <= 1
                resolve(hitter, ace ? .ace : .winner, delay: hitter == .opponent ? config.missGrace : 0.1,
                        cancellable: hitter == .opponent)
            } else {
                resolve(hitter.other, .out, delay: 0.1)
            }
        }
    }

    /// The ball went past the player (or the opponent) without being hit.
    private func checkBallPassed() {
        guard pending == nil, let hitter = rally.lastHitter else { return }
        if isDrill { return }
        // The opponent still intends to play the ball: not a winner yet.
        if hitter == .human, let plan = aiPlan, !plan.decision.misses { return }
        if hitter == .opponent, rally.bounces[.near, default: 0] >= 1, ball.position.x < -2.7 {
            let ace = rally.isServe || rally.hits <= 1
            resolve(.opponent, ace ? .ace : .winner, delay: config.missGrace, cancellable: true)
        } else if hitter == .human, rally.bounces[.far, default: 0] >= 1, ball.position.x > 2.7 {
            let ace = rally.isServe || rally.hits <= 1
            resolve(.human, ace ? .ace : .winner, delay: 0.15)
        }
    }

    private func resolve(_ winner: Player, _ reason: PointReason, delay: Double, cancellable: Bool = false) {
        guard pending == nil || pending!.cancellable else { return }
        if let p = pending, p.winner == winner { return }
        pending = Pending(winner: winner, reason: reason, deadline: clock + delay, cancellable: cancellable)
    }

    private func letServe() {
        guard let server = rally.lastHitter else { return }
        pending = nil
        events.append(.letServe)
        beginServeReady(server)
    }

    // MARK: - Points, games, match

    private func awardPoint(_ winner: Player, _ reason: PointReason) {
        switch phase {
        case .rally, .tossing, .serveReady: scorePoint(winner, reason)
        default: return
        }
    }

    private func scorePoint(_ winner: Player, _ reason: PointReason) {
        if isDrill { return }
        let updates = score.award(to: winner)
        let length = max(rallyCount, 0)
        if winner == .human {
            stats.pointsWon += 1
            switch reason {
            case .ace: stats.aces += 1
            case .winner, .doubleBounce:
                stats.winners += 1
                if rally.lastHumanStroke == .smash { stats.smashWinners += 1 }
            default: break
            }
        } else {
            stats.pointsLost += 1
            if rally.lastHitter == .human, reason == .out || reason == .net || reason == .ownSideBounce { stats.unforcedErrors += 1 }
            if reason == .tossFault || (reason == .serveFault && rally.server == .human) { stats.unforcedErrors += 1 }
        }
        stats.longestRally = max(stats.longestRally, length)
        events.append(.point(PointInfo(winner: winner, reason: reason, rallyLength: length,
                                       humanPoints: score.humanPoints, opponentPoints: score.opponentPoints)))
        hint = nil
        strike = nil
        aiPlan = nil
        pending = nil
        phase = .pointOver(winner: winner)
        phaseTimer = config.pointPause

        for u in updates {
            switch u {
            case .point: break
            case .gameWon(let w):
                if w == .human { stats.gamesWon += 1 } else { stats.gamesLost += 1 }
                events.append(.gameWon(winner: w, humanGames: score.humanGames, opponentGames: score.opponentGames))
                phase = .gameOver(winner: w)
                phaseTimer = config.gamePause
            case .matchWon(let w):
                events.append(.matchWon(winner: w))
                phase = .matchOver(winner: w)
                outcome = MatchOutcome(winner: w, humanGames: score.humanGames, opponentGames: score.opponentGames,
                                       gameScores: score.finishedGames.map { (human: $0.human, opponent: $0.opponent) },
                                       stats: stats, duration: matchTime, opponentID: opponent.id)
            }
        }
    }

    private func afterPoint() {
        let next = score.server
        if next != rally.server { events.append(.serverChanged(next)) }
        if isDrill { drillNext(); return }
        beginServeReady(next)
    }

    // MARK: - Drills (ball machine)

    private func drillNext() {
        guard let spec = drillSpec else { return }
        if drillAttempts >= spec.totalBalls {
            phase = .drillOver
            events.append(.drillComplete(successes: drillSuccesses, attempts: drillAttempts))
            return
        }
        beginServeReady(spec.kind == .serve ? .human : .opponent)
        if spec.kind != .serve { phaseTimer = 0.9 }
    }

    /// The machine "serves": a feed ball lands on the human's half.
    private func machineFeed() {
        guard let spec = drillSpec else { return }
        let feed = spec.feed(index: feedIndex, rng: &rng)
        feedIndex += 1
        let origin = Vec3(1.55, 0.35, 0)
        let sol = ShotSolver.solve(origin: origin, facing: .towardNear, speed: feed.speed, spin: feed.spin,
                                   target: (-feed.landingDepth, feed.landingZ), arc: feed.arc)
        history.removeAll()
        ball = BallState(position: origin, velocity: sol.velocity, spin: Facing.towardNear.toWorld(feed.spin.vector))
        phase = .rally
        rally.isServe = false
        rally.lastHitter = .opponent
        rally.hits = 1
        rally.bounces = [.near: 0, .far: 0]
        rally.nearBounceTime = nil
        rallyCount = 1
        events.append(.tossStarted(.opponent))
        prepareReceiver(of: .opponent, at: clock)
    }

    private func drillBounce(side: CourtSide) {
        guard let hitter = rally.lastHitter else { return }
        if hitter == .human, side == .far, rally.bounces[.far] == 1 {
            // A legal return (or a legal serve in the serve drill).
            let stroke = rally.lastHumanStroke ?? .drive
            var ok = drillSpec?.requiredStrokes.contains(stroke) ?? true
            if ok, let side = drillSpec?.requiredSide, side != .either {
                ok = rally.lastHumanSide == side || rally.lastHumanSide == .either
            }
            drillFinish(ok ? .success : .wrongStroke)
        } else if hitter == .human, side == .near, !(drillSpec?.kind == .serve) {
            drillFinish(.netOrOut)
        } else if hitter == .human, side == .near, drillSpec?.kind == .serve, rally.bounces[.near, default: 0] > 1 {
            drillFinish(.netOrOut)
        }
    }

    private func drillFloor() {
        guard let hitter = rally.lastHitter else { return }
        drillFinish(hitter == .human ? .netOrOut : .missed)
    }

    private func drillFinish(_ outcome: DrillOutcome) {
        guard case .rally = phase else { return }
        drillAttempts += 1
        if outcome == .success { drillSuccesses += 1 }
        events.append(.drill(outcome, successes: drillSuccesses, attempts: drillAttempts))
        hint = nil
        strike = nil
        pending = nil
        phase = .pointOver(winner: outcome == .success ? .human : .opponent)
        phaseTimer = 1.4
    }
}

// MARK: - Test hooks

extension MatchEngine {
    /// Starts a rally from an arbitrary ball (unit tests and scripted scenarios).
    func debugLaunch(ball newBall: BallState, hitter: Player, isServe: Bool = false) {
        rally = RallyState()
        rally.server = isServe ? hitter : hitter.other
        rally.isServe = isServe
        rally.lastHitter = hitter
        rally.hits = 1
        history.removeAll()
        ball = newBall
        ballVisible = true
        pending = nil
        phase = .rally
        rallyCount = 1
        prepareReceiver(of: hitter, at: clock)
    }
}
