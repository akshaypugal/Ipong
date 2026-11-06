import Foundation

public enum SwingRejection: String, Sendable {
    case weak
    case tooShort
    case tooLong
    case implausible
    case lowConfidence
    case cooldown
    case rateLimited
    case retract
    case backswing
}

/// Summary of one burst of wrist acceleration, after peak detection.
public struct SwingFeatures: Equatable, Sendable {
    /// Peak filtered acceleration magnitude, g.
    public var peak: Double
    /// Hand speed estimate, m/s.
    public var speed: Double
    public var duration: Double
    /// Vertical share of the swing direction: +1 straight up, -1 straight down.
    public var verticalFraction: Double
    /// Signed rotation about the vertical axis accumulated over the burst, rad.
    public var yawIntegral: Double
    public var peakYaw: Double
    public var peakGyro: Double
    /// Unit direction of the burst in the world frame.
    public var direction: Vec3
    public var peakTime: Double

    public init(peak: Double, speed: Double, duration: Double, verticalFraction: Double,
                yawIntegral: Double, peakYaw: Double, peakGyro: Double, direction: Vec3 = .zero, peakTime: Double = 0) {
        self.peak = peak
        self.speed = speed
        self.duration = duration
        self.verticalFraction = verticalFraction
        self.yawIntegral = yawIntegral
        self.peakYaw = peakYaw
        self.peakGyro = peakGyro
        self.direction = direction
        self.peakTime = peakTime
    }
}

public enum SwingClassification: Equatable, Sendable {
    case swing(SwingResult)
    case toss(confidence: Double)
    case rejected(SwingRejection)
}

/// Pure function from burst features to a stroke. No state, no sensors.
public enum SwingClassifier {
    public static func classify(_ f: SwingFeatures, config c: SwingConfig, calibration cal: SwingCalibration) -> SwingClassification {
        if f.peak > c.maxPeak { return .rejected(.implausible) }
        if f.peak < c.minPeak { return .rejected(.weak) }
        if f.duration < c.minDuration { return .rejected(.tooShort) }
        if f.duration > c.maxDuration { return .rejected(.tooLong) }

        let vf = f.verticalFraction
        let hasYaw = f.peakYaw >= c.yawSideMin

        // Serve toss: a clean upward lift without wrist rotation.
        if vf >= c.tossVerticalFrac, f.peak <= c.tossMaxPeak, f.peakYaw < c.tossMaxYaw {
            return .toss(confidence: clamp(0.55 + 0.4 * (vf - c.tossVerticalFrac) / (1 - c.tossVerticalFrac)))
        }

        // Which side? Wrist rotation through the swing: forehand sweeps one way, backhand the other.
        var side = StrokeSide.either
        if hasYaw {
            var s = f.yawIntegral * cal.forehandYawSign
            if c.mirror { s = -s }
            side = s >= 0 ? .forehand : .backhand
        }

        let power = clamp(0.5 * f.peak / (cal.drivePeak * 1.4) + 0.5 * f.speed / c.speedReference)
        let topspin = vf >= 0 ? clamp(vf * 1.5) : -clamp(-vf * 1.5)
        var sidespin = 0.0

        let stroke: StrokeKind
        if f.peak >= c.smashMin, vf >= c.smashMinVertical, vf <= c.smashMaxVertical {
            stroke = .smash
        } else if vf >= c.lobVerticalFrac, f.peak >= c.minPeak {
            stroke = .lob
        } else if f.peakGyro >= c.flickGyroMin, f.peak >= c.flickMin, f.peak <= c.flickMax, abs(vf) < 0.3 {
            stroke = .flick
            sidespin = clamp(f.peakGyro / 18) * (f.yawIntegral * cal.forehandYawSign >= 0 ? 1 : -1) * (c.mirror ? -1 : 1)
        } else if vf >= c.topspinVerticalFrac, f.peak >= c.driveMin {
            stroke = .topspin
        } else if vf <= c.chopVerticalFrac {
            stroke = f.peak >= c.pushMax ? .chop : .push
        } else if f.peak <= c.blockMax, f.duration <= c.blockMaxDuration {
            stroke = .block
        } else if f.peak <= c.dropMax {
            stroke = .drop
        } else if f.peak >= c.driveMin {
            stroke = .drive
        } else {
            return .rejected(.weak)
        }

        let confidence = clamp(0.5 + 0.25 * clamp(f.peak / (c.minPeak * 2.5)) + 0.25 * (hasYaw || stroke == .block || stroke == .drop ? 1 : 0.6))
        if confidence < c.confidenceMin { return .rejected(.lowConfidence) }

        return .swing(SwingResult(stroke: stroke, side: side, power: power, speed: f.speed,
                                  topspin: topspin, sidespin: sidespin, confidence: confidence,
                                  timestamp: f.peakTime + c.contactOffset, duration: f.duration))
    }
}
