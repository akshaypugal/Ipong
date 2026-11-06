import Foundation

/// Clamp `v` into `lo...hi` (defaults to 0...1).
@inline(__always)
public func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
    min(max(v, lo), hi)
}

/// Minimal 3-vector used by the motion and gesture layers.
public struct Vec3: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double = 0, _ y: Double = 0, _ z: Double = 0) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }

    /// Unit vector, or `.zero` when the vector is (almost) zero.
    public var normalized: Vec3 {
        let m = magnitude
        return m > 1e-9 ? Vec3(x / m, y / m, z / m) : .zero
    }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }

    public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    /// Angle in radians between two vectors (0 when either is zero-length).
    public func angle(to other: Vec3) -> Double {
        let a = normalized, b = other.normalized
        if a == .zero || b == .zero { return 0 }
        return acos(clamp(a.dot(b), -1, 1))
    }

    public static func + (l: Vec3, r: Vec3) -> Vec3 { Vec3(l.x + r.x, l.y + r.y, l.z + r.z) }
    public static func - (l: Vec3, r: Vec3) -> Vec3 { Vec3(l.x - r.x, l.y - r.y, l.z - r.z) }
    public static func * (l: Vec3, r: Double) -> Vec3 { Vec3(l.x * r, l.y * r, l.z * r) }
    public static func / (l: Vec3, r: Double) -> Vec3 { Vec3(l.x / r, l.y / r, l.z / r) }
    public static prefix func - (v: Vec3) -> Vec3 { Vec3(-v.x, -v.y, -v.z) }
}

/// Deterministic SplitMix64 generator. Used everywhere randomness is needed so
/// fights, AI and daily challenges are reproducible in tests.
public struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public static func random() -> SeededRNG {
        SeededRNG(seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in 0..<1.
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Uniform in lo...hi.
    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    /// True with probability `p`.
    public mutating func chance(_ p: Double) -> Bool {
        unit() < p
    }

    /// Approximately gaussian noise (sum of uniforms), mean 0, std ~= `sigma`.
    public mutating func gaussian(sigma: Double) -> Double {
        var s = 0.0
        for _ in 0..<6 { s += unit() }
        return (s - 3.0) * sigma * 1.4142
    }
}
