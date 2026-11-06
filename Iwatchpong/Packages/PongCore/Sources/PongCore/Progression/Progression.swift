import Foundation

/// Everything that is saved between launches.
public struct PongProfile: Codable, Equatable, Sendable {
    public var level: Int
    public var xp: Int
    public var totalXP: Int
    public var coins: Int
    public var upgrades: PlayerUpgrades
    /// Opponents beaten in career order (0...6).
    public var careerProgress: Int
    public var opponentWins: [Int]
    public var matchesPlayed: Int
    public var matchesWon: Int
    public var lifetime: MatchStats
    /// Best star rating per drill (keyed by `DrillKind.rawValue`).
    public var drillStars: [String: Int]
    public var drillBest: [String: Int]
    public var calibration: SwingCalibration
    public var settings: AppSettings
    public var daily: DailyChallengeState
    public var hasOnboarded: Bool

    public init() {
        level = 1
        xp = 0
        totalXP = 0
        coins = 0
        upgrades = PlayerUpgrades()
        careerProgress = 0
        opponentWins = Array(repeating: 0, count: OpponentProfile.roster.count)
        matchesPlayed = 0
        matchesWon = 0
        lifetime = MatchStats()
        drillStars = [:]
        drillBest = [:]
        calibration = .default
        settings = AppSettings()
        daily = DailyChallengeState()
        hasOnboarded = false
    }

    private enum CodingKeys: String, CodingKey {
        case level, xp, totalXP, coins, upgrades, careerProgress, opponentWins, matchesPlayed, matchesWon
        case lifetime, drillStars, drillBest, calibration, settings, daily, hasOnboarded
    }

    /// Tolerant decoding: unknown / missing / corrupt fields fall back to defaults.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = max(1, (try? c.decode(Int.self, forKey: .level)) ?? 1)
        xp = max(0, (try? c.decode(Int.self, forKey: .xp)) ?? 0)
        totalXP = max(0, (try? c.decode(Int.self, forKey: .totalXP)) ?? 0)
        coins = max(0, (try? c.decode(Int.self, forKey: .coins)) ?? 0)
        upgrades = (try? c.decode(PlayerUpgrades.self, forKey: .upgrades)) ?? PlayerUpgrades()
        careerProgress = min(max(0, (try? c.decode(Int.self, forKey: .careerProgress)) ?? 0), OpponentProfile.roster.count)
        var wins = (try? c.decode([Int].self, forKey: .opponentWins)) ?? []
        while wins.count < OpponentProfile.roster.count { wins.append(0) }
        opponentWins = wins
        matchesPlayed = (try? c.decode(Int.self, forKey: .matchesPlayed)) ?? 0
        matchesWon = (try? c.decode(Int.self, forKey: .matchesWon)) ?? 0
        lifetime = (try? c.decode(MatchStats.self, forKey: .lifetime)) ?? MatchStats()
        drillStars = (try? c.decode([String: Int].self, forKey: .drillStars)) ?? [:]
        drillBest = (try? c.decode([String: Int].self, forKey: .drillBest)) ?? [:]
        calibration = (try? c.decode(SwingCalibration.self, forKey: .calibration)) ?? .default
        settings = (try? c.decode(AppSettings.self, forKey: .settings)) ?? AppSettings()
        daily = (try? c.decode(DailyChallengeState.self, forKey: .daily)) ?? DailyChallengeState()
        hasOnboarded = (try? c.decode(Bool.self, forKey: .hasOnboarded)) ?? false
    }

    // MARK: Level

    public static func xpNeeded(forLevel level: Int) -> Int { 120 + 60 * (level - 1) }
    public var xpToNextLevel: Int { Self.xpNeeded(forLevel: level) }
    public var xpFraction: Double { clamp(Double(xp) / Double(xpToNextLevel)) }

    @discardableResult
    public mutating func addXP(_ amount: Int) -> Int {
        guard amount > 0 else { return 0 }
        totalXP += amount
        xp += amount
        var gained = 0
        while xp >= xpToNextLevel {
            xp -= xpToNextLevel
            level += 1
            gained += 1
        }
        return gained
    }

    // MARK: Career

    public var careerCleared: Bool { careerProgress >= OpponentProfile.roster.count }

    public var unlockedOpponentCount: Int {
        careerCleared ? OpponentProfile.roster.count : careerProgress + 1
    }

    public func isUnlocked(opponent id: Int) -> Bool { id < unlockedOpponentCount }

    /// Current rank: ROOKIE -> CLUB -> LEAGUE -> NATIONAL -> WORLD -> LEGEND.
    public var rank: CareerRank {
        let i = min(careerProgress, OpponentProfile.roster.count - 1)
        return OpponentProfile.roster[i].rank
    }

    /// Pro Tour tiers unlocked after the career is cleared.
    public var maxTier: Int { careerCleared ? 1 + min(opponentWins.min() ?? 0, 2) : 0 }

    public var totalDrillStars: Int { drillStars.values.reduce(0, +) }
}

public struct RewardLine: Equatable, Sendable {
    public var title: String
    public var xp: Int
    public var coins: Int
}

public struct RewardSummary: Equatable, Sendable {
    public var won: Bool
    public var xp: Int
    public var coins: Int
    public var lines: [RewardLine]
    public var levelsGained: Int
    public var newLevel: Int
    public var unlockedOpponent: Int?
    public var careerCompleted: Bool
    public var completedChallenges: [String]
    public var humanGames: Int
    public var opponentGames: Int
}

public enum Rewards {
    public static func lines(for outcome: MatchOutcome, opponent: OpponentProfile) -> [RewardLine] {
        let s = outcome.stats
        let won = outcome.humanWon
        let scale = opponent.rewardScale
        let baseXP = Double(120 + 45 * opponent.id)
        let baseCoins = Double(40 + 20 * opponent.id)
        let extra = won ? 1.0 : 0.5

        func line(_ title: String, xp: Double, coins: Double, factor: Double = 1) -> RewardLine {
            RewardLine(title: title, xp: Int((xp * factor).rounded()), coins: Int((coins * factor).rounded()))
        }

        var out: [RewardLine] = []
        if won {
            out.append(line("Victory", xp: baseXP, coins: baseCoins, factor: scale))
            if outcome.opponentGames == 0 {
                out.append(line("Clean sweep", xp: 40, coins: 20, factor: scale))
            }
        } else {
            out.append(line("Match played", xp: baseXP * 0.25, coins: baseCoins * 0.25, factor: scale))
        }
        if s.aces > 0 {
            out.append(line("Aces x\(s.aces)", xp: Double(s.aces) * 8, coins: Double(s.aces) * 4, factor: extra))
        }
        if s.smashWinners > 0 {
            out.append(line("Smash winners x\(s.smashWinners)", xp: Double(s.smashWinners) * 10, coins: Double(s.smashWinners) * 5, factor: extra))
        }
        if s.longestRally >= 10 {
            let over = Double(min(s.longestRally - 9, 12))
            out.append(line("Rally of \(s.longestRally)", xp: over * 5, coins: over * 2, factor: extra))
        }
        if s.perfectHits > 0 {
            let c = Double(min(s.perfectHits, 40))
            out.append(line("Perfect shots x\(s.perfectHits)", xp: c * 2, coins: c, factor: extra))
        }
        return out
    }

    /// Drill rewards: new best star rating pays out the difference.
    public static func drillReward(successes: Int, spec: DrillSpec, previousStars: Int) -> (xp: Int, coins: Int, stars: Int) {
        let stars = spec.stars(for: successes)
        let newStars = max(0, stars - previousStars)
        let participation = 10 + successes * 2
        return (participation + newStars * 40, 5 + successes + newStars * 25, stars)
    }
}

public enum ProgressionService {
    @discardableResult
    public static func apply(outcome: MatchOutcome,
                             opponent: OpponentProfile,
                             tier: Int = 0,
                             to profile: inout PongProfile,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> RewardSummary {
        profile.daily.refreshIfNeeded(now: now, calendar: calendar)

        let lines = Rewards.lines(for: outcome, opponent: opponent)
        let xp = lines.reduce(0) { $0 + $1.xp }
        let coins = lines.reduce(0) { $0 + $1.coins }

        profile.matchesPlayed += 1
        profile.lifetime.merge(outcome.stats)
        var unlocked: Int?
        var completedCareer = false

        if outcome.humanWon {
            profile.matchesWon += 1
            if opponent.id < profile.opponentWins.count { profile.opponentWins[opponent.id] += 1 }
            if tier == 0, opponent.id == profile.careerProgress {
                profile.careerProgress += 1
                if profile.careerProgress < OpponentProfile.roster.count {
                    unlocked = profile.careerProgress
                } else {
                    completedCareer = true
                }
            }
        }

        let completed = profile.daily.record(stats: outcome.stats, won: outcome.humanWon)
        let levels = profile.addXP(xp)
        profile.coins += coins

        return RewardSummary(won: outcome.humanWon, xp: xp, coins: coins, lines: lines, levelsGained: levels,
                             newLevel: profile.level, unlockedOpponent: unlocked, careerCompleted: completedCareer,
                             completedChallenges: completed, humanGames: outcome.humanGames,
                             opponentGames: outcome.opponentGames)
    }

    /// Applies a finished drill: stars, XP and coins.
    @discardableResult
    public static func applyDrill(kind: DrillKind, successes: Int, attempts: Int, to profile: inout PongProfile) -> (xp: Int, coins: Int, stars: Int, levelsGained: Int) {
        let spec = DrillSpec.spec(for: kind)
        let key = kind.rawValue
        let previous = profile.drillStars[key] ?? 0
        let reward = Rewards.drillReward(successes: successes, spec: spec, previousStars: previous)
        profile.drillStars[key] = max(previous, reward.stars)
        profile.drillBest[key] = max(profile.drillBest[key] ?? 0, successes)
        let levels = profile.addXP(reward.xp)
        profile.coins += reward.coins
        return (reward.xp, reward.coins, reward.stars, levels)
    }

    @discardableResult
    public static func purchase(_ stat: UpgradeStat, profile: inout PongProfile) -> Bool {
        guard let cost = profile.upgrades.cost(for: stat), profile.coins >= cost else { return false }
        profile.coins -= cost
        profile.upgrades.setLevel(stat, profile.upgrades.level(stat) + 1)
        return true
    }

    @discardableResult
    public static func claimChallenge(id: String, profile: inout PongProfile) -> (xp: Int, coins: Int, levelsGained: Int)? {
        guard let reward = profile.daily.claim(id: id) else { return nil }
        let levels = profile.addXP(reward.xp)
        profile.coins += reward.coins
        return (reward.xp, reward.coins, levels)
    }
}
