import Foundation

public enum ChallengeKind: String, Codable, CaseIterable, Sendable {
    case smashes, topspins, chops, flicks, lobs, blocks, drops, drives
    case aces, winners, perfectHits, longRally, pointsWon, wins, serves

    public func title(target: Int) -> String {
        switch self {
        case .smashes: return "Hit \(target) Smashes"
        case .topspins: return "Play \(target) Topspin Loops"
        case .chops: return "Play \(target) Backspin Chops"
        case .flicks: return "Land \(target) Sidespin Flicks"
        case .lobs: return "Play \(target) Lobs"
        case .blocks: return "Make \(target) Blocks"
        case .drops: return "Play \(target) Drop Shots"
        case .drives: return "Hit \(target) Drives"
        case .aces: return target == 1 ? "Serve an Ace" : "Serve \(target) Aces"
        case .winners: return "Hit \(target) Winners"
        case .perfectHits: return "Hit \(target) Perfect Shots"
        case .longRally: return "Win a \(target)-Shot Rally"
        case .pointsWon: return "Win \(target) Points"
        case .wins: return target == 1 ? "Win a Match" : "Win \(target) Matches"
        case .serves: return "Serve \(target) Times"
        }
    }

    public var icon: String {
        switch self {
        case .smashes: return "💥"
        case .topspins: return "🌀"
        case .chops: return "🔪"
        case .flicks: return "💫"
        case .lobs: return "🌈"
        case .blocks: return "🛡"
        case .drops: return "🪶"
        case .drives: return "🏓"
        case .aces: return "🎯"
        case .winners: return "⚡"
        case .perfectHits: return "✨"
        case .longRally: return "🔥"
        case .pointsWon: return "🏅"
        case .wins: return "🏆"
        case .serves: return "🥄"
        }
    }

    public var targets: [Int] {
        switch self {
        case .smashes: return [3, 5, 8]
        case .topspins: return [10, 15, 25]
        case .chops: return [8, 12, 20]
        case .flicks: return [3, 5, 8]
        case .lobs: return [3, 5, 8]
        case .blocks: return [8, 12, 20]
        case .drops: return [3, 5, 8]
        case .drives: return [15, 25, 40]
        case .aces: return [1, 2, 3]
        case .winners: return [4, 6, 10]
        case .perfectHits: return [10, 20, 30]
        case .longRally: return [10, 15, 20]
        case .pointsWon: return [10, 15, 25]
        case .wins: return [1, 2]
        case .serves: return [8, 12, 20]
        }
    }

    func contribution(from stats: MatchStats, won: Bool) -> Int {
        switch self {
        case .smashes: return stats.smashes
        case .topspins: return stats.topspins
        case .chops: return stats.chops
        case .flicks: return stats.flicks
        case .lobs: return stats.lobs
        case .blocks: return stats.blocks
        case .drops: return stats.drops
        case .drives: return stats.drives
        case .aces: return stats.aces
        case .winners: return stats.winners
        case .perfectHits: return stats.perfectHits
        case .longRally: return stats.longestRally
        case .pointsWon: return stats.pointsWon
        case .wins: return won ? 1 : 0
        case .serves: return stats.serves
        }
    }
}

public struct DailyChallenge: Codable, Identifiable, Equatable, Sendable {
    public static let rewardXP = 100
    public static let rewardCoins = 50

    public var id: String
    public var kind: ChallengeKind
    public var target: Int
    public var progress: Int
    public var claimed: Bool

    public init(id: String, kind: ChallengeKind, target: Int, progress: Int = 0, claimed: Bool = false) {
        self.id = id
        self.kind = kind
        self.target = target
        self.progress = progress
        self.claimed = claimed
    }

    public var isComplete: Bool { progress >= target }
    public var title: String { kind.title(target: target) }
    public var fraction: Double { target == 0 ? 1 : min(1, Double(progress) / Double(target)) }
}

/// Three challenges per day, chosen deterministically from the date (works offline).
public struct DailyChallengeState: Codable, Equatable, Sendable {
    public var dayKey: String
    public var challenges: [DailyChallenge]

    public init(dayKey: String = "", challenges: [DailyChallenge] = []) {
        self.dayKey = dayKey
        self.challenges = challenges
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func generate(for date: Date, calendar: Calendar = .current) -> DailyChallengeState {
        let key = dayKey(for: date, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let year: Int = c.year ?? 0
        let month: Int = c.month ?? 0
        let day: Int = c.day ?? 0
        let seedValue: Int = year * 10_000 + month * 100 + day
        var rng = SeededRNG(seed: UInt64(seedValue))

        // One classic always appears; the rest are random.
        let classic: [ChallengeKind] = [.smashes, .aces, .perfectHits]
        let first = classic[Int(rng.next() % UInt64(classic.count))]
        var pool = ChallengeKind.allCases.filter { $0 != first }
        for i in stride(from: pool.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            pool.swapAt(i, j)
        }
        let kinds = [first] + Array(pool.prefix(2))
        let challenges = kinds.map { kind -> DailyChallenge in
            let targets = kind.targets
            let target = targets[Int(rng.next() % UInt64(targets.count))]
            return DailyChallenge(id: "\(key)-\(kind.rawValue)", kind: kind, target: target)
        }
        return DailyChallengeState(dayKey: key, challenges: challenges)
    }

    @discardableResult
    public mutating func refreshIfNeeded(now: Date, calendar: Calendar = .current) -> Bool {
        let key = Self.dayKey(for: now, calendar: calendar)
        guard key != dayKey || challenges.isEmpty else { return false }
        self = Self.generate(for: now, calendar: calendar)
        return true
    }

    /// Adds a finished match to every challenge. Returns ids that just became complete.
    @discardableResult
    public mutating func record(stats: MatchStats, won: Bool) -> [String] {
        var completed: [String] = []
        for i in challenges.indices {
            let was = challenges[i].isComplete
            let add = challenges[i].kind.contribution(from: stats, won: won)
            if challenges[i].kind == .longRally {
                challenges[i].progress = max(challenges[i].progress, add)
            } else {
                challenges[i].progress += add
            }
            if !was, challenges[i].isComplete { completed.append(challenges[i].id) }
        }
        return completed
    }

    public mutating func claim(id: String) -> (xp: Int, coins: Int)? {
        guard let i = challenges.firstIndex(where: { $0.id == id }),
              challenges[i].isComplete, !challenges[i].claimed else { return nil }
        challenges[i].claimed = true
        return (DailyChallenge.rewardXP, DailyChallenge.rewardCoins)
    }

    public var claimableCount: Int {
        challenges.filter { $0.isComplete && !$0.claimed }.count
    }
}
