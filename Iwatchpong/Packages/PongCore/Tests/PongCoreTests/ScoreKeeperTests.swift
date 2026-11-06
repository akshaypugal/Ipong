import XCTest
@testable import PongCore

final class ScoreKeeperTests: XCTestCase {
    private func play(_ s: inout ScoreKeeper, _ winners: [Player]) {
        for w in winners { s.award(to: w) }
    }

    func testGameIsWonAtElevenWithAClearTwoPointLead() {
        var s = ScoreKeeper()
        play(&s, Array(repeating: .human, count: 10))
        XCTAssertEqual(s.humanGames, 0)
        let updates = s.award(to: .human)
        XCTAssertTrue(updates.contains(.gameWon(.human)))
        XCTAssertEqual(s.humanGames, 1)
        XCTAssertEqual(s.humanPoints, 11)
    }

    func testMustWinByTwoAtTenAll() {
        var s = ScoreKeeper()
        for _ in 0..<10 { s.award(to: .human); s.award(to: .opponent) }
        XCTAssertTrue(s.isDeuce)
        XCTAssertFalse(s.award(to: .human).contains(.gameWon(.human)), "11-10 is not enough")
        XCTAssertFalse(s.award(to: .opponent).contains(.gameWon(.opponent)), "11-11")
        s.award(to: .opponent)
        XCTAssertEqual(s.opponentGames, 0, "12-11")
        XCTAssertTrue(s.award(to: .opponent).contains(.gameWon(.opponent)), "13-11")
        XCTAssertEqual(s.opponentGames, 1)
    }

    func testEleven_Nine_IsAGameButElevenTen_IsNot() {
        var s = ScoreKeeper()
        play(&s, Array(repeating: .opponent, count: 9) + Array(repeating: .human, count: 9))
        play(&s, [.human, .human])
        XCTAssertEqual(s.humanGames, 1)
    }

    func testServiceChangesEveryTwoPoints() {
        var s = ScoreKeeper(firstServer: .human)
        XCTAssertEqual(s.server, .human)
        s.award(to: .human)
        XCTAssertEqual(s.server, .human)
        s.award(to: .opponent)
        XCTAssertEqual(s.server, .opponent)
        s.award(to: .opponent)
        XCTAssertEqual(s.server, .opponent)
        s.award(to: .human)
        XCTAssertEqual(s.server, .human)
    }

    func testServiceAlternatesEveryPointFromTenAll() {
        var s = ScoreKeeper(firstServer: .human)
        for _ in 0..<10 { s.award(to: .human); s.award(to: .opponent) }
        // 10-10: 20 points played; the block pattern gives the first server.
        XCTAssertEqual(s.server, .human)
        s.award(to: .human)
        XCTAssertEqual(s.server, .opponent)
        s.award(to: .opponent)
        XCTAssertEqual(s.server, .human)
        s.award(to: .human)
        XCTAssertEqual(s.server, .opponent)
    }

    func testFirstServerAlternatesEachGame() {
        var s = ScoreKeeper(firstServer: .human)
        play(&s, Array(repeating: .human, count: 11))
        s.startNextGame()
        XCTAssertEqual(s.server, .opponent)
        XCTAssertEqual(s.humanPoints, 0)
        XCTAssertEqual(s.gameNumber, 2)
        play(&s, Array(repeating: .human, count: 11))
        XCTAssertEqual(s.matchWinner, .human, "best of three")
        s.startNextGame()
        XCTAssertEqual(s.server, .human)
    }

    func testBestOfFiveNeedsThreeGames() {
        var s = ScoreKeeper(pointsPerGame: 11, gamesToWin: 3)
        for _ in 0..<2 {
            play(&s, Array(repeating: .human, count: 11))
            s.startNextGame()
        }
        XCTAssertNil(s.matchWinner)
        let updates = { () -> [ScoreKeeper.Update] in
            var u: [ScoreKeeper.Update] = []
            for _ in 0..<11 { u = s.award(to: .human) }
            return u
        }()
        XCTAssertTrue(updates.contains(.matchWon(.human)))
    }

    func testShortGamesToFive() {
        var s = ScoreKeeper(pointsPerGame: 5, gamesToWin: 1)
        play(&s, Array(repeating: .opponent, count: 5))
        XCTAssertEqual(s.matchWinner, .opponent)
    }

    func testFinishedGameScoresAreRecorded() {
        var s = ScoreKeeper()
        play(&s, Array(repeating: .opponent, count: 3) + Array(repeating: .human, count: 11))
        XCTAssertEqual(s.finishedGames, [ScoreKeeper.GameScore(human: 11, opponent: 3)])
    }

    func testGamePointFlag() {
        var s = ScoreKeeper()
        play(&s, Array(repeating: .human, count: 10))
        XCTAssertTrue(s.isGamePoint)
        var d = ScoreKeeper()
        for _ in 0..<10 { d.award(to: .human); d.award(to: .opponent) }
        XCTAssertFalse(d.isGamePoint, "10-10 is not a game point")
    }
}
