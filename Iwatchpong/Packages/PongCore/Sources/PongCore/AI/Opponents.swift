import Foundation

public enum PlayStyle: String, Codable, Sendable {
    case allRound
    case chopper
    case hardHitter
    case looper
    case blocker
    case champion

    public var title: String {
        switch self {
        case .allRound: return "ALL-ROUND"
        case .chopper: return "DEFENSIVE CHOPPER"
        case .hardHitter: return "HARD HITTER"
        case .looper: return "SPIN MASTER"
        case .blocker: return "BLOCKER"
        case .champion: return "CHAMPION"
        }
    }
}

public enum CareerRank: Int, CaseIterable, Sendable {
    case rookie, club, league, national, world, legend

    public var title: String {
        switch self {
        case .rookie: return "ROOKIE"
        case .club: return "CLUB"
        case .league: return "LEAGUE"
        case .national: return "NATIONAL"
        case .world: return "WORLD"
        case .legend: return "LEGEND"
        }
    }
}

/// An opponent is defined by *how they play*, not by hit points.
public struct OpponentProfile: Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var nickname: String
    public var style: PlayStyle
    public var tagline: String
    public var rank: CareerRank

    /// Seconds the opponent needs to react to a new shot.
    public var reaction: Double
    /// Probability of a clean execution against an easy ball (0...1).
    public var consistency: Double
    public var power: Double
    public var spin: Double
    /// Accuracy of aiming at corners / gaps.
    public var placement: Double
    /// Movement speed, m/s.
    public var speed: Double
    /// How often they go for a winner (smash / big loop) when given a chance.
    public var aggression: Double
    /// Chops, lobs and blocks when under pressure.
    public var defence: Double
    /// Serve variety and quality.
    public var serveSkill: Double
    public var rewardScale: Double

    public var skinHex: String
    public var hairHex: String
    public var shirtHex: String
    public var paddleHex: String

    public init(id: Int, name: String, nickname: String, style: PlayStyle, tagline: String, rank: CareerRank,
                reaction: Double, consistency: Double, power: Double, spin: Double, placement: Double,
                speed: Double, aggression: Double, defence: Double, serveSkill: Double, rewardScale: Double,
                skinHex: String, hairHex: String, shirtHex: String, paddleHex: String) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.style = style
        self.tagline = tagline
        self.rank = rank
        self.reaction = reaction
        self.consistency = consistency
        self.power = power
        self.spin = spin
        self.placement = placement
        self.speed = speed
        self.aggression = aggression
        self.defence = defence
        self.serveSkill = serveSkill
        self.rewardScale = rewardScale
        self.skinHex = skinHex
        self.hairHex = hairHex
        self.shirtHex = shirtHex
        self.paddleHex = paddleHex
    }

    /// A tougher rematch (Pro Tour): quicker, steadier, harder.
    public func scaled(tier: Int) -> OpponentProfile {
        guard tier > 0 else { return self }
        let t = Double(tier)
        var p = self
        p.reaction = max(0.12, reaction * pow(0.88, t))
        p.consistency = min(0.97, consistency + 0.05 * t)
        p.power = min(1, power + 0.06 * t)
        p.spin = min(1, spin + 0.05 * t)
        p.placement = min(1, placement + 0.06 * t)
        p.speed = speed + 0.25 * t
        p.rewardScale = rewardScale * (1 + 0.5 * t)
        return p
    }

    // MARK: Roster

    public static let roster: [OpponentProfile] = [
        OpponentProfile(
            id: 0, name: "Mia Chen", nickname: "Rookie", style: .allRound,
            tagline: "Slow rallies and plenty of mistakes. Learn the strokes.", rank: .rookie,
            reaction: 0.55, consistency: 0.55, power: 0.35, spin: 0.15, placement: 0.2,
            speed: 2.4, aggression: 0.10, defence: 0.30, serveSkill: 0.2, rewardScale: 1.0,
            skinHex: "F1C27D", hairHex: "2B1B12", shirtHex: "3D7DD8", paddleHex: "D7263D"),

        OpponentProfile(
            id: 1, name: "Tomás Ruiz", nickname: "Club Player", style: .allRound,
            tagline: "Solid drives, some topspin. Keep the ball in play.", rank: .club,
            reaction: 0.42, consistency: 0.68, power: 0.50, spin: 0.35, placement: 0.40,
            speed: 3.0, aggression: 0.30, defence: 0.40, serveSkill: 0.35, rewardScale: 1.2,
            skinHex: "C68642", hairHex: "151515", shirtHex: "E8A317", paddleHex: "1B1B1B"),

        OpponentProfile(
            id: 2, name: "Hana Sato", nickname: "The Wall", style: .chopper,
            tagline: "Backspin chops and lobs. Be patient, then attack.", rank: .league,
            reaction: 0.35, consistency: 0.78, power: 0.40, spin: 0.60, placement: 0.55,
            speed: 3.2, aggression: 0.15, defence: 0.90, serveSkill: 0.5, rewardScale: 1.4,
            skinHex: "F3D5B5", hairHex: "0B0B0B", shirtHex: "2F9E44", paddleHex: "1F6F31"),

        OpponentProfile(
            id: 3, name: "Viktor Petrov", nickname: "Hammer", style: .hardHitter,
            tagline: "Fast flat drives and smashes. Block, chop, or lob.", rank: .national,
            reaction: 0.32, consistency: 0.70, power: 0.85, spin: 0.40, placement: 0.60,
            speed: 3.4, aggression: 0.80, defence: 0.35, serveSkill: 0.6, rewardScale: 1.7,
            skinHex: "F1C27D", hairHex: "C9B037", shirtHex: "C92A2A", paddleHex: "8B1A1A"),

        OpponentProfile(
            id: 4, name: "Lin Wei", nickname: "Spin Master", style: .looper,
            tagline: "Heavy topspin loops and tricky sidespin serves.", rank: .world,
            reaction: 0.28, consistency: 0.80, power: 0.65, spin: 0.95, placement: 0.75,
            speed: 3.7, aggression: 0.50, defence: 0.50, serveSkill: 0.85, rewardScale: 2.0,
            skinHex: "E0AC69", hairHex: "0B0B0B", shirtHex: "6741D9", paddleHex: "111111"),

        OpponentProfile(
            id: 5, name: "Zhao Long", nickname: "The Dragon", style: .champion,
            tagline: "Everything, all the time. The final boss.", rank: .legend,
            reaction: 0.22, consistency: 0.90, power: 0.85, spin: 0.90, placement: 0.90,
            speed: 4.2, aggression: 0.60, defence: 0.70, serveSkill: 0.95, rewardScale: 2.6,
            skinHex: "E0AC69", hairHex: "0B0B0B", shirtHex: "F2C94C", paddleHex: "D7263D")
    ]
}
