import Foundation

/// One accepted or rejected burst, for the Debug screen and the event log.
public struct SwingDecision: Equatable, Sendable {
    public var time: TimeInterval
    public var label: String
    public var accepted: Bool
    public var peak: Double
    public var confidence: Double

    public init(time: TimeInterval, label: String, accepted: Bool, peak: Double, confidence: Double) {
        self.time = time
        self.label = label
        self.accepted = accepted
        self.peak = peak
        self.confidence = confidence
    }
}

/// The motion pipeline for the paddle:
///
///     raw sample -> noise filtering -> gyro baseline -> motion vector
///               -> peak detection (burst) -> features -> classification
///               -> validation (cooldown, rate, retract) -> backswing suppression
///               -> PaddleEvent
///
/// Swings come with a *backswing* (a weak burst in the opposite direction, just
/// before the real stroke). Strong bursts are emitted immediately; weak ones
/// wait `confirmDelay` to see whether a stronger opposite burst follows, in
/// which case they are discarded as the backswing. Events carry the *sensor*
/// time of contact, so the game can compensate for that delay.
public final class SwingRecognizer {
    public var config: SwingConfig {
        didSet {
            accelEMA.alpha = config.smoothing
            gyroEMA.alpha = config.smoothing
            yawEMA.alpha = config.smoothing
        }
    }
    public var calibration: SwingCalibration

    /// Every finalized burst (before classification): used for calibration and tuning.
    public var onBurst: ((SwingFeatures) -> Void)?
    public var onDecision: ((SwingDecision) -> Void)?
    public private(set) var lastDecision: SwingDecision?
    /// Latest filtered acceleration magnitude (for live meters).
    public private(set) var liveMagnitude = 0.0

    private enum Phase { case idle, burst, refractory }

    private struct Burst {
        var startTime = 0.0
        var peak = 0.0
        var peakTime = 0.0
        var dirSum = Vec3.zero
        var speedIntegral = 0.0
        var peakGyro = 0.0
        var peakYaw = 0.0
        var yawIntegral = 0.0

        mutating func begin(at t: Double) {
            self = Burst()
            startTime = t
        }
    }

    private struct Held {
        var event: PaddleEvent
        var direction: Vec3
        var peak: Double
        var emitAt: Double
    }

    private var median = MedianFilter3()
    private var accelEMA: Vec3EMA
    private var gyroEMA: EMAFilter
    private var yawEMA: EMAFilter
    private var phase = Phase.idle
    private var burst = Burst()
    private var lockoutUntil = 0.0
    private var lastTimestamp: TimeInterval?
    private var held: Held?
    private var lastEmitted = -1000.0
    private var lastDirection = Vec3.zero
    private var recentSwingTimes: [Double] = []

    public init(config: SwingConfig = .default, calibration: SwingCalibration = .default) {
        self.config = config
        self.calibration = calibration
        accelEMA = Vec3EMA(alpha: config.smoothing)
        gyroEMA = EMAFilter(alpha: config.smoothing)
        yawEMA = EMAFilter(alpha: config.smoothing)
    }

    public func reset() {
        median.reset()
        accelEMA.reset()
        gyroEMA.reset()
        yawEMA.reset()
        phase = .idle
        burst = Burst()
        lockoutUntil = 0
        lastTimestamp = nil
        held = nil
        lastEmitted = -1000
        lastDirection = .zero
        recentSwingTimes.removeAll()
    }

    public func process(_ samples: [MotionSample]) -> [PaddleEvent] {
        var out: [PaddleEvent] = []
        for s in samples { out.append(contentsOf: process(s)) }
        return out
    }

    public func process(_ s: MotionSample) -> [PaddleEvent] {
        var events: [PaddleEvent] = []
        let now = s.timestamp
        if let last = lastTimestamp, now < last - 1.0 { reset() }
        let dt: Double
        if let last = lastTimestamp { dt = min(max(now - last, 0.001), 0.05) } else { dt = 0.01 }
        lastTimestamp = now

        // Noise filtering.
        let acc = accelEMA.apply(median.apply(s.worldAccel))
        let mag = acc.magnitude
        liveMagnitude = mag

        // Gyro baseline; yaw = rotation about the vertical axis.
        let gyro = s.rotationRate - calibration.gyroBias
        var up = (-s.gravity).normalized
        if up == .zero { up = Vec3(0, 0, 1) }
        let yaw = yawEMA.apply(gyro.dot(up))
        let gyroMag = gyroEMA.apply(gyro.magnitude)

        // A held weak burst that was not contradicted becomes a real event.
        if let h = held, now >= h.emitAt {
            held = nil
            emit(h.event, direction: h.direction, at: now, into: &events)
        }

        let startThreshold = max(config.startThreshold, calibration.noiseFloor * 6)
        switch phase {
        case .idle:
            if mag >= startThreshold, now >= lockoutUntil {
                burst.begin(at: now)
                accumulate(acc: acc, mag: mag, yaw: yaw, gyro: gyroMag, dt: dt, now: now)
                phase = .burst
                // Something is moving again: keep the held burst around until it resolves.
                if var h = held {
                    h.emitAt = max(h.emitAt, now + 0.25)
                    held = h
                }
            }
        case .burst:
            accumulate(acc: acc, mag: mag, yaw: yaw, gyro: gyroMag, dt: dt, now: now)
            if now - burst.startTime > config.maxDuration {
                record(SwingDecision(time: now, label: "REJECT tooLong", accepted: false, peak: burst.peak, confidence: 0))
                phase = .refractory
                lockoutUntil = now + 0.1
            } else if mag < burst.peak * config.peakDropRatio {
                finalizeBurst(now: now, into: &events)
                phase = .refractory
            }
        case .refractory:
            if now >= lockoutUntil {
                if mag < startThreshold {
                    phase = .idle
                } else if lastDirection != .zero, acc.normalized.dot(lastDirection) < -0.5 {
                    // Back-to-back opposite lobe (backswing then stroke) without a quiet gap.
                    burst.begin(at: now)
                    accumulate(acc: acc, mag: mag, yaw: yaw, gyro: gyroMag, dt: dt, now: now)
                    phase = .burst
                    if var h = held {
                        h.emitAt = max(h.emitAt, now + 0.25)
                        held = h
                    }
                }
            }
        }
        return events
    }

    // MARK: Burst handling

    private func accumulate(acc: Vec3, mag: Double, yaw: Double, gyro: Double, dt: Double, now: Double) {
        if mag > burst.peak {
            burst.peak = mag
            burst.peakTime = now
        }
        burst.dirSum = burst.dirSum + acc * mag
        burst.speedIntegral += mag * 9.80665 * dt
        burst.peakGyro = max(burst.peakGyro, gyro)
        burst.peakYaw = max(burst.peakYaw, abs(yaw))
        burst.yawIntegral += yaw * dt
    }

    private func finalizeBurst(now: Double, into events: inout [PaddleEvent]) {
        let dir = burst.dirSum.normalized
        lockoutUntil = now + 0.03
        let features = SwingFeatures(peak: burst.peak,
                                     speed: burst.speedIntegral * config.speedCompensation,
                                     duration: now - burst.startTime,
                                     verticalFraction: dir.z,
                                     yawIntegral: burst.yawIntegral,
                                     peakYaw: burst.peakYaw,
                                     peakGyro: burst.peakGyro,
                                     direction: dir,
                                     peakTime: burst.peakTime)
        onBurst?(features)
        lastDirection = dir

        let event: PaddleEvent
        switch SwingClassifier.classify(features, config: config, calibration: calibration) {
        case .rejected(let reason):
            record(SwingDecision(time: now, label: "REJECT \(reason.rawValue)", accepted: false, peak: burst.peak, confidence: 0))
            return
        case .toss(let confidence):
            event = .toss(SwingMeta(confidence: confidence, timestamp: burst.peakTime))
        case .swing(let result):
            event = .swing(result)
        }

        // A burst that follows a held one in the opposite direction is either the
        // real stroke after its backswing (it is clearly stronger) or the follow-through
        // of the held stroke (it is not).
        if let h = held, h.direction.dot(dir) < -0.2 {
            if burst.peak > h.peak * 1.3 {
                held = nil
                record(SwingDecision(time: now, label: "REJECT backswing", accepted: false, peak: h.peak, confidence: 0))
            } else {
                record(SwingDecision(time: now, label: "REJECT retract", accepted: false, peak: burst.peak, confidence: 0))
                return
            }
        }

        // Anti-cheat validation.
        if let reason = validate(direction: dir, now: now) {
            record(SwingDecision(time: now, label: "REJECT \(reason.rawValue)", accepted: false, peak: burst.peak, confidence: event.confidence))
            return
        }

        // A held burst in the same direction was a real stroke: release it first.
        if let h = held {
            held = nil
            emit(h.event, direction: h.direction, at: now, into: &events)
        }

        // Every stroke waits `confirmDelay` so that a stronger opposite burst (it was
        // only the backswing) can cancel it. Events carry sensor time, so the game
        // compensates for the wait.
        held = Held(event: event, direction: dir, peak: burst.peak, emitAt: now + config.confirmDelay)
    }

    private func validate(direction: Vec3, now: Double) -> SwingRejection? {
        if now - lastEmitted < config.cooldown { return .cooldown }
        recentSwingTimes.removeAll { now - $0 > 1.0 }
        if recentSwingTimes.count >= config.maxSwingsPerSecond { return .rateLimited }
        if now - lastEmitted < config.recovery, lastDirection != .zero, direction.dot(lastEmittedDirection) < config.retractDot {
            return .retract
        }
        return nil
    }

    private var lastEmittedDirection = Vec3.zero

    private func emit(_ event: PaddleEvent, direction: Vec3, at now: Double, into events: inout [PaddleEvent]) {
        // Cooldown applies between *emitted* events.
        if now - lastEmitted < config.cooldown * 0.5 { return }
        lastEmitted = now
        lastEmittedDirection = direction
        recentSwingTimes.append(now)
        events.append(event)
        record(SwingDecision(time: now, label: event.code, accepted: true, peak: burst.peak, confidence: event.confidence))
    }

    private func record(_ d: SwingDecision) {
        lastDecision = d
        onDecision?(d)
    }
}

// MARK: - Calibration helper

public enum SwingCalibrator {
    /// The strongest burst found in a batch of samples (used by the guided calibration).
    public static func strongestBurst(in samples: [MotionSample], config: SwingConfig = .default,
                                      calibration: SwingCalibration = .default) -> SwingFeatures? {
        var best: SwingFeatures?
        let r = SwingRecognizer(config: config, calibration: calibration)
        r.onBurst = { f in
            if best == nil || f.peak > best!.peak { best = f }
        }
        _ = r.process(samples)
        // Flush a burst that was still in progress at the end of the batch.
        if let last = samples.last {
            var tail: [MotionSample] = []
            for i in 1...8 {
                var s = last
                s.timestamp = last.timestamp + Double(i) * 0.01
                s.worldAccel = .zero
                s.userAccel = .zero
                tail.append(s)
            }
            _ = r.process(tail)
        }
        return best
    }

    /// Builds a swing calibration from the three guided captures.
    public static func build(neutral: [MotionSample], forehand: [MotionSample], backhand: [MotionSample],
                             now: TimeInterval) -> SwingCalibration? {
        guard neutral.count >= 10 else { return nil }
        var cal = SwingCalibration.default
        let n = Double(neutral.count)
        var gyroSum = Vec3.zero, gravSum = Vec3.zero
        var accMagSum = 0.0, accMagSq = 0.0
        for s in neutral {
            gyroSum = gyroSum + s.rotationRate
            gravSum = gravSum + s.gravity
            let m = s.userAccel.magnitude
            accMagSum += m
            accMagSq += m * m
        }
        cal.gyroBias = gyroSum / n
        cal.neutralGravity = (gravSum / n).normalized
        let mean = accMagSum / n
        cal.noiseFloor = max(0.005, max(0, accMagSq / n - mean * mean).squareRoot())
        cal.hasNeutral = true

        var probe = cal
        probe.hasNeutral = true
        if let fh = strongestBurst(in: forehand, calibration: probe), fh.peakYaw >= 1.0 {
            cal.forehandYawSign = fh.yawIntegral >= 0 ? 1 : -1
            cal.drivePeak = min(8, max(2, fh.peak))
            cal.hasStrokes = true
        }
        return cal
    }
}
