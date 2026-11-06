import Foundation

/// Table-tennis scoring (ITTF rules): games to 11, win by 2, service changes
/// every 2 points (every point from 10-10), the first server alternates each game,
/// best of N games. Pure value type, independent of any physics.
public struct ScoreKeeper: Equatable, Sendable {
    public var pointsPerGame: Int
    public var gamesToWin: Int
    public private(set) var humanPoints = 0
    public private(set) var opponentPoints = 0
    public private(set) var humanGames = 0
    public private(set) var opponentGames = 0
    public private(set) var gameNumber = 1
    public private(set) var firstServerOfGame: Player
    public private(set) var finishedGames: [GameScore] = []

    public struct GameScore: Equatable, Sendable {
        public var human: Int
        public var opponent: Int
    }

    public enum Update: Equatable, Sendable {
        case point
        case gameWon(Player)
        case matchWon(Player)
    }

    public init(pointsPerGame: Int = 11, gamesToWin: Int = 2, firstServer: Player = .human) {
        self.pointsPerGame = pointsPerGame
        self.gamesToWin = gamesToWin
        firstServerOfGame = firstServer
    }

    public var totalPoints: Int { humanPoints + opponentPoints }

    /// 10-10 (or later): the service alternates every point.
    public var isDeuce: Bool { humanPoints >= pointsPerGame - 1 && opponentPoints >= pointsPerGame - 1 }

    /// Who serves the next point.
    public var server: Player {
        let t = totalPoints
        let deuceStart = 2 * (pointsPerGame - 1)
        let blockServer: Player = (t / 2) % 2 == 0 ? firstServerOfGame : firstServerOfGame.other
        if t < deuceStart { return blockServer }
        // From 10-10 every point alternates, continuing from the server at 10-10.
        let atDeuce: Player = (deuceStart / 2) % 2 == 0 ? firstServerOfGame : firstServerOfGame.other
        return (t - deuceStart) % 2 == 0 ? atDeuce : atDeuce.other
    }

    public func points(of p: Player) -> Int { p == .human ? humanPoints : opponentPoints }
    public func games(of p: Player) -> Int { p == .human ? humanGames : opponentGames }

    public var isGamePoint: Bool {
        let h = humanPoints, o = opponentPoints
        return (h >= pointsPerGame - 1 || o >= pointsPerGame - 1) && h != o
    }

    public var matchWinner: Player? {
        if humanGames >= gamesToWin { return .human }
        if opponentGames >= gamesToWin { return .opponent }
        return nil
    }

    /// Awards a point and reports what it caused.
    @discardableResult
    public mutating func award(to p: Player) -> [Update] {
        if p == .human { humanPoints += 1 } else { opponentPoints += 1 }
        var out: [Update] = [.point]
        let mine = points(of: p), theirs = points(of: p.other)
        if mine >= pointsPerGame, mine - theirs >= 2 {
            if p == .human { humanGames += 1 } else { opponentGames += 1 }
            finishedGames.append(GameScore(human: humanPoints, opponent: opponentPoints))
            out.append(.gameWon(p))
            if games(of: p) >= gamesToWin { out.append(.matchWon(p)) }
        }
        return out
    }

    /// Starts the next game (the first server alternates).
    public mutating func startNextGame() {
        humanPoints = 0
        opponentPoints = 0
        gameNumber += 1
        firstServerOfGame = firstServerOfGame.other
    }
}
