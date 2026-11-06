import Foundation

/// One reading from the Watch's fused device-motion stream.
///
/// The Watch layer (CoreMotion) fills this in; everything after it is pure Swift.
public struct MotionSample: Codable, Equatable, Sendable {
    /// Wall-clock time (unix seconds) of the reading.
    public var timestamp: TimeInterval
    /// User acceleration in the device frame, in g, gravity removed.
    public var userAccel: Vec3
    /// Gravity direction in the device frame (unit-ish, in g).
    public var gravity: Vec3
    /// Angular velocity in the device frame, rad/s.
    public var rotationRate: Vec3
    /// User acceleration in the world frame (z up, x/y arbitrary-but-constant heading), in g.
    public var worldAccel: Vec3

    public init(timestamp: TimeInterval,
                userAccel: Vec3,
                gravity: Vec3,
                rotationRate: Vec3,
                worldAccel: Vec3) {
        self.timestamp = timestamp
        self.userAccel = userAccel
        self.gravity = gravity
        self.rotationRate = rotationRate
        self.worldAccel = worldAccel
    }
}

/// 3x3 rotation matrix, row-major (matches `CMRotationMatrix` m11...m33).
public struct RotationMatrix: Equatable, Sendable {
    public var m: [Double]

    public init(_ m11: Double, _ m12: Double, _ m13: Double,
                _ m21: Double, _ m22: Double, _ m23: Double,
                _ m31: Double, _ m32: Double, _ m33: Double) {
        m = [m11, m12, m13, m21, m22, m23, m31, m32, m33]
    }

    public static let identity = RotationMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1)

    public func multiply(_ v: Vec3) -> Vec3 {
        Vec3(m[0] * v.x + m[1] * v.y + m[2] * v.z,
             m[3] * v.x + m[4] * v.y + m[5] * v.z,
             m[6] * v.x + m[7] * v.y + m[8] * v.z)
    }

    public func transposedMultiply(_ v: Vec3) -> Vec3 {
        Vec3(m[0] * v.x + m[3] * v.y + m[6] * v.z,
             m[1] * v.x + m[4] * v.y + m[7] * v.z,
             m[2] * v.x + m[5] * v.y + m[8] * v.z)
    }
}

/// Converts device-frame vectors into the world frame.
///
/// Apple documents `CMAttitude.rotationMatrix` as describing the device attitude
/// relative to the reference frame, but whether it maps world->device or
/// device->world is easy to get backwards. Instead of trusting memory, this
/// mapper checks both conventions against the measured gravity vector for the
/// first `lockAfter` samples and then locks the one that agrees.
public struct WorldFrameMapper: Sendable {
    public enum Convention: Sendable {
        case worldToDevice
        case deviceToWorld
    }

    public private(set) var locked: Convention?
    public var lockAfter: Int = 120
    private var observed = 0
    private var errorWorldToDevice = 0.0
    private var errorDeviceToWorld = 0.0

    public init() {}

    public var best: Convention {
        errorWorldToDevice <= errorDeviceToWorld ? .worldToDevice : .deviceToWorld
    }

    public mutating func reset() {
        locked = nil
        observed = 0
        errorWorldToDevice = 0
        errorDeviceToWorld = 0
    }

    /// Maps `deviceVector` into the world frame (z up).
    public mutating func toWorld(_ deviceVector: Vec3, rotation: RotationMatrix, gravityDevice: Vec3) -> Vec3 {
        if locked == nil {
            let down = Vec3(0, 0, -1)
            errorWorldToDevice += (rotation.multiply(down) - gravityDevice).magnitude
            errorDeviceToWorld += (rotation.multiply(gravityDevice) - down).magnitude
            observed += 1
            if observed >= lockAfter { locked = best }
        }
        switch locked ?? best {
        case .worldToDevice: return rotation.transposedMultiply(deviceVector)
        case .deviceToWorld: return rotation.multiply(deviceVector)
        }
    }
}
