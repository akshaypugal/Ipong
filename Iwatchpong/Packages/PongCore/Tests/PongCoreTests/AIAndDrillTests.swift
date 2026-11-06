import XCTest
@testable import PongCore

final class OpponentBrainTests: XCTestCase {
    private func ball(height: Double = 0.18, speed: Double = 8, topspin: Double = 0) -> BallState {
        // Travelling toward the opponent's end (+x) with the given topspin.
        BallState(position: Vec3(1.5, height, 0), velocity: Vec3(speed, 0, 0), spin: SpinSpec(top: topspin).vector)
    }

    private func distribution(_ profile: OpponentProfile, ball b: BallState, apexX: Double = 1.6, samples: Int = 400,
                              reach: Double = 0) -> [StrokeKind: Double] {
        var rng = SeededRNG(seed: 99)
        var counts: [StrokeKind: Int] = [:]
        for _ in 0..<samples {
            let d = OpponentBrain.decide(profile: profile, ball: b, apexX: apexX, humanZ: 0, reachDeficit: reach, rng: &rng)
            counts[d.swing.stroke, default: 0] += 1
        }
        return counts.mapValues { Double($0) / Double(samples) }
    }

    func testChopperChops() {
        let d = distribution(OpponentProfile.roster[2], ball: ball())
        XCTAssertGreaterThan(d[.chop] ?? 0, 0.5)
    }

    func testChopperPushesShortBalls() {
        let d = distribution(OpponentProfile.roster[2], ball: ball(), apexX: 0.5)
        XCTAssertGreaterThan((d[.push] ?? 0) + (d[.drop] ?? 0), 0.8)
        XCTAssertEqual(d[.chop] ?? 0, 0, accuracy: 0.001)
    }

    func testHardHitterSmashesHighBalls() {
        let d = distribution(OpponentProfile.roster[3], ball: ball(height: 0.45, speed: 6))
        XCTAssertGreaterThan(d[.smash] ?? 0, 0.7)
    }

    func testHardHitterDrivesNormalBalls() {
        let d = distribution(OpponentProfile.roster[3], ball: ball())
        XCTAssertGreaterThan((d[.drive] ?? 0) + (d[.topspin] ?? 0), 0.7)
        XCTAssertEqual(d[.chop] ?? 0, 0, accuracy: 0.001)
    }

    func testLooperLoops() {
        let d = distribution(OpponentProfile.roster[4], ball: ball())
        XCTAssertGreaterThan(d[.topspin] ?? 0, 0.55)
    }

    func testLooperFlicksShortBalls() {
        let d = distribution(OpponentProfile.roster[4], ball: ball(), apexX: 0.5)
        XCTAssertGreaterThan(d[.flick] ?? 0, 0.35)
    }

    func testChampionUsesEverything() {
        var seen = Set<StrokeKind>()
        for (h, speed, x) in [(0.18, 8.0, 1.6), (0.45, 6.0, 1.6), (0.18, 8.0, 0.5), (0.18, 17.0, 1.6)] {
            for s in distribution(OpponentProfile.roster[5], ball: ball(height: h, speed: speed), apexX: x).keys { seen.insert(s) }
        }
        XCTAssertGreaterThanOrEqual(seen.count, 6)
        XCTAssertTrue(seen.contains(.smash))
        XCTAssertTrue(seen.contains(.flick))
    }

    func testHeavyBackspinMakesGoodPlayersLiftTheBall() {
        let champ = distribution(OpponentProfile.roster[5], ball: ball(topspin: -300), samples: 600)
        let rookie = distribution(OpponentProfile.roster[0], ball: ball(topspin: -300), samples: 600)
        XCTAssertGreaterThan(champ[.topspin] ?? 0, rookie[.topspin] ?? 0)
    }

    func testBetterPlayersMissLess() {
        var rng = SeededRNG(seed: 4)
        func missRate(_ p: OpponentProfile) -> Double {
            var m = 0
            for _ in 0..<500 {
                if OpponentBrain.decide(profile: p, ball: ball(speed: 12, topspin: 250), apexX: 1.6, humanZ: 0, reachDeficit: 0.1, rng: &rng).misses { m += 1 }
            }
            return Double(m) / 500
        }
        XCTAssertGreaterThan(missRate(OpponentProfile.roster[0]), missRate(OpponentProfile.roster[5]))
        XCTAssertGreaterThan(missRate(OpponentProfile.roster[0]), 0.2)
        XCTAssertLessThan(missRate(OpponentProfile.roster[5]), 0.1)
    }

    func testHarderBallsAreMissedMoreOften() {
        var rng = SeededRNG(seed: 6)
        func missRate(_ b: BallState) -> Double {
            var m = 0
            for _ in 0..<500 {
                if OpponentBrain.decide(profile: OpponentProfile.roster[1], ball: b, apexX: 1.6, humanZ: 0, reachDeficit: 0, rng: &rng).misses { m += 1 }
            }
            return Double(m) / 500
        }
        XCTAssertGreaterThan(missRate(ball(speed: 18, topspin: 400)), missRate(ball(speed: 6)))
    }

    func testStretchingMakesMistakesMoreLikely() {
        var rng = SeededRNG(seed: 8)
        func missRate(reach: Double) -> Double {
            var m = 0
            for _ in 0..<500 {
                if OpponentBrain.decide(profile: OpponentProfile.roster[2], ball: ball(), apexX: 1.6, humanZ: 0, reachDeficit: reach, rng: &rng).misses { m += 1 }
            }
            return Double(m) / 500
        }
        XCTAssertGreaterThan(missRate(reach: 0.5), missRate(reach: 0))
    }

    func testOpponentsAimAwayFromTheHuman() {
        var rng = SeededRNG(seed: 12)
        var away = 0
        for _ in 0..<300 {
            let d = OpponentBrain.decide(profile: OpponentProfile.roster[4], ball: ball(), apexX: 1.6, humanZ: 0.6, reachDeficit: 0, rng: &rng)
            if d.aim < 0 { away += 1 }       // human on the right (+z): aim left
        }
        XCTAssertGreaterThan(away, 180)
    }

    func testServeVarietyDependsOnSkill() {
        func kinds(_ p: OpponentProfile) -> Set<StrokeKind> {
            var rng = SeededRNG(seed: 3)
            var s = Set<StrokeKind>()
            for _ in 0..<300 { s.insert(OpponentBrain.serve(profile: p, humanZ: 0, rng: &rng).swing.stroke) }
            return s
        }
        XCTAssertGreaterThan(kinds(OpponentProfile.roster[5]).count, kinds(OpponentProfile.roster[0]).count - 1)
        XCTAssertTrue(kinds(OpponentProfile.roster[4]).contains(.flick))
        XCTAssertTrue(kinds(OpponentProfile.roster[2]).contains(.push))
    }

    func testRosterIsADifficultyLadderOfDistinctStyles() {
        let r = OpponentProfile.roster
        XCTAssertEqual(r.count, 6)
        XCTAssertEqual(r.map { $0.rank }, CareerRank.allCases)
        XCTAssertEqual(r.map { $0.style }, [.allRound, .allRound, .chopper, .hardHitter, .looper, .champion])
        for i in 1..<r.count { XCTAssertLessThan(r[i].reaction, r[i - 1].reaction + 0.001 + (i == 3 ? 0.1 : 0)) }
        XCTAssertEqual(r.max(by: { $0.defence < $1.defence })?.id, 2)
        XCTAssertEqual(r.max(by: { $0.power < $1.power })?.id, 3 )
        XCTAssertEqual(r.max(by: { $0.spin < $1.spin })?.id, 4)
        XCTAssertEqual(r.max(by: { $0.serveSkill < $1.serveSkill })?.id, 5)
    }

    func testTierScalingMakesRematchesHarder() {
        let base = OpponentProfile.roster[2]
        let hard = base.scaled(tier: 2)
        XCTAssertLessThan(hard.reaction, base.reaction)
        XCTAssertGreaterThan(hard.consistency, base.consistency)
        XCTAssertGreaterThan(hard.rewardScale, base.rewardScale)
        XCTAssertEqual(base.scaled(tier: 0).reaction, base.reaction)
    }

    func testDecisionsAreDeterministic() {
        func run() -> [StrokeKind] {
            var rng = SeededRNG(seed: 77)
            return (0..<50).map { _ in
                OpponentBrain.decide(profile: OpponentProfile.roster[1], ball: ball(), apexX: 1.6, humanZ: 0, reachDeficit: 0, rng: &rng).swing.stroke
            }
        }
        XCTAssertEqual(run(), run())
    }
}

final class DrillTests: XCTestCase {
    private func drillEngine(_ kind: DrillKind, balls: Int = 10, seed: UInt64 = 5) -> MatchEngine {
        var spec = DrillSpec.spec(for: kind)
        spec.totalBalls = balls
        return MatchEngine(opponent: OpponentProfile.roster[0], mode: .drill(spec), seed: seed)
    }

    private func swing(_ input: SimulatedInput) -> PaddleEvent {
        var p = SimulatedPaddle(seed: 1, power: 0.6, jitter: 0)
        return p.event(for: input, at: 0)
    }

    private func drillOutcomes(_ events: [MatchEvent]) -> [DrillOutcome] {
        events.compactMap { if case .drill(let o, _, _) = $0 { return o } else { return nil } }
    }

    private func answerNextBall(_ e: MatchEngine, with input: SimulatedInput) -> [MatchEvent] {
        var events = e.run(until: { if case .tossStarted = $0 { return true } else { return false } }, limit: 5)
        guard let hint = e.snapshot.hint else { return events }
        events += e.run(untilClock: hint.idealTime)
        e.handle(swing(input))
        events += e.drainEvents()
        events += e.run(until: { if case .drill = $0 { return true } else { return false } }, limit: 6)
        return events
    }

    func testEveryDrillHasASpecAndAFeedThatLandsOnTheHumansHalf() {
        for kind in DrillKind.allCases where kind != .serve {
            let spec = DrillSpec.spec(for: kind)
            XCTAssertFalse(spec.instruction.isEmpty)
            XCTAssertFalse(spec.requiredStrokes.isEmpty)
            for i in 0..<3 {
                let e = drillEngine(kind, seed: UInt64(10 + i))
                e.start()
                let events = e.run(until: { if case .bounce(.near, _, _) = $0 { return true } else { return false } }, limit: 4)
                var landed: Vec3?
                for ev in events { if case .bounce(.near, let p, _) = ev { landed = p } }
                XCTAssertNotNil(landed, "\(kind) feed #\(i) never landed on the near half")
                if let l = landed {
                    XCTAssertLessThan(l.x, 0)
                    XCTAssertLessThan(abs(l.z), Table.halfWidth)
                }
            }
        }
    }

    func testForehandDriveDrillCountsACorrectDrive() {
        let e = drillEngine(.forehandDrive)
        e.start()
        let events = answerNextBall(e, with: .forehandDrive)
        let outcomes = drillOutcomes(events)
        XCTAssertEqual(outcomes.count, 1)
        // A correct, well-timed drive on the forehand side should usually be a success.
        XCTAssertEqual(outcomes.first, .success, "got \(outcomes)")
        XCTAssertEqual(e.snapshot.drillSuccesses, 1)
        XCTAssertEqual(e.snapshot.drillAttempts, 1)
    }

    func testWrongStrokeDoesNotCount() {
        let e = drillEngine(.forehandDrive)
        e.start()
        let outcomes = drillOutcomes(answerNextBall(e, with: .chop))
        XCTAssertEqual(outcomes.count, 1)
        XCTAssertNotEqual(outcomes.first, .success)
    }

    func testNotSwingingIsAMiss() {
        let e = drillEngine(.block)
        e.start()
        let events = e.run(until: { if case .drill = $0 { return true } else { return false } }, limit: 8)
        XCTAssertEqual(drillOutcomes(events).first, .missed)
        XCTAssertEqual(e.snapshot.drillAttempts, 1)
        XCTAssertEqual(e.snapshot.drillSuccesses, 0)
    }

    func testDrillEndsAfterTheConfiguredNumberOfBalls() {
        let e = drillEngine(.drop, balls: 3)
        e.start()
        let events = e.run(until: { if case .drillComplete = $0 { return true } else { return false } }, limit: 40)
        XCTAssertTrue(events.contains { if case .drillComplete(_, let attempts) = $0 { return attempts == 3 } else { return false } })
        XCTAssertEqual(e.phase, .drillOver)
        XCTAssertTrue(e.isOver)
    }

    func testEachDrillAcceptsItsOwnStroke() {
        let answers: [(DrillKind, SimulatedInput)] = [
            (.forehandDrive, .forehandDrive), (.backhandDrive, .backhandDrive), (.topspinLoop, .forehandTopspin),
            (.backspinChop, .chop), (.push, .push), (.block, .block), (.smash, .smash), (.lob, .lob),
            (.drop, .drop), (.flick, .flickLeft)
        ]
        var successes = 0
        for (kind, input) in answers {
            let e = drillEngine(kind, balls: 4, seed: 21)
            e.start()
            var got = 0
            for _ in 0..<4 {
                let outcomes = drillOutcomes(answerNextBall(e, with: input))
                if outcomes.first == .success { got += 1 }
                _ = e.run(until: { if case .serveReady = $0 { return true } else { return false } }, limit: 4)
            }
            successes += got
            XCTAssertGreaterThanOrEqual(got, 1, "\(kind): the right stroke, well timed, should succeed at least once in 4 balls")
        }
        XCTAssertGreaterThan(successes, answers.count * 2)
    }

    func testServeDrillCountsLegalServes() {
        let e = drillEngine(.serve, balls: 4)
        e.start()
        XCTAssertEqual(e.phase, .serveReady(.human))
        var ok = 0
        for _ in 0..<4 {
            e.handle(swing(.toss))
            e.run(untilClock: e.snapshot.hint!.idealTime)
            e.handle(swing(.forehandTopspin))
            let events = e.run(until: { if case .drill = $0 { return true } else { return false } }, limit: 6)
            if drillOutcomes(events).first == .success { ok += 1 }
            _ = e.run(until: { if case .serveReady = $0 { return true } else { return false } }, limit: 4)
        }
        XCTAssertGreaterThanOrEqual(ok, 3)
    }

    func testStarsFollowTheThresholds() {
        let spec = DrillSpec.spec(for: .forehandDrive)
        XCTAssertEqual(spec.stars(for: 0), 0)
        XCTAssertEqual(spec.stars(for: spec.starThresholds[0]), 1)
        XCTAssertEqual(spec.stars(for: spec.starThresholds[1]), 2)
        XCTAssertEqual(spec.stars(for: 10), 3)
    }
}
