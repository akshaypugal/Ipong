import Foundation
import CoreMotion
import PongCore

/// Motion layer on the Watch: reads fused device motion from Core Motion,
/// converts it into `MotionSample`s (device frame + world frame) and runs the
/// swing recogniser. Everything downstream is pure Swift in PongCore.
///
///     CMDeviceMotion -> MotionSample -> SwingRecognizer -> [PaddleEvent]
///
/// All callbacks run on the motion queue to keep latency low; hop to the main
/// thread yourself before touching UI.
final class MotionEngine {
    let recognizer = SwingRecognizer()

    /// Called with recognised strokes (motion queue).
    var onEvents: (([PaddleEvent]) -> Void)?
    /// Called for every sample (motion queue): calibration and the debug stream use this.
    var onSample: ((MotionSample) -> Void)?
    /// Called for every accepted/rejected burst (motion queue).
    var onDecision: ((SwingDecision) -> Void)?

    /// When false, samples are delivered to `onSample` but not recognised (calibration).
    var recognitionEnabled = true

    /// Applies settings on the motion queue (the recogniser is not thread-safe).
    func apply(config: SwingConfig? = nil, calibration: SwingCalibration? = nil) {
        queue.addOperation { [weak self] in
            guard let self else { return }
            if let c = config { self.recognizer.config = c }
            if let c = calibration { self.recognizer.calibration = c }
        }
    }

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.wristpong.motion"
        q.qualityOfService = .userInteractive
        q.maxConcurrentOperationCount = 1
        return q
    }()

    private var mapper = WorldFrameMapper()
    private var bootOffset: TimeInterval = 0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    var isRunning: Bool { manager.isDeviceMotionActive }

    init() {
        recognizer.onDecision = { [weak self] d in self?.onDecision?(d) }
    }

    /// Starts sensors at `rate` Hz. Safe to call when already running.
    func start(rate: Double = 100) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        queue.addOperation { [weak self] in
            self?.recognizer.reset()
            self?.mapper.reset()
        }
        manager.deviceMotionUpdateInterval = 1.0 / rate
        // CMDeviceMotion.timestamp is seconds since boot; convert to wall-clock time.
        bootOffset = Date().timeIntervalSince1970 - ProcessInfo.processInfo.systemUptime
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion)
        }
    }

    func stop() {
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
    }

    /// Forget stroke state without stopping the sensors.
    func resetRecognizer() {
        queue.addOperation { [weak self] in self?.recognizer.reset() }
    }

    private func process(_ m: CMDeviceMotion) {
        let ua = Vec3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
        let g = Vec3(m.gravity.x, m.gravity.y, m.gravity.z)
        let r = Vec3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
        let rm = m.attitude.rotationMatrix
        let rotation = RotationMatrix(rm.m11, rm.m12, rm.m13,
                                      rm.m21, rm.m22, rm.m23,
                                      rm.m31, rm.m32, rm.m33)
        let world = mapper.toWorld(ua, rotation: rotation, gravityDevice: g)
        let sample = MotionSample(timestamp: bootOffset + m.timestamp,
                                  userAccel: ua, gravity: g, rotationRate: r, worldAccel: world)
        onSample?(sample)
        guard recognitionEnabled else { return }
        let events = recognizer.process(sample)
        if !events.isEmpty { onEvents?(events) }
    }
}
