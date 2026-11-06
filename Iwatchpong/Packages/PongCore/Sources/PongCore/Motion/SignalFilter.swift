import Foundation

/// Exponential moving average for scalars.
public struct EMAFilter: Sendable {
    public var alpha: Double
    private var value: Double?

    public init(alpha: Double) { self.alpha = alpha }

    public mutating func apply(_ x: Double) -> Double {
        guard let v = value else {
            value = x
            return x
        }
        let y = alpha * x + (1 - alpha) * v
        value = y
        return y
    }

    public mutating func reset() { value = nil }
}

/// Exponential moving average for vectors.
public struct Vec3EMA: Sendable {
    public var alpha: Double
    private var value: Vec3?

    public init(alpha: Double) { self.alpha = alpha }

    public mutating func apply(_ v: Vec3) -> Vec3 {
        guard let prev = value else {
            value = v
            return v
        }
        let y = v * alpha + prev * (1 - alpha)
        value = y
        return y
    }

    public mutating func reset() { value = nil }
}

/// Component-wise median of the last three samples. Removes isolated one-sample
/// spikes (sensor glitches) while keeping real, multi-sample motion intact.
public struct MedianFilter3: Sendable {
    private var a: Vec3?
    private var b: Vec3?

    public init() {}

    private static func med(_ x: Double, _ y: Double, _ z: Double) -> Double {
        max(min(x, y), min(max(x, y), z))
    }

    public mutating func apply(_ v: Vec3) -> Vec3 {
        defer {
            a = b
            b = v
        }
        guard let p2 = a, let p1 = b else { return v }
        return Vec3(Self.med(p2.x, p1.x, v.x), Self.med(p2.y, p1.y, v.y), Self.med(p2.z, p1.z, v.z))
    }

    public mutating func reset() {
        a = nil
        b = nil
    }
}
