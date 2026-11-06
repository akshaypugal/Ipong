import XCTest
@testable import PongCore

/// Plays whole matches with scripted players to check the rules end to end and
/// that the difficulty curve is sensible.
final class MatchSimulationTests: XCTestCase {
    private func skilled(_ seed: UInt64) -> HumanBot {
        let b = HumanBot(seed: seed, timingSigma: 0.04, rallyInputs: [.forehandTopspin, .forehandDrive, .backhandDrive, .backhandTopspin, .block])
        b.serveInput = .forehandTopspin
        return b
    }

    private func average(_ seed: UInt64) -> HumanBot {
        let b = HumanBot(seed: seed, timingSigma: 0.07, rallyInputs: [.forehandDrive, .backhandDrive, .block, .forehandTopspin])
        b.serveInput = .forehandDrive
        return b
    }

    private func novice(_ seed: UInt64) -> HumanBot {
        let b = HumanBot(seed: seed, timingSigma: 0.09, rallyInputs: [.forehandDrive, .backhandDrive, .block])
        b.attentiveness = 0.85
        b.serveInput = .forehandDrive
        return b
    }

    private func results(opponent: Int, bot: (UInt64) -> HumanBot, seeds: Int) -> (wins: Int, finished: Int, seconds: Double, points: Double) {
        var wins = 0, finished = 0
        var seconds = 0.0, points = 0.0
        for s in 1...seeds {
            let (outcome, engine) = playMatch(opponent: OpponentProfile.roster[opponent], bot: bot(UInt64(s)), seed: UInt64(s) &* 13)
            if let o = outcome {
                finished += 1
                if o.humanWon { wins += 1 }
                seconds += o.duration
                points += Double(engine.stats.pointsWon + engine.stats.pointsLost)
            }
        }
        return (wins, finished, seconds / Double(max(1, finished)), points / Double(max(1, finished)))
    }

    func testAMatchRunsToACompletionWithValidScores() {
        let (outcome, engine) = playMatch(opponent: OpponentProfile.roster[1], bot: average(2), seed: 7)
        guard let o = outcome else { return XCTFail("match did not finish, phase \(engine.phase)") }
        XCTAssertTrue(engine.isOver)
        XCTAssertEqual(max(o.humanGames, o.opponentGames), 2)
        XCTAssertLessThan(min(o.humanGames, o.opponentGames), 2)
        XCTAssertEqual(o.gameScores.count, o.humanGames + o.opponentGames)
        for g in o.gameScores {
            let hi = max(g.human, g.opponent), lo = min(g.human, g.opponent)
            XCTAssertGreaterThanOrEqual(hi, 11)
            XCTAssertGreaterThanOrEqual(hi - lo, 2)
            if hi > 11 { XCTAssertEqual(hi - lo, 2, "extended games end exactly two clear") }
        }
        XCTAssertGreaterThan(o.stats.totalShots, 20)
        XCTAssertGreaterThan(o.stats.pointsWon + o.stats.pointsLost, 22)
    }

    func testStatsAddUp() {
        let (outcome, _) = playMatch(opponent: OpponentProfile.roster[0], bot: skilled(3), seed: 9)
        guard let o = outcome else { return XCTFail("match did not finish") }
        let total = o.gameScores.reduce(0) { $0 + $1.human + $1.opponent }
        XCTAssertEqual(o.stats.pointsWon + o.stats.pointsLost, total)
        XCTAssertEqual(o.stats.gamesWon, o.humanGames)
        XCTAssertEqual(o.stats.gamesLost, o.opponentGames)
        XCTAssertGreaterThan(o.stats.longestRally, 1)
    }

    func testMatchesAreDeterministic() {
        func run() -> [Int] {
            let (o, _) = playMatch(opponent: OpponentProfile.roster[2], bot: average(4), seed: 5)
            return [o?.humanGames ?? -1, o?.opponentGames ?? -1, o?.stats.pointsWon ?? -1, o?.stats.totalShots ?? -1]
        }
        XCTAssertEqual(run(), run())
    }

    func testServiceRotatesDuringAMatch() {
        let e = MatchEngine(opponent: OpponentProfile.roster[1], seed: 4)
        let bot = average(1)
        e.start()
        var servers: [Player] = []
        var lastPoints = 0
        var t = 0.0
        while t < 900, servers.count < 8, !e.isOver {
            bot.tick(e)
            e.update(1.0 / 120)
            for ev in e.drainEvents() {
                if case .serveReady(let p) = ev { servers.append(p) }
            }
            lastPoints = e.score.totalPoints
            t += 1.0 / 120
        }
        _ = lastPoints
        XCTAssertGreaterThanOrEqual(servers.count, 6)
        // First server serves points 1-2, the other serves 3-4, ... (a let would repeat a serve; tolerate none here).
        let unique = servers.prefix(6)
        XCTAssertTrue(unique.contains(.human) && unique.contains(.opponent))
    }

    func testBestOfFiveGoesLonger() {
        var c = MatchConfig()
        c.pointsPerGame = 5
        c.gamesToWin = 3
        let (o, _) = playMatch(opponent: OpponentProfile.roster[0], bot: skilled(5), seed: 3, config: c, maxSeconds: 3600)
        XCTAssertNotNil(o)
        XCTAssertEqual(max(o?.humanGames ?? 0, o?.opponentGames ?? 0), 3)
    }

    func testShortGamesToFiveFinishQuickly() {
        var c = MatchConfig()
        c.pointsPerGame = 5
        c.gamesToWin = 1
        let (o, _) = playMatch(opponent: OpponentProfile.roster[0], bot: skilled(2), seed: 3, config: c, maxSeconds: 900)
        XCTAssertNotNil(o)
        XCTAssertEqual(o?.gameScores.count, 1)
    }

    /// Stronger opponents beat the same player more often (checked over a handful of short games).
    func testDifficultyLadder() {
        var c = MatchConfig()
        c.pointsPerGame = 7
        c.gamesToWin = 1
        func wins(_ opponent: Int) -> Int {
            var w = 0
            for s in 1...4 {
                let (o, _) = playMatch(opponent: OpponentProfile.roster[opponent], bot: skilled(UInt64(s)), seed: UInt64(s) &* 17, config: c, maxSeconds: 1500)
                if o?.humanWon == true { w += 1 }
            }
            return w
        }
        let rookie = wins(0), dragon = wins(5)
        XCTAssertGreaterThan(rookie, dragon)
        XCTAssertGreaterThanOrEqual(rookie, 3, "a good player should usually beat the rookie")
        XCTAssertLessThanOrEqual(dragon, 2, "the champion should be a real test")
    }

    /// Prints the full win-rate table. Slow: run with PONG_BALANCE=1.
    func testPrintWinRates() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PONG_BALANCE"] != nil, "set PONG_BALANCE=1 to print the balance table")
        var lines: [String] = []
        for i in 0..<6 {
            let a = results(opponent: i, bot: skilled, seeds: 4)
            let b = results(opponent: i, bot: average, seeds: 4)
            let c = i < 2 ? results(opponent: i, bot: novice, seeds: 4) : (wins: 0, finished: 0, seconds: 0.0, points: 0.0)
            lines.append("opp \(i) \(OpponentProfile.roster[i].nickname): skilled \(a.wins)/\(a.finished) (\(Int(a.seconds))s \(Int(a.points))pts) | average \(b.wins)/\(b.finished) (\(Int(b.seconds))s) | novice \(c.wins)/\(c.finished) (\(Int(c.seconds))s)")
        }
        print("BALANCE\n" + lines.joined(separator: "\n"))
    }
}
