import Foundation

/// What the opponent has decided to do with an incoming ball.
public struct AIDecision: Sendable {
    public var swing: SwingResult
    public var contact: ContactInfo
    public var mods: ShotModifiers
    /// -1...1 aim across the table (hitter coordinates).
    public var aim: Double
    /// The opponent will fail to get it back.
    public var misses: Bool
    /// The opponent gets a racket on it but makes an unforced error (net / long / wide).
    public var faulty: Bool
}

/// Decides how each playing style answers a ball: which stroke, how hard, where,
/// and whether the execution fails. Pure and deterministic given an RNG.
public enum OpponentBrain {
    public static func mods(for p: OpponentProfile) -> ShotModifiers {
        ShotModifiers(speed: 1.0, spin: 0.75 + 0.4 * p.spin,
                      error: 1.45 - 0.95 * p.consistency, window: 1.0, placement: p.placement,
                      baseError: 1.3 * pow(max(0.02, 1 - p.consistency), 1.1))
    }

    /// How hard is the incoming ball to deal with (0 easy ... 1 very hard)?
    static func difficulty(of ball: BallState) -> Double {
        let speedPart = clamp((ball.speed - 6) / 10)
        let spinPart = clamp(abs(ShotModel.topspinAmount(of: ball)) / 450)
        let sidePart = clamp(abs(ball.spin.y) / 400)
        return clamp(0.5 * speedPart + 0.3 * spinPart + 0.2 * sidePart)
    }

    /// - Parameters:
    ///   - ball: the ball at the moment the opponent will strike it (hitter coordinates are applied by the engine).
    ///   - apexX: distance of the strike from the net (short balls are played differently).
    ///   - humanZ: where the human currently stands (the opponent aims away from them).
    ///   - reachDeficit: how far beyond comfortable reach the ball is.
    public static func decide(profile p: OpponentProfile, ball: BallState, apexX: Double, humanZ: Double,
                              reachDeficit: Double, timeAvailable: Double = 1, rng: inout SeededRNG) -> AIDecision {
        let height = ball.position.y
        let diff = difficulty(of: ball)
        let incomingTop = ShotModel.topspinAmount(of: ball)
        let isShort = abs(apexX) < 0.95
        let pressure = clamp(diff + 0.5 * reachDeficit)

        var stroke: StrokeKind
        let roll = rng.unit()
        let bigChance = p.aggression * clamp(0.4 + (height - 0.18) * 3)

        switch p.style {
        case .chopper:
            if height > 0.38, roll < p.aggression * 1.5 { stroke = .smash }
            else if isShort { stroke = roll < 0.65 ? .push : .drop }
            else if pressure > 0.65, roll < p.defence * 0.5 { stroke = .lob }
            else { stroke = roll < 0.80 ? .chop : (roll < 0.92 ? .block : .push) }
        case .hardHitter:
            if height > 0.30, roll < 0.9 { stroke = .smash }
            else if isShort { stroke = roll < 0.5 ? .flick : .push }
            else if pressure > 0.7 { stroke = roll < 0.5 ? .block : .lob }
            else { stroke = roll < 0.60 ? .drive : (roll < 0.85 ? .topspin : .block) }
        case .looper:
            if height > 0.34, roll < bigChance { stroke = .smash }
            else if isShort { stroke = roll < 0.55 ? .flick : (roll < 0.8 ? .push : .topspin) }
            else if pressure > 0.75 { stroke = roll < 0.6 ? .block : .chop }
            else { stroke = roll < 0.72 ? .topspin : (roll < 0.9 ? .drive : .block) }
        case .blocker:
            stroke = isShort ? .push : (roll < 0.75 ? .block : .drive)
        case .champion:
            if height > 0.30, roll < 0.75 { stroke = .smash }
            else if isShort { stroke = roll < 0.45 ? .flick : (roll < 0.8 ? .push : .drop) }
            else if pressure > 0.8 { stroke = roll < 0.5 ? .block : (roll < 0.8 ? .chop : .lob) }
            else { stroke = roll < 0.50 ? .topspin : (roll < 0.78 ? .drive : (roll < 0.9 ? .block : .chop)) }
        case .allRound:
            if height > 0.34, roll < bigChance { stroke = .smash }
            else if isShort { stroke = roll < 0.6 ? .push : .drop }
            else if pressure > 0.7 { stroke = roll < 0.5 ? .block : (roll < 0.8 ? .chop : .lob) }
            else { stroke = roll < 0.35 ? .topspin : (roll < 0.72 ? .drive : (roll < 0.87 ? .block : .chop)) }
        }

        // Against heavy backspin a drive/block usually nets: good players lift it.
        if incomingTop < -150, stroke == .drive || stroke == .block, rng.unit() < p.consistency { stroke = .topspin }

        let power = clamp(p.power * (0.7 + 0.35 * rng.unit()) + (stroke == .smash ? 0.25 : 0))
        let topspinAmount: Double
        switch stroke {
        case .topspin: topspinAmount = 0.35 + 0.6 * p.spin
        case .chop, .push: topspinAmount = -(0.5 + 0.4 * p.spin)
        default: topspinAmount = 0.1
        }
        let sidespin: Double = stroke == .flick ? (rng.chance(0.5) ? 1 : -1) * (0.5 + 0.5 * p.spin) : 0

        let swing = SwingResult(stroke: stroke, side: rng.chance(0.55) ? .forehand : .backhand,
                                power: power, speed: 3 + 4 * power, topspin: topspinAmount, sidespin: sidespin,
                                confidence: 1, timestamp: 0, duration: 0.15)

        // Aim away from where the human stands; better placement = nearer the lines.
        var aim: Double
        if rng.chance(0.25 + 0.6 * p.placement) {
            let awaySign: Double = humanZ >= 0 ? -1 : 1
            aim = awaySign * (0.5 + 0.5 * p.placement) * (0.7 + 0.3 * rng.unit())
        } else {
            aim = rng.range(-0.5, 0.5)
        }
        if stroke == .lob || stroke == .chop { aim *= 0.5 }

        // Execution.
        let timingOffset = rng.gaussian(sigma: 0.10 * max(0.05, 1.05 - p.consistency))
        let contact = ContactInfo(timingOffset: timingOffset, ballHeight: height, ballSpeed: ball.speed,
                                  incomingTopspin: incomingTop, reachDeficit: reachDeficit, wrongSide: false,
                                  timeAvailable: timeAvailable)
        let execution = p.consistency - 0.8 * diff - 0.8 * reachDeficit + rng.gaussian(sigma: 0.12)
        let misses = execution < 0.15
        let faultChance = 0.9 * pow(max(0.02, 1 - p.consistency), 1.15) * (0.6 + diff)
        let faulty = !misses && rng.chance(faultChance)

        return AIDecision(swing: swing, contact: contact, mods: mods(for: p), aim: clamp(aim, -1, 1), misses: misses, faulty: faulty)
    }

    /// How the opponent serves.
    public static func serve(profile p: OpponentProfile, humanZ: Double, rng: inout SeededRNG) -> AIDecision {
        let roll = rng.unit()
        let stroke: StrokeKind
        switch p.style {
        case .chopper: stroke = roll < 0.6 ? .push : (roll < 0.85 ? .chop : .drive)
        case .hardHitter: stroke = roll < 0.55 ? .drive : (roll < 0.8 ? .smash : .topspin)
        case .looper, .champion:
            stroke = roll < 0.35 ? .flick : (roll < 0.6 ? .push : (roll < 0.85 ? .topspin : .drive))
        case .allRound, .blocker: stroke = roll < 0.4 ? .drive : (roll < 0.7 ? .topspin : .push)
        }
        // Beginners rarely vary their serve.
        let chosen: StrokeKind = rng.chance(0.3 + 0.7 * p.serveSkill) ? stroke : .drive
        let power = clamp(p.power * 0.8 + 0.1 + (chosen == .smash ? 0.2 : 0))
        let swing = SwingResult(stroke: chosen, side: .forehand, power: power, speed: 3 + 3 * power,
                                topspin: chosen == .topspin ? 0.6 : (chosen == .push || chosen == .chop ? -0.7 : 0.1),
                                sidespin: chosen == .flick ? (rng.chance(0.5) ? 1 : -1) * 0.8 : 0,
                                confidence: 1, timestamp: 0, duration: 0.15)
        let awaySign: Double = humanZ >= 0 ? -1 : 1
        let aim = rng.chance(0.3 + 0.5 * p.placement) ? awaySign * (0.4 + 0.5 * p.placement) : rng.range(-0.4, 0.4)
        let contact = ContactInfo(timingOffset: rng.gaussian(sigma: 0.04 * (1.2 - p.consistency)))
        return AIDecision(swing: swing, contact: contact, mods: mods(for: p), aim: aim, misses: false, faulty: false)
    }
}
