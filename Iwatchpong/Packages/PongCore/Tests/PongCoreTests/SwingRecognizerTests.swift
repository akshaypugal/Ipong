import XCTest
@testable import PongCore

/// Every stroke, recognised from synthetic wrist motion, plus the edge cases.
final class SwingRecognizerTests: XCTestCase {
    private func play(_ build: (inout SwingSynth) -> [MotionSample],
                      calibration: SwingCalibration = .default,
                      config: SwingConfig = .default) -> [PaddleEvent] {
        var synth = SwingSynth()
        let r = SwingRecognizer(config: config, calibration: calibration)
        var samples = synth.rest(0.4)
        samples += build(&synth)
        samples += synth.rest(0.8)
        return recognize(samples, recognizer: r).map { $0.event }
    }

    private func single(_ events: [PaddleEvent], file: StaticString = #filePath, line: UInt = #line) -> SwingResult? {
        XCTAssertEqual(events.count, 1, "got \(events.map { $0.code })", file: file, line: line)
        return events.first?.swing
    }

    // MARK: Strokes

    func testForehandDrive() {
        guard let s = single(play { $0.stroke(peak: 4, vertical: 0.05, yaw: 8) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .drive)
        XCTAssertEqual(s.side, .forehand)
        XCTAssertGreaterThan(s.power, 0.3)
    }

    func testBackhandDrive() {
        guard let s = single(play { $0.stroke(peak: 4, vertical: 0.0, yaw: -8) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .drive)
        XCTAssertEqual(s.side, .backhand)
    }

    func testTopspinLoop() {
        guard let s = single(play { $0.stroke(peak: 4.5, vertical: 0.5, yaw: 6) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .topspin)
        XCTAssertGreaterThan(s.topspin, 0.4)
    }

    func testBackhandTopspin() {
        guard let s = single(play { $0.stroke(peak: 4.5, vertical: 0.45, yaw: -6) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .topspin)
        XCTAssertEqual(s.side, .backhand)
    }

    func testBackspinChop() {
        guard let s = single(play { $0.stroke(peak: 3, vertical: -0.55, yaw: 5) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .chop)
        XCTAssertLessThan(s.topspin, -0.4)
    }

    func testSoftPush() {
        guard let s = single(play { $0.stroke(peak: 1.6, duration: 0.2, vertical: -0.5, yaw: 1) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .push)
    }

    func testSmash() {
        guard let s = single(play { $0.stroke(peak: 8, vertical: 0.1, yaw: 9) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .smash)
        XCTAssertGreaterThan(s.power, 0.6)
    }

    func testDownwardSmash() {
        guard let s = single(play { $0.stroke(peak: 7, vertical: -0.4, yaw: 8) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .smash)
    }

    func testLob() {
        guard let s = single(play { $0.stroke(peak: 3, duration: 0.2, vertical: 0.75, yaw: 6) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .lob)
    }

    func testBlock() {
        guard let s = single(play { $0.stroke(peak: 1.9, duration: 0.1, vertical: 0.0, yaw: 1) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .block)
        XCTAssertEqual(s.side, .either)
    }

    func testDropShot() {
        guard let s = single(play { $0.stroke(peak: 1.4, duration: 0.24, vertical: 0.0, yaw: 0.5) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .drop)
    }

    func testSidespinFlick() {
        let gyro = Vec3(0, 14, 0)
        guard let s = single(play { $0.stroke(peak: 2.6, duration: 0.1, vertical: 0.0, yaw: 3, extraGyro: gyro) }) else { return XCTFail("no swing") }
        XCTAssertEqual(s.stroke, .flick)
        XCTAssertNotEqual(s.sidespin, 0)
    }

    func testServeToss() {
        let events = play { $0.stroke(peak: 2.0, duration: 0.18, vertical: 0.92, yaw: 0.5) }
        XCTAssertEqual(events.count, 1, "got \(events.map { $0.code })")
        guard case .toss? = events.first else { return XCTFail("expected a toss, got \(events.map { $0.code })") }
    }

    func testPowerGrowsWithSwingStrength() {
        let soft = single(play { $0.stroke(peak: 2.4, vertical: 0, yaw: 6) })
        let hard = single(play { $0.stroke(peak: 4.8, vertical: 0, yaw: 6) })
        XCTAssertGreaterThan(hard?.power ?? 0, soft?.power ?? 1)
    }

    // MARK: Backswing / follow-through handling

    func testBackswingAndFollowThroughAreNotStrokes() {
        let events = play { $0.stroke(peak: 6, vertical: 0.1, yaw: 7) }
        XCTAssertEqual(events.count, 1, "got \(events.map { $0.code })")
    }

    func testStrokeWithoutBackswingStillCounts() {
        let events = play { $0.stroke(peak: 4, vertical: 0, yaw: 6, backswing: false, followThrough: false) }
        XCTAssertEqual(events.count, 1)
    }

    func testSeparateStrokesAreAllDetected() {
        var synth = SwingSynth()
        let r = SwingRecognizer()
        var samples = synth.rest(0.4)
        samples += synth.stroke(peak: 4, yaw: 7)
        samples += synth.rest(1.0)
        samples += synth.stroke(peak: 4, yaw: -7)
        samples += synth.rest(1.0)
        samples += synth.stroke(peak: 4.5, vertical: 0.5, yaw: 6)
        samples += synth.rest(0.8)
        let events = recognize(samples, recognizer: r).map { $0.event }
        XCTAssertEqual(events.count, 3, "got \(events.map { $0.code })")
        XCTAssertEqual(events[0].swing?.side, .forehand)
        XCTAssertEqual(events[1].swing?.side, .backhand)
        XCTAssertEqual(events[2].swing?.stroke, .topspin)
    }

    func testContactTimestampIsTheSensorTimeNotTheEmissionTime() {
        var synth = SwingSynth()
        var samples = synth.rest(0.4)
        let strokeStart = synth.time
        samples += synth.stroke(peak: 4, duration: 0.14, yaw: 7, backswing: false, followThrough: false)
        samples += synth.rest(0.8)
        let out = recognize(samples)
        XCTAssertEqual(out.count, 1)
        let contact = out[0].event.timestamp
        // Contact is within the forward lobe (+ the configured offset); the event appears later.
        XCTAssertGreaterThan(contact, strokeStart)
        XCTAssertLessThan(contact, strokeStart + 0.3)
        XCTAssertGreaterThan(out[0].emittedAt - contact, 0.1, "events are delayed by the backswing check; the timestamp stays on the sensor timeline")
        XCTAssertLessThan(out[0].emittedAt - contact, 0.45)
    }

    // MARK: Edge cases

    func testIdleStillnessProducesNothing() {
        var synth = SwingSynth()
        XCTAssertTrue(recognize(synth.rest(5)).isEmpty)
    }

    func testRandomWristMovementProducesNothing() {
        var synth = SwingSynth()
        synth.noise = 0.3
        XCTAssertTrue(recognize(synth.rest(6)).isEmpty)
    }

    func testWeakMovementIsIgnored() {
        let events = play { $0.stroke(peak: 0.6, vertical: 0, yaw: 2) }
        XCTAssertTrue(events.isEmpty, "got \(events.map { $0.code })")
    }

    func testExtremelyFastMovementIsRejected() {
        let events = play { $0.stroke(peak: 40, vertical: 0, yaw: 8, backswing: false, followThrough: false) }
        XCTAssertTrue(events.isEmpty, "got \(events.map { $0.code })")
    }

    func testSingleSampleSpikeIsFilteredOut() {
        var synth = SwingSynth()
        var samples = synth.rest(0.3)
        samples.append(synth.sample(accel: Vec3(60, 0, 0)))
        samples += synth.rest(0.6)
        XCTAssertTrue(recognize(samples).isEmpty)
    }

    func testSwingsFasterThanTheCooldownAreLimited() {
        var synth = SwingSynth()
        var samples = synth.rest(0.4)
        for _ in 0..<6 {
            samples += synth.stroke(peak: 4, yaw: 7, backswing: false, followThrough: false)
            samples += synth.rest(0.08)
        }
        samples += synth.rest(0.8)
        let events = recognize(samples).map { $0.event }
        XCTAssertLessThan(events.count, 6)
        XCTAssertGreaterThanOrEqual(events.count, 1)
    }

    func testMirrorSwapsForehandAndBackhand() {
        var config = SwingConfig.default
        config.mirror = true
        guard let s = single(play({ $0.stroke(peak: 4, yaw: 8) }, config: config)) else { return XCTFail("no swing") }
        XCTAssertEqual(s.side, .backhand)
    }

    // MARK: Calibration

    func testCalibrationLearnsTheForehandRotationDirection() {
        var synth = SwingSynth()
        let neutral = synth.rest(2.0)
        let forehand = synth.rest(0.3) + synth.stroke(peak: 3.5, yaw: -8) + synth.rest(0.5)    // a left-hander: negative yaw
        let backhand = synth.rest(0.3) + synth.stroke(peak: 3.5, yaw: 8) + synth.rest(0.5)
        guard let cal = SwingCalibrator.build(neutral: neutral, forehand: forehand, backhand: backhand, now: 5) else {
            return XCTFail("calibration failed")
        }
        XCTAssertEqual(cal.forehandYawSign, -1)
        XCTAssertTrue(cal.isCalibrated)
        XCTAssertEqual(cal.drivePeak, 3.5, accuracy: 0.6)

        // With that calibration the same negative-yaw swing is a forehand.
        var synth2 = SwingSynth()
        var samples = synth2.rest(0.4)
        samples += synth2.stroke(peak: 4, yaw: -8)
        samples += synth2.rest(0.8)
        let events = recognize(samples, recognizer: SwingRecognizer(calibration: cal))
        XCTAssertEqual(events.first?.event.swing?.side, .forehand)
    }

    func testCalibrationNeedsAStillNeutral() {
        var synth = SwingSynth()
        XCTAssertNil(SwingCalibrator.build(neutral: synth.rest(0.05), forehand: [], backhand: [], now: 0))
    }

    func testCalibrationWithoutAClearSwingIsIncomplete() {
        var synth = SwingSynth()
        let cal = SwingCalibrator.build(neutral: synth.rest(2), forehand: synth.rest(1), backhand: synth.rest(1), now: 0)
        XCTAssertNotNil(cal)
        XCTAssertFalse(cal?.isCalibrated ?? true)
    }

    func testPowerIsRelativeToTheCalibratedDrive() {
        var strong = SwingCalibration.default
        strong.hasNeutral = true
        strong.hasStrokes = true
        strong.drivePeak = 7
        var weak = strong
        weak.drivePeak = 2.5
        let p1 = single(play({ $0.stroke(peak: 4, yaw: 7) }, calibration: strong))
        let p2 = single(play({ $0.stroke(peak: 4, yaw: 7) }, calibration: weak))
        XCTAssertGreaterThan(p2?.power ?? 0, p1?.power ?? 1)
    }

    // MARK: Classifier directly

    func testClassifierRejectsOutOfRangeBursts() {
        let base = SwingFeatures(peak: 3, speed: 3, duration: 0.15, verticalFraction: 0, yawIntegral: 1, peakYaw: 5, peakGyro: 5)
        XCTAssertEqual(SwingClassifier.classify(SwingFeatures(peak: 0.5, speed: 1, duration: 0.15, verticalFraction: 0, yawIntegral: 0, peakYaw: 0, peakGyro: 0),
                                                config: .default, calibration: .default), .rejected(.weak))
        var f = base; f.peak = 30
        XCTAssertEqual(SwingClassifier.classify(f, config: .default, calibration: .default), .rejected(.implausible))
        f = base; f.duration = 0.01
        XCTAssertEqual(SwingClassifier.classify(f, config: .default, calibration: .default), .rejected(.tooShort))
        f = base; f.duration = 2
        XCTAssertEqual(SwingClassifier.classify(f, config: .default, calibration: .default), .rejected(.tooLong))
    }

    func testEveryStrokeHasNamesAndInstructions() {
        for s in StrokeKind.allCases {
            XCTAssertFalse(s.displayName.isEmpty)
            XCTAssertFalse(s.howTo.isEmpty)
        }
        XCTAssertEqual(StrokeKind.allCases.count, 9)
    }
}
