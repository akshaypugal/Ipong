import XCTest
@testable import PongCore

final class WireTests: XCTestCase {
    private func roundTrip(_ m: WireMessage, file: StaticString = #filePath, line: UInt = #line) {
        guard let back = WireMessage(dictionary: m.dictionary) else {
            return XCTFail("failed to decode \(m)", file: file, line: line)
        }
        XCTAssertEqual(back, m, file: file, line: line)
    }

    func testEveryStrokeSurvivesTheWire() {
        for stroke in StrokeKind.allCases {
            for side in StrokeSide.allCases {
                let s = SwingResult(stroke: stroke, side: side, power: 0.7, speed: 4.5, topspin: -0.4, sidespin: 0.3,
                                    confidence: 0.88, timestamp: 12.5, duration: 0.17)
                roundTrip(.paddle(.swing(s), seq: 3, sensorTime: 12.5, sentTime: 12.6))
            }
        }
    }

    func testTossSurvivesTheWire() {
        roundTrip(.paddle(.toss(SwingMeta(confidence: 0.8, timestamp: 9)), seq: 1, sensorTime: 9, sentTime: 9.1))
    }

    func testControlMessages() {
        roundTrip(.heartbeat(seq: 9, sentTime: 100, mode: .play))
        roundTrip(.ping(id: 3, sentTime: 55))
        roundTrip(.pong(id: 3, pingSentTime: 55, watchTime: 60))
        roundTrip(.decision(time: 5, label: "TOPSPIN", peak: 3.4, confidence: 0.9))
        roundTrip(.rawBatch(RawBatch(values: [1, 2, 3, 4, 5, 6, 7])))
        roundTrip(.state(MatchSummary(phase: .rally, humanPoints: 7, opponentPoints: 5, humanGames: 1, opponentGames: 0, humanServes: false, rally: 6, sentTime: 3)))
        roundTrip(.calibrationProgress(CalibrationProgress(step: .forehand, progress: 0.5, secondsLeft: 2, message: "Swing")))
        roundTrip(.calibrationResult(SwingCalibration(gyroBias: Vec3(0.01, 0, 0.02), noiseFloor: 0.03, forehandYawSign: -1, drivePeak: 3.3, hasNeutral: true, hasStrokes: true)))
        for cue in PongHaptic.allCases { roundTrip(.haptic(cue)) }
    }

    func testCommands() {
        roundTrip(.command(.setMode(.practice)))
        roundTrip(.command(.startCalibration))
        roundTrip(.command(.cancelCalibration))
        roundTrip(.command(.setDebugStream(true)))
        roundTrip(.command(.setLocalHaptics(false)))
        roundTrip(.command(.setCalibration(.default)))
        var cfg = SwingConfig.default
        cfg.smashMin = 6.1
        roundTrip(.command(.setConfig(cfg)))
    }

    func testMalformedMessagesAreIgnored() {
        XCTAssertNil(WireMessage(dictionary: [:]))
        XCTAssertNil(WireMessage(dictionary: ["k": "nonsense"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "p"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "p", "n": "DRIVE", "seq": 1, "st": 1.0, "tx": 1.0]))          // no stroke payload
        XCTAssertNil(WireMessage(dictionary: ["k": "p", "n": "X", "sk": "wat", "seq": 1, "st": 1.0, "tx": 1.0]))
        XCTAssertNil(WireMessage(dictionary: ["k": "cmd", "c": "mode", "m": "bogus"]))
        XCTAssertNil(WireMessage(dictionary: ["k": "state", "d": Data([1, 2, 3])]))
        XCTAssertNil(WireMessage(dictionary: ["k": "haptic", "h": "unknown"]))
    }

    func testIntegersAreAcceptedWhereDoublesAreExpected() {
        let d: [String: Any] = ["k": "p", "n": "DRIVE", "sk": "drive", "seq": 1, "st": 5, "tx": 6, "c": 1, "pw": 1, "sp": 1]
        guard case .paddle(let e, _, let sensor, _)? = WireMessage(dictionary: d) else { return XCTFail("did not decode") }
        XCTAssertEqual(sensor, 5)
        XCTAssertEqual(e.swing?.stroke, .drive)
    }

    func testSyncContextRoundTrip() {
        var cfg = SwingConfig.default
        cfg.lobVerticalFrac = 0.6
        let ctx = SyncContext(calibration: SwingCalibration(forehandYawSign: -1, drivePeak: 3, hasNeutral: true, hasStrokes: true),
                              config: cfg, localHaptics: false)
        XCTAssertEqual(SyncContext(dictionary: ctx.dictionary), ctx)
        XCTAssertNil(SyncContext(dictionary: [:]))
        XCTAssertEqual(SyncContext(dictionary: ["k": "ctx", "cal": Data([9])])?.calibration, .default)
    }

    func testRawBatchLastSample() {
        let s = MotionSample(timestamp: 7, userAccel: Vec3(1, 2, 3), gravity: Vec3(0, 0, -1), rotationRate: Vec3(4, 5, 6), worldAccel: .zero)
        let b = RawBatch(samples: [s, s])
        XCTAssertEqual(b.count, 2)
        XCTAssertEqual(b.last?.accel, Vec3(1, 2, 3))
        XCTAssertEqual(b.last?.gyro, Vec3(4, 5, 6))
    }

    // MARK: Haptic mapping

    private func report(timing: TimingLabel, quality: Double, stroke: StrokeKind = .drive, hitter: Player = .human) -> ShotReport {
        ShotReport(hitter: hitter, stroke: stroke, side: .forehand, speedKmh: 40, topspin: 0.2, sidespin: 0, quality: quality,
                   timing: timing, timingOffset: 0, power: 0.6, isServe: false, wrongSide: false, stretched: false, target: nil)
    }

    func testHapticCuesForKeyMoments() {
        XCTAssertEqual(MatchEvent.ballOnYourSide.hapticCue, .ballOnYourSide)
        XCTAssertEqual(MatchEvent.shot(report(timing: .perfect, quality: 0.95)).hapticCue, .perfectHit)
        XCTAssertEqual(MatchEvent.shot(report(timing: .good, quality: 0.8)).hapticCue, .goodHit)
        XCTAssertEqual(MatchEvent.shot(report(timing: .late, quality: 0.3)).hapticCue, .weakHit)
        XCTAssertEqual(MatchEvent.shot(report(timing: .good, quality: 0.8, stroke: .smash)).hapticCue, .smashHit)
        XCTAssertNil(MatchEvent.shot(report(timing: .perfect, quality: 0.9, hitter: .opponent)).hapticCue, "only your own shots buzz")
        XCTAssertEqual(MatchEvent.whiff(.tooLate).hapticCue, .whiff)
        XCTAssertNil(MatchEvent.whiff(.needToss).hapticCue)
        XCTAssertEqual(MatchEvent.netTouch(.clip).hapticCue, .netCord)
        XCTAssertEqual(MatchEvent.serveReady(.human).hapticCue, .serveReady)
        XCTAssertNil(MatchEvent.serveReady(.opponent).hapticCue)
        XCTAssertEqual(MatchEvent.point(PointInfo(winner: .human, reason: .winner, rallyLength: 4, humanPoints: 1, opponentPoints: 0)).hapticCue, .pointWon)
        XCTAssertEqual(MatchEvent.point(PointInfo(winner: .opponent, reason: .out, rallyLength: 4, humanPoints: 0, opponentPoints: 1)).hapticCue, .pointLost)
        XCTAssertEqual(MatchEvent.gameWon(winner: .human, humanGames: 1, opponentGames: 0).hapticCue, .gameWon)
        XCTAssertEqual(MatchEvent.matchWon(winner: .opponent).hapticCue, .matchLost)
    }

    func testWatchSummaryReflectsTheMatch() {
        let e = MatchEngine(opponent: OpponentProfile.roster[0], seed: 1)
        XCTAssertEqual(e.watchSummary.phase, .idle)
        e.start()
        XCTAssertEqual(e.watchSummary.phase, .serveReady)
        XCTAssertTrue(e.watchSummary.humanServes)
    }

    // MARK: Latency

    func testClockSyncEstimatesOffset() {
        var sync = ClockSync()
        sync.addSample(pingSent: 100.0, watchTime: 105.02, pongReceived: 100.04)
        XCTAssertEqual(sync.offset, 5.0, accuracy: 1e-6)
        XCTAssertEqual(sync.toPhoneTime(105.5), 100.5, accuracy: 1e-6)
    }

    func testClockSyncPrefersLowRoundTrip() {
        var sync = ClockSync()
        sync.addSample(pingSent: 0, watchTime: 5.4, pongReceived: 0.5)
        let rough = sync.offset
        sync.addSample(pingSent: 10, watchTime: 15.01, pongReceived: 10.02)
        XCTAssertEqual(sync.offset, 5.0, accuracy: 0.001)
        XCTAssertNotEqual(rough, sync.offset)
    }

    func testLatencyTrackerStats() {
        var t = LatencyTracker(capacity: 10)
        [10.0, 20, 30].forEach { t.record(milliseconds: $0) }
        let s = t.stats
        XCTAssertEqual(s.last, 30)
        XCTAssertEqual(s.average, 20, accuracy: 1e-9)
        XCTAssertEqual(s.minimum, 10)
        XCTAssertEqual(s.maximum, 30)
        t.record(milliseconds: -5)
        t.record(milliseconds: .nan)
        XCTAssertEqual(t.stats.minimum, 0)
    }

    // MARK: Connection

    func testConnectionLifecycle() {
        var m = ConnectionMonitor(heartbeatTimeout: 4)
        XCTAssertEqual(m.state(now: 0), .inactive)
        m.update(activated: true, reachable: false, now: 0)
        XCTAssertEqual(m.state(now: 0), .disconnected)
        m.update(reachable: true, now: 1)
        XCTAssertEqual(m.state(now: 1), .connected)
        XCTAssertEqual(m.state(now: 1).headline, "WATCH CONNECTED")
        XCTAssertEqual(m.state(now: 5.5), .disconnected, "no heartbeat for too long")
        m.heard(at: 6)
        XCTAssertEqual(m.state(now: 7), .connected)
        m.update(reachable: false, now: 8)
        XCTAssertEqual(m.state(now: 8), .disconnected)
        XCTAssertEqual(m.state(now: 8).headline, "WATCH DISCONNECTED")
        m.update(reachable: true, now: 20)
        XCTAssertEqual(m.state(now: 20), .connected, "a stale heartbeat from before the drop must not count")
        m.reset()
        XCTAssertEqual(m.state(now: 21), .inactive)
    }

    func testPairingAndInstallStates() {
        var m = ConnectionMonitor()
        m.update(supported: true, paired: false, appInstalled: false, activated: true, reachable: false, now: 0)
        XCTAssertEqual(m.state(now: 0), .notPaired)
        m.update(paired: true, now: 0)
        XCTAssertEqual(m.state(now: 0), .appNotInstalled)
        m.update(appInstalled: true, now: 0)
        XCTAssertEqual(m.state(now: 0), .disconnected)
        m.update(supported: false, now: 0)
        XCTAssertEqual(m.state(now: 0), .unsupported)
        for s in [LinkState.unsupported, .notPaired, .appNotInstalled, .inactive, .disconnected, .connected] {
            XCTAssertFalse(s.detail.isEmpty)
        }
    }

    func testPausedGameIgnoresInputUntilResumed() {
        let e = MatchEngine(opponent: OpponentProfile.roster[0], seed: 2)
        e.start()
        e.isPaused = true
        var pad = SimulatedPaddle(seed: 1)
        e.handle(pad.event(for: .toss, at: 0))
        XCTAssertEqual(e.phase, .serveReady(.human))
        e.isPaused = false
        e.handle(pad.event(for: .toss, at: 0))
        XCTAssertEqual(e.phase, .tossing(.human))
    }

    // MARK: Simulated paddle

    func testSimulatedPaddleProducesEveryInput() {
        var pad = SimulatedPaddle(seed: 3)
        let strokes: [SimulatedInput: StrokeKind] = [
            .forehandDrive: .drive, .backhandDrive: .drive, .forehandTopspin: .topspin, .backhandTopspin: .topspin,
            .chop: .chop, .push: .push, .smash: .smash, .lob: .lob, .block: .block, .drop: .drop,
            .flickLeft: .flick, .flickRight: .flick
        ]
        for input in SimulatedInput.allCases {
            let e = pad.event(for: input, at: 10)
            XCTAssertEqual(e.timestamp, 10)
            if input == .toss {
                XCTAssertEqual(e.code, "TOSS")
            } else {
                XCTAssertEqual(e.swing?.stroke, strokes[input], "\(input)")
                XCTAssertTrue((0...1).contains(e.swing?.power ?? 2))
            }
        }
        XCTAssertEqual(SimulatedInput.allCases.count, 13)
        // Every stroke kind has at least one button.
        XCTAssertEqual(Set(strokes.values), Set(StrokeKind.allCases))
        XCTAssertEqual(pad.event(for: .backhandDrive).swing?.side, .backhand)
        XCTAssertLessThan(pad.event(for: .flickLeft).swing?.sidespin ?? 0, 0)
    }
}
