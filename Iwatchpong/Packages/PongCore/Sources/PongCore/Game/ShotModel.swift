import Foundation

/// How the ball arrives at the paddle.
public struct ContactInfo: Sendable {
    /// Seconds relative to the ideal moment of contact (negative = early).
    public var timingOffset: Double
    /// Ball height above the table at contact.
    public var ballHeight: Double
    public var ballSpeed: Double
    /// Incoming spin relative to its direction of travel (+ topspin, - backspin), rad/s.
    public var incomingTopspin: Double
    /// Metres beyond comfortable reach (0 = no stretch).
    public var reachDeficit: Double
    public var wrongSide: Bool
    /// Seconds between the opponent's hit and the ideal moment of contact (little time = rushed).
    public var timeAvailable: Double
    /// How hard the incoming shot was to deal with (0...1): pace, spin and how wide it was placed.
    public var pressure: Double

    public init(timingOffset: Double, ballHeight: Double = 0.2, ballSpeed: Double = 8, incomingTopspin: Double = 0,
                reachDeficit: Double = 0, wrongSide: Bool = false, timeAvailable: Double = 1, pressure: Double = 0) {
        self.timeAvailable = timeAvailable
        self.pressure = pressure
        self.timingOffset = timingOffset
        self.ballHeight = ballHeight
        self.ballSpeed = ballSpeed
        self.incomingTopspin = incomingTopspin
        self.reachDeficit = reachDeficit
        self.wrongSide = wrongSide
    }
}

/// Player/AI skill modifiers for the shot model.
public struct ShotModifiers: Sendable {
    public var speed = 1.0
    public var spin = 1.0
    /// Scales errors (lower = better).
    public var error = 1.0
    /// Scales the timing window (higher = more forgiving).
    public var window = 1.0
    /// How well shots are aimed (0...1).
    public var placement = 0.5
    /// Error that even a perfect contact has (human variance, nerves, a rushed ball).
    public var baseError = 0.05

    public init(speed: Double = 1, spin: Double = 1, error: Double = 1, window: Double = 1, placement: Double = 0.5,
                baseError: Double = 0.05) {
        self.speed = speed
        self.spin = spin
        self.error = error
        self.window = window
        self.placement = placement
        self.baseError = baseError
    }

    public init(upgrades u: PlayerUpgrades) {
        self.init(speed: u.speedMultiplier, spin: u.spinMultiplier, error: u.errorMultiplier,
                  window: u.timingWindowMultiplier, placement: 0.5 + 0.04 * Double(u.control),
                  baseError: max(0.02, 0.07 - 0.004 * Double(u.control)))
    }
}

public struct ShotPlan: Sendable {
    public var speed: Double
    public var spin: SpinSpec
    /// Where the ball should land, in the hitter's coordinates (x' toward the opponent).
    public var target: (x: Double, z: Double)
    public var arc: Arc
    public var quality: Double
    public var timing: TimingLabel
    public var power: Double
    public var wrongSide: Bool
    public var stretched: Bool
}

/// Turns a recognised stroke and the way the ball arrives into a physical shot:
/// launch speed, spin, aim and an error that depends on how good the contact was.
public enum ShotModel {
    public static let baseTimingWindow = 0.20
    public static let maxSpin = 460.0

    /// Spin of a ball relative to its direction of travel (+ topspin, - backspin), rad/s.
    public static func topspinAmount(of ball: BallState) -> Double {
        let h = Vec3(ball.velocity.x, 0, ball.velocity.z)
        guard h.magnitude > 0.1 else { return 0 }
        let axis = Vec3(0, 1, 0).cross(h.normalized)
        return ball.spin.dot(axis)
    }

    /// Where, relative to the apex of the bounce, each stroke is best played.
    public static func idealOffset(for stroke: StrokeKind) -> Double {
        switch stroke {
        case .drive, .topspin, .block, .flick, .push, .drop: return 0.02
        case .chop: return 0.10          // the chopper takes the ball later, on its way down
        case .lob: return 0.08
        case .smash: return 0.05
        }
    }

    public static func timingLabel(offset: Double, window: Double = 1) -> TimingLabel {
        let a = abs(offset)
        if a <= 0.045 * window { return .perfect }
        if a <= 0.095 * window { return .good }
        return offset < 0 ? .early : .late
    }

    /// Overall contact quality 0...1.
    public static func quality(swing: SwingResult, contact c: ContactInfo, mods: ShotModifiers) -> Double {
        let window = baseTimingWindow * mods.window
        let timingQ = pow(max(0, 1 - abs(c.timingOffset) / window), 1.2)

        var heightQ: Double
        let h = c.ballHeight
        if h < 0.05 {
            heightQ = clamp(1 - (0.05 - h) / 0.12)
        } else if h <= 0.32 {
            heightQ = 1
        } else {
            heightQ = clamp(1 - (h - 0.32) / 0.5)
        }
        if swing.stroke == .smash {
            heightQ = h >= 0.26 ? 1 : clamp(0.4 + (h - 0.05) * 2.5)
        } else if swing.stroke == .lob {
            heightQ = max(heightQ, 0.8)
        }

        let reachQ = clamp(1 - c.reachDeficit / 0.4)
        let sideQ = c.wrongSide && swing.side != .either ? 0.7 : 1.0
        // Fast balls leave little time to react: rushed contact is worse contact.
        let paceQ = 1 - 0.35 * clamp((c.ballSpeed - 9) / 12) - 0.35 * clamp((0.5 - c.timeAvailable) / 0.3)

        // Spin handling: playing the wrong stroke against heavy spin is hard.
        var spinQ = 1.0
        let incoming = c.incomingTopspin
        if incoming < -120 {            // heavy backspin: needs lift
            switch swing.stroke {
            case .topspin, .push, .lob, .flick: spinQ = 1.0
            case .drive: spinQ = 0.85
            case .block, .smash: spinQ = 0.7
            default: spinQ = 0.9
            }
        } else if incoming > 160 {      // heavy topspin: needs control
            switch swing.stroke {
            case .block, .chop, .lob, .topspin: spinQ = 1.0
            case .drive, .smash: spinQ = 0.85
            case .push, .drop: spinQ = 0.7
            default: spinQ = 0.9
            }
        }

        let confidence = 0.88 + 0.12 * swing.confidence
        // Being stretched wide hurts badly.
        let stretch = max(0, c.reachDeficit - 0.1)
        let stretchFactor = 1 - min(0.6, 1.2 * stretch)
        let pressureFactor = 1 - 0.45 * clamp(c.pressure)
        let q = stretchFactor * pressureFactor * (0.36 * timingQ + 0.20 * heightQ + 0.20 * reachQ + 0.08 * sideQ + 0.10 * paceQ + 0.06 * spinQ) * confidence
        return clamp(q)
    }

    /// How hard a shot is to return (0...1): pace, spin and wide placement.
    public static func pressure(of plan: ShotPlan, stroke: StrokeKind) -> Double {
        let pace = 0.5 * clamp((plan.speed - 9) / 9)
        let spin = 0.25 * clamp(abs(plan.spin.top) / 450) + 0.2 * clamp(abs(plan.spin.side) / 400)
        let wide = 0.25 * clamp(abs(plan.target.z) / 0.6)
        let smash = stroke == .smash ? 0.2 : 0
        return clamp(pace + spin + wide + smash)
    }

    /// A rally shot.
    public static func plan(swing: SwingResult, contact c: ContactInfo, mods: ShotModifiers,
                            aimOverride: Double? = nil, errorOverride: Double? = nil, rng: inout SeededRNG) -> ShotPlan {
        let q = quality(swing: swing, contact: c, mods: mods)
        let timing = timingLabel(offset: c.timingOffset, window: mods.window)
        // Weak contact also takes power off the stroke.
        let p = clamp(swing.power * (0.65 + 0.35 * q))
        let tAmt = swing.topspin
        var speed = 8.0
        var top = 0.0
        var side = 0.0
        var depth = 0.9
        var arc = Arc.low

        switch swing.stroke {
        case .drive:
            speed = 8 + 7 * p
            top = 40 + 80 * p
            depth = 0.70 + 0.45 * p
        case .topspin:
            speed = 7 + 6 * p
            top = (170 + 280 * p) * (0.7 + 0.3 * abs(tAmt))
            depth = 0.80 + 0.40 * p
        case .chop:
            speed = 5.0 + 3.0 * p
            top = -(150 + 200 * max(0.4, abs(tAmt)))
            depth = 0.70 + 0.35 * p
        case .push:
            speed = 4.6 + 1.8 * p
            top = -(110 + 120 * p)
            depth = 0.30 + 0.30 * p
        case .smash:
            speed = 15 + 10 * p
            top = 60 + 60 * p
            depth = 0.95 + 0.30 * p
        case .lob:
            speed = 5.5 + 2.5 * p
            top = 40 + 80 * max(0, tAmt)
            depth = 0.95 + 0.20 * p
            arc = .high
        case .block:
            speed = clamp(0.5 * c.ballSpeed + 1.5 + 2 * p, 4.2, 11)
            top = -0.3 * c.incomingTopspin
            depth = 0.55 + 0.30 * p
        case .drop:
            speed = 4.2 + 1.2 * p
            top = -(50 + 60 * p)
            depth = 0.15 + 0.22 * p
        case .flick:
            speed = 6 + 4 * p
            top = 60
            let dir: Double = swing.sidespin >= 0 ? 1 : -1
            side = dir * (210 + 260 * p)
            depth = 0.85 + 0.20 * p
        }

        speed *= mods.speed
        top *= mods.spin
        side *= mods.spin
        top = max(-maxSpin, min(maxSpin, top))
        side = max(-maxSpin, min(maxSpin, side))

        // Aim: swing earlier to aim right, later to aim left (like a real brush-through).
        let aim = aimOverride ?? clamp(-c.timingOffset / 0.15, -1, 1)
        var targetZ = aim * 0.5 * (0.55 + 0.45 * mods.placement)
        var targetX = depth

        // Errors grow as contact quality falls.
        let err = errorOverride ?? max(pow(1 - q, 0.9) * mods.error, mods.baseError)
        targetX += rng.gaussian(sigma: 0.85 * err)
        targetZ += rng.gaussian(sigma: 0.60 * err)
        speed *= 1 + rng.gaussian(sigma: 0.10 * err)
        targetX = max(0.08, min(1.55, targetX))
        targetZ = max(-0.72, min(0.72, targetZ))

        return ShotPlan(speed: max(2, speed), spin: SpinSpec(top: top, side: side),
                        target: (targetX, targetZ), arc: arc, quality: q, timing: timing,
                        power: p, wrongSide: c.wrongSide, stretched: c.reachDeficit > 0.05)
    }

    /// A serve: the stroke chooses the serve type.
    public static func servePlan(swing: SwingResult, timingOffset: Double, mods: ShotModifiers,
                                 aimOverride: Double? = nil, rng: inout SeededRNG) -> ShotPlan {
        let contact = ContactInfo(timingOffset: timingOffset, ballHeight: 0.2)
        let q = quality(swing: swing, contact: contact, mods: mods)
        let timing = timingLabel(offset: timingOffset, window: mods.window)
        let p = clamp(swing.power * (0.65 + 0.35 * q))
        var speed = 6.0
        var top = 0.0
        var side = 0.0
        var depth = 0.9

        switch swing.stroke {
        case .drive:                       // fast flat serve
            speed = 7 + 3 * p
            top = 40
            depth = 1.15
        case .topspin:                     // topspin serve
            speed = 6 + 2.5 * p
            top = 200 + 220 * p
            depth = 1.05
        case .chop, .push:                 // short backspin serve
            speed = 3.4 + 1.4 * p
            top = -(180 + 150 * p)
            depth = 0.40 + 0.2 * p
        case .flick:                       // sidespin serve
            speed = 5 + 2.5 * p
            top = 60
            side = (swing.sidespin >= 0 ? 1.0 : -1.0) * (260 + 200 * p)
            depth = 0.85
        case .smash:                       // fast, aggressive, risky
            speed = 9.5 + 3 * p
            top = 60
            depth = 1.25
        case .lob:                         // slow topspin
            speed = 4.8 + 1.4 * p
            top = 120
            depth = 1.0
        case .block, .drop:                // short touch serve
            speed = 3.0 + 1.0 * p
            top = -80
            depth = 0.32
        }

        speed *= mods.speed
        top *= mods.spin
        side *= mods.spin
        top = max(-maxSpin, min(maxSpin, top))
        side = max(-maxSpin, min(maxSpin, side))

        let aim = aimOverride ?? clamp(-timingOffset / 0.15, -1, 1)
        var targetZ = aim * 0.45 * (0.55 + 0.45 * mods.placement)
        var targetX = depth
        let err = max(pow(1 - q, 0.9) * mods.error, mods.baseError)
        targetX = max(0.2, min(1.3, targetX + rng.gaussian(sigma: 0.60 * err)))
        targetZ = max(-0.65, min(0.65, targetZ + rng.gaussian(sigma: 0.45 * err)))

        return ShotPlan(speed: max(2.5, speed), spin: SpinSpec(top: top, side: side),
                        target: (targetX, targetZ), arc: .low, quality: q, timing: timing,
                        power: p, wrongSide: false, stretched: false)
    }
}
