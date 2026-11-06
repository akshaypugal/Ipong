import Foundation

public enum Player: String, Codable, Sendable {
    case human
    case opponent

    public var other: Player { self == .human ? .opponent : .human }

    /// The half of the table this player stands at.
    public var side: CourtSide { self == .human ? .near : .far }

    public var facing: Facing { self == .human ? .towardFar : .towardNear }
}

public enum PointReason: String, Codable, Sendable {
    /// The defender could not return a good ball.
    case winner
    /// A serve the receiver never touched.
    case ace
    case doubleBounce
    /// Hit the ball long or wide.
    case out
    /// Hit it into the net.
    case net
    /// Ball bounced on the hitter's own half.
    case ownSideBounce
    /// Illegal serve (bounced on the wrong half, ...).
    case serveFault
    /// Failed to hit the served ball after tossing it.
    case tossFault
    /// Swung and missed / too late to reach the ball.
    case missed

    public var title: String {
        switch self {
        case .winner: return "WINNER"
        case .ace: return "ACE"
        case .doubleBounce: return "DOUBLE BOUNCE"
        case .out: return "OUT"
        case .net: return "NET"
        case .ownSideBounce: return "OWN SIDE"
        case .serveFault: return "SERVE FAULT"
        case .tossFault: return "TOSS FAULT"
        case .missed: return "MISSED"
        }
    }
}

public enum TimingLabel: String, Codable, Sendable {
    case perfect, good, early, late

    public var title: String {
        switch self {
        case .perfect: return "PERFECT"
        case .good: return "GOOD"
        case .early: return "EARLY"
        case .late: return "LATE"
        }
    }
}

public enum WhiffReason: String, Codable, Sendable {
    /// Nothing to hit yet (the ball has not bounced on your side).
    case noBall
    case tooEarly
    case tooLate
    case alreadyHit
    /// Swung during the serve toss window without a toss.
    case needToss
    /// Wrong moment of the point (between points).
    case notInPlay
    /// The ball was too far from you to get a paddle on it.
    case outOfReach
}

public struct ShotReport: Equatable, Sendable {
    public var hitter: Player
    public var stroke: StrokeKind
    public var side: StrokeSide
    public var speedKmh: Double
    public var topspin: Double          // -1...+1 relative
    public var sidespin: Double
    /// Overall contact quality 0...1.
    public var quality: Double
    public var timing: TimingLabel
    /// Seconds relative to the ideal moment (negative = early).
    public var timingOffset: Double
    public var power: Double
    public var isServe: Bool
    public var wrongSide: Bool
    public var stretched: Bool
    /// Where the shot is aimed to land.
    public var target: Vec3?
}

public struct PointInfo: Equatable, Sendable {
    public var winner: Player
    public var reason: PointReason
    public var rallyLength: Int
    public var humanPoints: Int
    public var opponentPoints: Int
}

public enum DrillOutcome: String, Codable, Sendable {
    case success
    case wrongStroke
    case missed
    case netOrOut
}

public enum MatchEvent: Equatable, Sendable {
    case serveReady(Player)
    case tossStarted(Player)
    case tossMissed(Player)
    case shot(ShotReport)
    case whiff(WhiffReason)
    case bounce(side: CourtSide, position: Vec3, isServe: Bool)
    case netTouch(NetContact)
    /// The ball is about to come up on the human's half: swing on the beat.
    case ballOnYourSide
    case letServe
    case point(PointInfo)
    case serverChanged(Player)
    case gameWon(winner: Player, humanGames: Int, opponentGames: Int)
    case matchWon(winner: Player)
    case rallyMilestone(Int)
    case drill(DrillOutcome, successes: Int, attempts: Int)
    case drillComplete(successes: Int, attempts: Int)
}

public struct MatchConfig: Sendable {
    public var pointsPerGame = 11
    /// Games needed to win the match (2 = best of 3).
    public var gamesToWin = 2
    public var firstServer: Player = .human
    /// Pause after a point before the next serve.
    public var pointPause = 1.5
    public var gamePause = 3.0
    /// How long a missed human return waits for a late (latency-delayed) swing.
    public var missGrace = 0.5
    /// Latency compensation: the longest we roll the ball back for a delayed swing.
    public var maxRollback = 0.5
    /// How long the AI waits before serving.
    public var aiServeDelay = 0.9
    /// Free re-tosses before a missed toss is a fault.
    public var tossRetries = 1
    /// Seconds before the human starts moving toward a new ball (reaction time).
    public var humanReaction = 0.30

    public init() {}
}

/// Where the human stands and how the swing animation is playing.
public struct PlayerPose: Equatable, Sendable {
    public var x: Double
    public var z: Double
    public var swingStart: Double?
    public var swingStroke: StrokeKind?
    public var swingSide: StrokeSide
    public var swingDirection: Double       // -1 left ... +1 right (aim)

    public init(x: Double, z: Double = 0) {
        self.x = x
        self.z = z
        swingSide = .forehand
        swingDirection = 0
    }
}

/// When and where the next ideal strike happens (drives the on-screen timing ring).
public struct StrikeHint: Equatable, Sendable {
    public var idealTime: Double
    public var position: Vec3
}

public enum MatchPhase: Equatable, Sendable {
    case notStarted
    case serveReady(Player)
    case tossing(Player)
    case rally
    case pointOver(winner: Player)
    case gameOver(winner: Player)
    case matchOver(winner: Player)
    case drillOver
}

public struct MatchSnapshot: Equatable, Sendable {
    public var phase: MatchPhase
    public var time: Double
    public var ballVisible: Bool
    public var ball: BallState
    public var human: PlayerPose
    public var opponent: PlayerPose
    public var humanPoints: Int
    public var opponentPoints: Int
    public var humanGames: Int
    public var opponentGames: Int
    public var server: Player
    public var rally: Int
    public var hint: StrikeHint?
    public var gameNumber: Int
    public var drillSuccesses: Int
    public var drillAttempts: Int
}

public struct MatchStats: Codable, Equatable, Sendable {
    public var pointsWon = 0
    public var pointsLost = 0
    public var aces = 0
    public var winners = 0
    public var unforcedErrors = 0
    public var longestRally = 0
    public var totalShots = 0
    public var perfectHits = 0
    public var smashes = 0
    public var smashWinners = 0
    public var lobs = 0
    public var blocks = 0
    public var chops = 0
    public var topspins = 0
    public var flicks = 0
    public var drops = 0
    public var pushes = 0
    public var drives = 0
    public var forehands = 0
    public var backhands = 0
    public var serves = 0
    public var fastestShotKmh = 0.0
    public var gamesWon = 0
    public var gamesLost = 0
    public var strokeCounts: [String: Int] = [:]

    public init() {}

    public mutating func record(stroke: StrokeKind, side: StrokeSide) {
        totalShots += 1
        strokeCounts[stroke.rawValue, default: 0] += 1
        switch stroke {
        case .drive: drives += 1
        case .topspin: topspins += 1
        case .chop: chops += 1
        case .push: pushes += 1
        case .smash: smashes += 1
        case .lob: lobs += 1
        case .block: blocks += 1
        case .drop: drops += 1
        case .flick: flicks += 1
        }
        if side == .forehand { forehands += 1 }
        if side == .backhand { backhands += 1 }
    }

    public mutating func merge(_ o: MatchStats) {
        pointsWon += o.pointsWon
        pointsLost += o.pointsLost
        aces += o.aces
        winners += o.winners
        unforcedErrors += o.unforcedErrors
        longestRally = max(longestRally, o.longestRally)
        totalShots += o.totalShots
        perfectHits += o.perfectHits
        smashes += o.smashes
        smashWinners += o.smashWinners
        lobs += o.lobs
        blocks += o.blocks
        chops += o.chops
        topspins += o.topspins
        flicks += o.flicks
        drops += o.drops
        pushes += o.pushes
        drives += o.drives
        forehands += o.forehands
        backhands += o.backhands
        serves += o.serves
        fastestShotKmh = max(fastestShotKmh, o.fastestShotKmh)
        gamesWon += o.gamesWon
        gamesLost += o.gamesLost
        for (k, v) in o.strokeCounts { strokeCounts[k, default: 0] += v }
    }

    public func count(_ stroke: StrokeKind) -> Int { strokeCounts[stroke.rawValue] ?? 0 }
}

public struct MatchOutcome: Equatable, Sendable {
    public var winner: Player
    public var humanGames: Int
    public var opponentGames: Int
    public var gameScores: [(human: Int, opponent: Int)]
    public var stats: MatchStats
    public var duration: Double
    public var opponentID: Int

    public var humanWon: Bool { winner == .human }

    public static func == (l: MatchOutcome, r: MatchOutcome) -> Bool {
        l.winner == r.winner && l.humanGames == r.humanGames && l.opponentGames == r.opponentGames
            && l.stats == r.stats && l.duration == r.duration && l.opponentID == r.opponentID
            && l.gameScores.count == r.gameScores.count
            && zip(l.gameScores, r.gameScores).allSatisfy { $0.human == $1.human && $0.opponent == $1.opponent }
    }

    public init(winner: Player, humanGames: Int, opponentGames: Int, gameScores: [(human: Int, opponent: Int)],
                stats: MatchStats, duration: Double, opponentID: Int) {
        self.winner = winner
        self.humanGames = humanGames
        self.opponentGames = opponentGames
        self.gameScores = gameScores
        self.stats = stats
        self.duration = duration
        self.opponentID = opponentID
    }
}
