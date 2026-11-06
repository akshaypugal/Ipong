import Foundation

public enum UpgradeStat: String, Codable, CaseIterable, Identifiable, Sendable {
    case power, control, spin, reflex

    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }

    public var icon: String {
        switch self {
        case .power: return "💥"
        case .control: return "🎯"
        case .spin: return "🌀"
        case .reflex: return "⚡"
        }
    }

    public var blurb: String {
        switch self {
        case .power: return "Faster drives, smashes and serves"
        case .control: return "Fewer errors, better placement"
        case .spin: return "More spin on loops, chops and serves"
        case .reflex: return "Bigger timing window, longer reach, quicker feet"
        }
    }
}

/// The four MVP upgrades. Deliberately simple.
public struct PlayerUpgrades: Codable, Equatable, Sendable {
    public static let maxLevel = 10

    public var power: Int
    public var control: Int
    public var spin: Int
    public var reflex: Int

    public init(power: Int = 0, control: Int = 0, spin: Int = 0, reflex: Int = 0) {
        self.power = power
        self.control = control
        self.spin = spin
        self.reflex = reflex
    }

    private enum CodingKeys: String, CodingKey { case power, control, spin, reflex }

    /// Tolerant decoding.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func level(_ key: CodingKeys) -> Int { min(max((try? c.decode(Int.self, forKey: key)) ?? 0, 0), Self.maxLevel) }
        power = level(.power)
        control = level(.control)
        spin = level(.spin)
        reflex = level(.reflex)
    }

    public func level(_ stat: UpgradeStat) -> Int {
        switch stat {
        case .power: return power
        case .control: return control
        case .spin: return spin
        case .reflex: return reflex
        }
    }

    public mutating func setLevel(_ stat: UpgradeStat, _ value: Int) {
        let v = min(max(value, 0), Self.maxLevel)
        switch stat {
        case .power: power = v
        case .control: control = v
        case .spin: spin = v
        case .reflex: reflex = v
        }
    }

    public static func cost(fromLevel current: Int) -> Int { 40 + 20 * current }

    public func cost(for stat: UpgradeStat) -> Int? {
        let l = level(stat)
        return l >= Self.maxLevel ? nil : Self.cost(fromLevel: l)
    }

    // MARK: Effects

    public var speedMultiplier: Double { 1 + 0.03 * Double(power) }
    public var spinMultiplier: Double { 1 + 0.06 * Double(spin) }
    /// Scales shot errors (lower = better).
    public var errorMultiplier: Double { 1 - 0.045 * Double(control) }
    /// Scales the timing window around the ideal moment.
    public var timingWindowMultiplier: Double { 1 + 0.05 * Double(reflex) }
    public var reachBonus: Double { 0.03 * Double(reflex) }
    public var moveSpeed: Double { 3.0 + 0.15 * Double(reflex) }
}
