import Foundation
import PongCore

/// Runs the guided calibration on the Watch, driven by incoming motion samples
/// (so it follows the sensor clock, no timers needed):
///
///   1. neutral   (3 s)  - paddle hand still: gyro bias, gravity direction, noise floor
///   2. forehand  (wait) - one forehand swing: which way the wrist rotates + drive strength
///   3. backhand  (wait) - one backhand swing: must rotate the opposite way
final class CalibrationRunner {
    private enum Phase {
        case idle
        case neutral(start: Double)
        case forehandWait(start: Double)
        case forehandCapture(trigger: Double)
        case backhandWait(start: Double)
        case backhandCapture(trigger: Double)
    }

    static let neutralDuration = 3.0
    static let swingTimeout = 20.0
    /// Acceleration (g) that starts a swing capture.
    static let swingTrigger = 1.2
    /// Ignore motion this long after a prompt (hand returning to rest, reading the prompt).
    static let settleTime = 0.6
    static let captureTime = 0.9

    /// Progress updates for the iPhone and the Watch UI (any queue).
    var onProgress: ((CalibrationProgress) -> Void)?
    /// Called once when the run ends: a calibration, or nil when it failed/cancelled.
    var onFinished: ((SwingCalibration?) -> Void)?

    /// `start`/`cancel` come from the main thread, `feed` from the motion queue.
    private let lock = NSLock()
    private var phase = Phase.idle
    private var neutral: [MotionSample] = []
    private var forehand: [MotionSample] = []
    private var backhand: [MotionSample] = []
    private var recent: [MotionSample] = []
    private var probe = SwingCalibration.default
    private var lastEmitted = -1

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    private var running: Bool {
        if case .idle = phase { return false }
        return true
    }

    func start(at time: Double) {
        lock.lock()
        defer { lock.unlock() }
        neutral.removeAll()
        forehand.removeAll()
        backhand.removeAll()
        recent.removeAll()
        probe = .default
        lastEmitted = -1
        phase = .neutral(start: time)
        emit(.neutral, 0, Int(Self.neutralDuration), "Hold your paddle hand still")
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard running else { return }
        phase = .idle
        onFinished?(nil)
    }

    func feed(_ s: MotionSample) {
        lock.lock()
        defer { lock.unlock() }
        let t = s.timestamp
        switch phase {
        case .idle:
            return

        case .neutral(var start):
            // Time the capture on the sensor clock (the start time came from the wall clock).
            if neutral.isEmpty { start = t; phase = .neutral(start: t) }
            neutral.append(s)
            let e = max(0, t - start)
            progress(.neutral, e, Self.neutralDuration, "Hold your paddle hand still")
            if e >= Self.neutralDuration { finishNeutral(at: t) }

        case .forehandWait(let start):
            keepRecent(s)
            if s.userAccel.magnitude >= Self.swingTrigger, t - start > Self.settleTime {
                forehand = recent
                phase = .forehandCapture(trigger: t)
            } else if t - start > Self.swingTimeout {
                fail("No swing detected. Swing a forehand drive a little harder.")
            }

        case .forehandCapture(let trigger):
            forehand.append(s)
            if t - trigger >= Self.captureTime { finishForehand(at: t) }

        case .backhandWait(let start):
            keepRecent(s)
            if s.userAccel.magnitude >= Self.swingTrigger, t - start > Self.settleTime {
                backhand = recent
                phase = .backhandCapture(trigger: t)
            } else if t - start > Self.swingTimeout {
                fail("No swing detected. Swing a backhand drive a little harder.")
            }

        case .backhandCapture(let trigger):
            backhand.append(s)
            if t - trigger >= Self.captureTime { finishBackhand(at: t) }
        }
    }

    // MARK: Phase endings

    private func finishNeutral(at t: Double) {
        guard neutral.count >= 50, isStill(neutral),
              let cal = SwingCalibrator.build(neutral: neutral, forehand: [], backhand: [], now: t) else {
            fail("You moved. Rest your arm and keep your wrist still, then try again.")
            return
        }
        probe = cal
        recent.removeAll()
        phase = .forehandWait(start: t)
        lastEmitted = -1
        emit(.forehand, 0, 0, "Swing one forehand drive, like hitting a ball.")
    }

    private func finishForehand(at t: Double) {
        guard let f = SwingCalibrator.strongestBurst(in: forehand, calibration: probe), f.peakYaw >= 1.0 else {
            retryForehand(at: t, "That swing was too soft or too flat. Try a firmer forehand with a wrist turn.")
            return
        }
        probe.forehandYawSign = f.yawIntegral >= 0 ? 1 : -1
        recent.removeAll()
        phase = .backhandWait(start: t)
        lastEmitted = -1
        emit(.backhand, 0, 0, "Now swing one backhand drive, back across your body.")
    }

    private func finishBackhand(at t: Double) {
        guard let b = SwingCalibrator.strongestBurst(in: backhand, calibration: probe), b.peakYaw >= 0.8 else {
            retryBackhand(at: t, "That swing was too soft. Try a firmer backhand.")
            return
        }
        let backSign: Double = b.yawIntegral >= 0 ? 1 : -1
        guard backSign != probe.forehandYawSign else {
            // The wrist rotated the same way both times: forehand and backhand were not distinct.
            retryForehand(at: t, "Both swings turned the same way. Start again: forehand first, then a backhand the other way.")
            return
        }
        guard let cal = SwingCalibrator.build(neutral: neutral, forehand: forehand, backhand: backhand,
                                              now: Date().timeIntervalSince1970),
              cal.hasStrokes else {
            retryForehand(at: t, "Could not read the swings. Try a firmer forehand.")
            return
        }
        phase = .idle
        emit(.done, 1, 0, "Calibrated")
        onFinished?(cal)
    }

    // MARK: Helpers

    private func retryForehand(at t: Double, _ message: String) {
        forehand.removeAll()
        backhand.removeAll()
        recent.removeAll()
        phase = .forehandWait(start: t)
        lastEmitted = -1
        emit(.forehand, 0, 0, message)
    }

    private func retryBackhand(at t: Double, _ message: String) {
        backhand.removeAll()
        recent.removeAll()
        phase = .backhandWait(start: t)
        lastEmitted = -1
        emit(.backhand, 0, 0, message)
    }

    private func keepRecent(_ s: MotionSample) {
        recent.append(s)
        if recent.count > 40 { recent.removeFirst(recent.count - 40) }
    }

    /// The paddle hand barely moved during the neutral capture.
    private func isStill(_ samples: [MotionSample]) -> Bool {
        let n = Double(samples.count)
        var sum = 0.0, sq = 0.0, gyro = Vec3.zero
        for s in samples {
            let m = s.userAccel.magnitude
            sum += m
            sq += m * m
            gyro = gyro + s.rotationRate
        }
        let mean = sum / n
        let std = max(0, sq / n - mean * mean).squareRoot()
        return mean < 0.25 && std < 0.15 && (gyro / n).magnitude < 0.15
    }

    private func progress(_ step: CalibrationStep, _ elapsed: Double, _ duration: Double, _ message: String) {
        let left = max(0, Int((duration - elapsed).rounded(.up)))
        guard left != lastEmitted else { return }
        lastEmitted = left
        emit(step, min(1, elapsed / duration), left, message)
    }

    private func emit(_ step: CalibrationStep, _ progress: Double, _ secondsLeft: Int, _ message: String) {
        onProgress?(CalibrationProgress(step: step, progress: progress, secondsLeft: secondsLeft, message: message))
    }

    private func fail(_ message: String) {
        phase = .idle
        emit(.failed, 0, 0, message)
        onFinished?(nil)
    }
}
