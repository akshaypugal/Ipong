import Foundation

/// All tunable thresholds of the swing recogniser. Accelerations are user
/// acceleration (gravity removed) in g, rotation in rad/s, times in seconds.
/// Defaults are a first guess that behaves with synthetic motion; tune them on a
/// real Watch with the Debug screen.
public struct SwingConfig: Codable, Equatable, Sendable {
    // Filtering / burst detection
    public var smoothing: Double = 0.55
    /// A burst is tracked from this low level so that its duration reflects the whole lobe.
    public var startThreshold: Double = 0.45
    public var peakDropRatio: Double = 0.70
    public var minDuration: Double = 0.04
    public var maxDuration: Double = 0.9
    public var speedCompensation: Double = 1.3
    /// The ball is struck roughly this long after the acceleration peak.
    public var contactOffset: Double = 0.05

    // Validation / anti-cheat
    public var minPeak: Double = 1.0
    public var maxPeak: Double = 24
    public var confidenceMin: Double = 0.4
    /// Minimum time between two recognised swings.
    public var cooldown: Double = 0.35
    public var maxSwingsPerSecond: Int = 3
    public var retractDot: Double = -0.2
    public var recovery: Double = 0.35

    // Backswing suppression: every stroke waits this long to see whether a stronger
    // opposite burst follows (then it was only the backswing).
    public var confirmDelay: Double = 0.18

    // Stroke classification
    /// Rotation (rad/s peak) needed to call a swing forehand/backhand.
    public var yawSideMin: Double = 2.0
    public var tossVerticalFrac: Double = 0.72
    public var tossMaxPeak: Double = 3.0
    public var tossMaxYaw: Double = 3.5
    public var lobVerticalFrac: Double = 0.55
    public var topspinVerticalFrac: Double = 0.22
    public var chopVerticalFrac: Double = -0.28
    public var driveMin: Double = 1.8
    public var smashMin: Double = 5.2
    public var smashMinVertical: Double = -0.6
    public var smashMaxVertical: Double = 0.30
    public var blockMax: Double = 2.2
    public var blockMaxDuration: Double = 0.10
    public var dropMax: Double = 2.0
    public var pushMax: Double = 1.9
    public var flickGyroMin: Double = 9.0
    public var flickMin: Double = 1.2
    public var flickMax: Double = 4.5

    // Quality scoring
    public var speedReference: Double = 6.0

    /// Swap forehand and backhand (e.g. watch worn on the other wrist than calibrated).
    public var mirror: Bool = false

    public init() {}

    public static let `default` = SwingConfig()
}

/// What the recogniser learns about this player and wrist.
public struct SwingCalibration: Codable, Equatable, Sendable {
    public var gyroBias: Vec3
    public var noiseFloor: Double
    public var neutralGravity: Vec3
    /// Sign of the wrist's yaw rotation during a forehand: +1 for a right-hander
    /// wearing the Watch on the right wrist (counter-clockwise seen from above).
    public var forehandYawSign: Double
    /// This player's natural forehand drive peak (g). Power is relative to it.
    public var drivePeak: Double
    public var hasNeutral: Bool
    public var hasStrokes: Bool
    public var createdAt: TimeInterval

    public init(gyroBias: Vec3 = .zero, noiseFloor: Double = 0.02, neutralGravity: Vec3 = Vec3(0, 0, -1),
                forehandYawSign: Double = 1, drivePeak: Double = 4.0,
                hasNeutral: Bool = false, hasStrokes: Bool = false, createdAt: TimeInterval = 0) {
        self.gyroBias = gyroBias
        self.noiseFloor = noiseFloor
        self.neutralGravity = neutralGravity
        self.forehandYawSign = forehandYawSign >= 0 ? 1 : -1
        self.drivePeak = drivePeak
        self.hasNeutral = hasNeutral
        self.hasStrokes = hasStrokes
        self.createdAt = createdAt
    }

    public static let `default` = SwingCalibration()

    public var isCalibrated: Bool { hasNeutral && hasStrokes }
}
