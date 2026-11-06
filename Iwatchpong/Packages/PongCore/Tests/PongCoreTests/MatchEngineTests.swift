import XCTest
@testable import PongCore

/// The table-tennis game, driven by simulated strokes and scripted balls.
final class MatchEngineTests: XCTestCase {
    private func engine(_ opponent: OpponentProfile = flawlessOpponent(), upgrades: PlayerUpgrades = PlayerUpgrades(),
                        seed: UInt64 = 3, config: MatchConfig = MatchConfig()) -> MatchEngine {
        MatchEngine(opponent: opponent, upgrades: upgrades, config: config, seed: seed)
    }

    private func swing(_ input: SimulatedInput, at time: Double = 0, seed: UInt64 = 1) -> PaddleEvent {
        var p = SimulatedPaddle(seed: seed, power: 0.6, jitter: 0)
        return p.event(for: input, at: time)
    }

    // MARK: Serving

    func testMatchStartsWithTheFirstServer() {
        let e = engine()
        e.start()
        XCTAssertEqual(e.phase, .serveReady(.human))
        XCTAssertTrue(e.drainEvents().contains(.serveReady(.human)))
        XCTAssertTrue(e.snapshot.ballVisible)
    }

    func testOpponentServesFirstWhenConfigured() {
        var c = MatchConfig()
        c.firstServer = .opponent
        let e = engine(config: c)
        e.start()
        XCTAssertEqual(e.phase, .serveReady(.opponent))
        let events = e.run(until: { if case .shot = $0 { return true } else { return false } }, limit: 6)
        let s = shots(events)
        XCTAssertEqual(s.first?.hitter, .opponent)
        XCTAssertEqual(s.first?.isServe, true)
    }

    func testTossThenSwingServes() {
        let e = engine(hopelessOpponent())
        e.start()
        e.handle(swing(.toss))
        XCTAssertEqual(e.phase, .tossing(.human))
        guard let hint = e.snapshot.hint else { return XCTFail("no timing hint for the toss") }
        e.run(untilClock: hint.idealTime)
        e.handle(swing(.forehandTopspin))
        let events = e.drainEvents()
        let s = shots(events)
        XCTAssertEqual(s.count, 1)
        XCTAssertTrue(s[0].isServe)
        XCTAssertEqual(s[0].hitter, .human)
        XCTAssertEqual(s[0].timing, .perfect)
        XCTAssertEqual(e.phase, .rally)
        XCTAssertGreaterThan(e.ball.velocity.x, 0, "toward the opponent")
    }

    func testSwingWithoutATossTossesForYou() {
        let e = engine()
        e.start()
        e.handle(swing(.forehandDrive))
        XCTAssertEqual(e.phase, .tossing(.human))
        XCTAssertTrue(e.drainEvents().contains(.whiff(.needToss)))
    }

    func testMissedTossIsRetriedOnceThenAFault() {
        let e = engine()
        e.start()
        e.handle(swing(.toss))
        var events = e.run(until: { if case .tossMissed = $0 { return true } else { return false } }, limit: 3)
        XCTAssertTrue(events.contains(.tossMissed(.human)))
        XCTAssertEqual(e.phase, .serveReady(.human), "one free re-toss")
        e.handle(swing(.toss))
        events = e.run(until: isPoint, limit: 3)
        let p = pointInfo(events)
        XCTAssertEqual(p?.winner, .opponent)
        XCTAssertEqual(p?.reason, .tossFault)
    }

    func testServeSwungTooEarlyOrTooLateIsAWhiff() {
        let e = engine()
        e.start()
        e.handle(swing(.toss))
        e.handle(swing(.forehandDrive))        // ball still rising
        XCTAssertTrue(e.drainEvents().contains(.whiff(.tooEarly)))
        XCTAssertEqual(e.phase, .tossing(.human))
    }

    func testEveryServeTypeIsLegalWhenWellTimed() {
        let inputs: [SimulatedInput] = [.forehandDrive, .forehandTopspin, .chop, .push, .flickLeft, .flickRight, .lob, .block, .drop]
        for input in inputs {
            let e = engine(hopelessOpponent(), seed: 11)
            e.start()
            e.handle(swing(.toss))
            e.run(untilClock: e.snapshot.hint!.idealTime)
            e.handle(swing(input))
            let events = e.run(until: { if case .point = $0 { return true } else { return false } }, limit: 6)
            let p = pointInfo(events)
            XCTAssertNotNil(p, "\(input) produced no point")
            XCTAssertNotEqual(p?.reason, .serveFault, "\(input) should be a legal serve, got \(String(describing: p))")
            // A legal serve against a hopeless opponent is an ace.
            XCTAssertEqual(p?.winner, .human, "\(input): \(String(describing: p))")
        }
    }

    // MARK: Rules

    private func rally(hit ball: BallState, by hitter: Player, opponent: OpponentProfile = hopelessOpponent()) -> MatchEngine {
        let e = engine(opponent)
        e.start()
        e.debugLaunch(ball: ball, hitter: hitter)
        e.drainEvents()
        return e
    }

    func testBallBouncingOnTheHittersOwnHalfLosesThePoint() {
        // Human hits a ball that lands on their own half.
        let ball = BallState(position: Vec3(-1.0, 0.3, 0), velocity: Vec3(1.0, -1.0, 0))
        let e = rally(hit: ball, by: .human)
        let p = pointInfo(e.run(until: isPoint, limit: 4))
        XCTAssertEqual(p?.winner, .opponent)
        XCTAssertEqual(p?.reason, .ownSideBounce)
    }

    func testBallIntoTheNetLosesThePoint() {
        let ball = BallState(position: Vec3(-0.6, 0.13, 0), velocity: Vec3(5, 0, 0))
        let e = rally(hit: ball, by: .human)
        let events = e.run(until: isPoint, limit: 4)
        XCTAssertTrue(events.contains(.netTouch(.blocked)))
        XCTAssertEqual(pointInfo(events)?.winner, .opponent)
        XCTAssertEqual(pointInfo(events)?.reason, .net)
    }

    func testBallLandingBeyondTheTableIsOut() {
        // High and fast over the table: never touches the far half.
        let ball = BallState(position: Vec3(-1.6, 0.4, 0), velocity: Vec3(14, 3.5, 0))
        let e = rally(hit: ball, by: .human)
        let p = pointInfo(e.run(until: isPoint, limit: 5))
        XCTAssertEqual(p?.winner, .opponent)
        XCTAssertEqual(p?.reason, .out)
    }

    func testBallWideOfTheTableIsOut() {
        let ball = BallState(position: Vec3(-1.6, 0.3, 0.6), velocity: Vec3(6, 1.2, 4))
        let e = rally(hit: ball, by: .human)
        let p = pointInfo(e.run(until: isPoint, limit: 5))
        XCTAssertEqual(p?.winner, .opponent)
        XCTAssertEqual(p?.reason, .out)
    }

    func testOpponentMissingAGoodShotWinsThePointForTheHuman() {
        // A legal return that the (hopeless) opponent cannot reach.
        let sol = ShotSolver.solve(origin: Vec3(-1.6, 0.25, 0), facing: .towardFar, speed: 9, spin: SpinSpec(top: 100),
                                   target: (0.9, 0.2), arc: .low)
        let ball = BallState(position: Vec3(-1.6, 0.25, 0), velocity: sol.velocity, spin: SpinSpec(top: 100).vector)
        let e = rally(hit: ball, by: .human)
        let p = pointInfo(e.run(until: isPoint, limit: 6))
        XCTAssertEqual(p?.winner, .human)
        XCTAssertTrue([.winner, .ace, .doubleBounce].contains(p?.reason ?? .out), "got \(String(describing: p?.reason))")
    }

    func testUnreturnedBallIsAPointForTheOpponent() {
        let e = rally(hit: incomingBall(), by: .opponent)
        let p = pointInfo(e.run(until: isPoint, limit: 8))
        XCTAssertEqual(p?.winner, .opponent)
    }

    func testPointIsScoredOnlyOnce() {
        let e = rally(hit: incomingBall(), by: .opponent)
        let events = e.run(8)
        XCTAssertEqual(events.filter(isPoint).count, 1)
        XCTAssertEqual(e.score.opponentPoints, 1)
        XCTAssertEqual(e.score.humanPoints, 0)
    }

    // MARK: Returning the ball

    func testPerfectTimingIsLabelledPerfect() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        guard let hint = e.snapshot.hint else { return XCTFail("no hint") }
        e.run(untilClock: hint.idealTime)
        e.handle(swing(.forehandDrive))
        let s = shots(e.drainEvents())
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].timing, .perfect)
        XCTAssertGreaterThan(s[0].quality, 0.7)
        XCTAssertGreaterThan(e.ball.velocity.x, 0)
    }

    func testEarlyAndLateSwingsAreLabelled() {
        func label(offset: Double) -> TimingLabel? {
            let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
            let hint = e.snapshot.hint!
            e.run(untilClock: hint.idealTime + offset)
            e.handle(swing(.forehandDrive))
            return shots(e.drainEvents()).first?.timing
        }
        XCTAssertEqual(label(offset: -0.14), .early)
        XCTAssertEqual(label(offset: 0.15), .late)
        XCTAssertEqual(label(offset: 0.0), .perfect)
    }

    func testTimingQualityDropsAsYouGetFurtherFromTheBeat() {
        func quality(offset: Double) -> Double {
            let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime + offset)
            e.handle(swing(.forehandDrive))
            return shots(e.drainEvents()).first?.quality ?? 0
        }
        XCTAssertGreaterThan(quality(offset: 0), quality(offset: 0.08))
        XCTAssertGreaterThan(quality(offset: 0.08), quality(offset: 0.16))
    }

    func testSwingingBeforeTheBallBouncesIsAWhiff() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        e.handle(swing(.forehandDrive))
        XCTAssertTrue(e.drainEvents().contains(.whiff(.noBall)))
    }

    func testSwingingMuchTooLateIsAWhiff() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        e.run(untilClock: e.snapshot.hint!.idealTime + 0.6)
        e.handle(swing(.forehandDrive))
        XCTAssertTrue(e.drainEvents().contains(.whiff(.tooLate)))
    }

    func testYouCannotHitTheSameBallTwice() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        e.run(untilClock: e.snapshot.hint!.idealTime)
        e.handle(swing(.forehandDrive))
        e.drainEvents()
        e.handle(swing(.forehandDrive))
        XCTAssertTrue(e.drainEvents().contains(.whiff(.alreadyHit)))
    }

    func testBallOnYourSideCueFiresAtTheBounce() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        let events = e.run(until: { $0 == .ballOnYourSide }, limit: 2)
        XCTAssertTrue(events.contains(.ballOnYourSide))
    }

    // MARK: Latency compensation

    func testADelayedSwingIsRolledBackToTheMomentOfContact() {
        // Swing happened exactly on the beat, but reaches the game 0.2 s later.
        func timing(age: Double) -> (TimingLabel?, Double?) {
            let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
            let hint = e.snapshot.hint!
            e.run(untilClock: hint.idealTime + 0.2)
            e.handle(swing(.forehandDrive), age: age)
            let s = shots(e.drainEvents()).first
            return (s?.timing, s?.timingOffset)
        }
        let compensated = timing(age: 0.2)
        let naive = timing(age: 0)
        XCTAssertEqual(compensated.0, .perfect)
        XCTAssertEqual(compensated.1 ?? 9, 0, accuracy: 0.02)
        XCTAssertEqual(naive.0, .late)
    }

    func testRolledBackShotFliesOnFromTheCorrectPlace() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        e.run(untilClock: e.snapshot.hint!.idealTime + 0.2)
        e.handle(swing(.forehandDrive), age: 0.2)
        e.drainEvents()
        XCTAssertGreaterThan(e.ball.velocity.x, 3, "already on its way to the opponent")
        XCTAssertGreaterThan(e.ball.position.x, -2.6)
    }

    func testRollbackIsLimited() {
        let e = rally(hit: incomingBall(), by: .opponent, opponent: flawlessOpponent())
        e.run(untilClock: e.snapshot.hint!.idealTime + 0.2)
        e.handle(swing(.forehandDrive), age: 5)       // absurd age is clamped, never crashes
        XCTAssertNoThrow(e.run(1))
    }

    func testALateArrivingSwingSavesAPointThatWasAboutToBeLost() {
        let e = rally(hit: incomingBall(speed: 12), by: .opponent, opponent: flawlessOpponent())
        let hint = e.snapshot.hint!
        // The ball goes past; the point is pending for the grace period.
        e.run(untilClock: hint.idealTime + 0.2)
        e.handle(swing(.block), age: 0.2)
        let events = e.drainEvents()
        XCTAssertFalse(events.contains(where: isPoint))
        XCTAssertEqual(shots(events).first?.hitter, .human)
    }

    // MARK: Strokes

    func testEveryStrokeProducesAReturn() {
        for input in SimulatedInput.allCases where input != .toss {
            let e = rally(hit: incomingBall(speed: 7), by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime)
            e.handle(swing(input))
            let s = shots(e.drainEvents())
            XCTAssertEqual(s.count, 1, "\(input)")
            XCTAssertGreaterThan(e.ball.velocity.x, 0, "\(input) should send the ball back")
        }
    }

    func testStrokesHaveTheirSignatureSpinAndSpeed() {
        func shot(_ input: SimulatedInput) -> ShotReport {
            let e = rally(hit: incomingBall(speed: 8), by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime)
            e.handle(swing(input))
            return shots(e.drainEvents())[0]
        }
        XCTAssertGreaterThan(shot(.forehandTopspin).topspin, 0.3)
        XCTAssertLessThan(shot(.chop).topspin, -0.3)
        XCTAssertLessThan(shot(.push).topspin, -0.15)
        XCTAssertNotEqual(shot(.flickRight).sidespin, 0)
        XCTAssertGreaterThan(shot(.flickRight).sidespin, 0)
        XCTAssertLessThan(shot(.flickLeft).sidespin, 0)
        XCTAssertGreaterThan(shot(.smash).speedKmh, shot(.forehandDrive).speedKmh)
        XCTAssertGreaterThan(shot(.forehandDrive).speedKmh, shot(.push).speedKmh)
        XCTAssertLessThan(shot(.drop).speedKmh, shot(.forehandDrive).speedKmh)
    }

    func testBlockUsesTheIncomingPace() {
        func blockSpeed(incoming: Double) -> Double {
            let e = rally(hit: incomingBall(speed: incoming), by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime)
            e.handle(swing(.block))
            return shots(e.drainEvents())[0].speedKmh
        }
        XCTAssertGreaterThan(blockSpeed(incoming: 12), blockSpeed(incoming: 6))
    }

    func testLobGoesHigherThanADrive() {
        func apex(_ input: SimulatedInput) -> Double {
            let e = rally(hit: incomingBall(speed: 7), by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime)
            e.handle(swing(input))
            e.drainEvents()
            var maxY = 0.0
            for _ in 0..<240 { e.update(1.0 / 120); maxY = max(maxY, e.ball.position.y) }
            return maxY
        }
        XCTAssertGreaterThan(apex(.lob), apex(.forehandDrive) + 0.3)
    }

    func testWrongSideStrokeIsPenalised() {
        // The ball is on the forehand side (z > 0) for a right-hander.
        func quality(_ input: SimulatedInput) -> (Double, Bool) {
            let ball = incomingBall(speed: 8, landing: (-0.9, 0.5))
            let e = rally(hit: ball, by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime + 0.05)
            e.handle(swing(input))
            let s = shots(e.drainEvents())[0]
            return (s.quality, s.wrongSide)
        }
        let fh = quality(.forehandDrive)
        let bh = quality(.backhandDrive)
        XCTAssertFalse(fh.1)
        XCTAssertTrue(bh.1)
        XCTAssertGreaterThan(fh.0, bh.0)
    }

    func testLeftHandersHaveTheirForehandOnTheLeft() {
        let ball = incomingBall(speed: 8, landing: (-0.9, -0.5))
        let e = rally(hit: ball, by: .opponent, opponent: flawlessOpponent())
        e.rightHanded = false
        e.run(untilClock: e.snapshot.hint!.idealTime)
        e.handle(swing(.forehandDrive))
        XCTAssertFalse(shots(e.drainEvents())[0].wrongSide)
    }

    func testSwingEarlierAimsRightAndLaterAimsLeft() {
        func landingZ(offset: Double) -> Double {
            let e = rally(hit: incomingBall(speed: 8), by: .opponent, opponent: flawlessOpponent())
            e.run(untilClock: e.snapshot.hint!.idealTime + offset)
            e.handle(swing(.forehandDrive))
            return shots(e.drainEvents())[0].target?.z ?? 0
        }
        XCTAssertGreaterThan(landingZ(offset: -0.08), landingZ(offset: 0.08))
    }

    // MARK: Opponent returns

    func testAFlawlessOpponentReturnsGoodBalls() {
        let e = rally(hit: incomingBall(speed: 7), by: .opponent, opponent: flawlessOpponent())
        e.run(untilClock: e.snapshot.hint!.idealTime)
        e.handle(swing(.forehandDrive))
        let events = e.run(until: { if case .shot(let s) = $0 { return s.hitter == .opponent } else { return false } }, limit: 4)
        XCTAssertTrue(shots(events).contains { $0.hitter == .opponent })
    }

    // MARK: Phases

    func testPausedGameDoesNotAdvance() {
        let e = engine()
        e.start()
        e.isPaused = true
        let t = e.clock
        e.run(2)
        XCTAssertEqual(e.clock, t)
        e.handle(swing(.toss))
        XCTAssertEqual(e.phase, .serveReady(.human))
    }

    func testGameClockIsDeterministicForASeed() {
        func finalScore(seed: UInt64) -> [Int] {
            let (_, e) = playMatch(opponent: OpponentProfile.roster[1], bot: HumanBot(seed: 3), seed: seed, maxSeconds: 400)
            return [e.score.humanPoints, e.score.opponentPoints, e.score.humanGames, e.score.opponentGames]
        }
        XCTAssertEqual(finalScore(seed: 8), finalScore(seed: 8))
    }
}
