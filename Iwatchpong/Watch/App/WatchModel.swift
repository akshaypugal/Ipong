import Foundation
import Combine
import HealthKit
import PongCore

/// Watch-side coordinator: motion -> strokes -> iPhone, haptics, calibration,
/// connection state and the tiny UI state the Watch shows.
///
/// The Watch is not the game screen. It is the paddle: it collects motion,
/// recognises strokes, plays haptics and shows the score.
final class WatchModel: ObservableObject {
    static let shared = WatchModel()

    // MARK: UI state
    @Published private(set) var connected = false
    @Published private(set) var mode: MotionMode = .off
    @Published private(set) var summary = MatchSummary()
    @Published private(set) var lastGesture = "-"
    @Published private(set) var lastConfidence = 0.0
    @Published private(set) var gestureCount = 0
    @Published private(set) var liveMagnitude = 0.0
    @Published private(set) var calibration: CalibrationProgress?
    @Published private(set) var motionAvailable = true

    // MARK: Pieces
    private let link = WatchLink()
    private let motion = MotionEngine()
    private let workout = WorkoutSessionManager()
    private let runner = CalibrationRunner()

    private let lock = NSLock()
    private var seq = 0
    private var localHaptics = true
    private var debugStream = false
    private var currentMode = MotionMode.off      // mirrors `mode`, readable from the motion queue
    private var lastRawSend = 0.0
    private var lastMeterUpdate = 0.0
    private var heartbeat: Timer?
    private var heartbeatSeq = 0

    private let defaults = UserDefaults.standard
    private enum Key {
        static let calibration = "wristpong.calibration"
        static let config = "wristpong.config"
        static let localHaptics = "wristpong.localHaptics"
    }

    private init() {
        motionAvailable = motion.isAvailable
        loadSaved()
        wireCallbacks()
        link.activate()
        if let ctx = link.lastContext { apply(context: ctx) }
        startHeartbeat()
    }

    // MARK: Setup

    private func loadSaved() {
        var cal = SwingCalibration.default
        var cfg = SwingConfig.default
        if let d = defaults.data(forKey: Key.calibration), let v = try? JSONDecoder().decode(SwingCalibration.self, from: d) { cal = v }
        if let d = defaults.data(forKey: Key.config), let v = try? JSONDecoder().decode(SwingConfig.self, from: d) { cfg = v }
        if defaults.object(forKey: Key.localHaptics) != nil { localHaptics = defaults.bool(forKey: Key.localHaptics) }
        motion.apply(config: cfg, calibration: cal)
    }

    private func wireCallbacks() {
        link.onMessage = { [weak self] dict in
            guard let message = WireMessage(dictionary: dict) else { return }
            DispatchQueue.main.async { self?.handle(message) }
        }
        link.onContext = { [weak self] ctx in
            DispatchQueue.main.async { self?.apply(context: ctx) }
        }
        link.onStatusChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshConnection() }
        }

        motion.onEvents = { [weak self] events in self?.deliver(events) }
        motion.onSample = { [weak self] sample in self?.handle(sample: sample) }
        motion.onDecision = { [weak self] d in self?.report(decision: d) }

        runner.onProgress = { [weak self] p in
            guard let self else { return }
            self.link.send(.calibrationProgress(p))
            DispatchQueue.main.async { self.calibration = p }
        }
        runner.onFinished = { [weak self] cal in
            DispatchQueue.main.async { self?.calibrationFinished(cal) }
        }
    }

    private func startHeartbeat() {
        heartbeat?.invalidate()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.beat() }
        RunLoop.main.add(t, forMode: .common)
        heartbeat = t
    }

    private func beat() {
        refreshConnection()
        guard link.isReachable else { return }
        heartbeatSeq += 1
        link.send(.heartbeat(seq: heartbeatSeq, sentTime: Date().timeIntervalSince1970, mode: mode))
    }

    private func refreshConnection() {
        let now = link.isReachable
        if now != connected { connected = now }
    }

    /// App returned to the foreground.
    func becameActive() {
        link.activate()
        refreshConnection()
        if !motion.isRunning, let ctx = link.lastContext { apply(context: ctx) }
    }

    // MARK: Incoming from the iPhone

    private func handle(_ message: WireMessage) {
        switch message {
        case .command(let command):
            handle(command)

        case .state(let s):
            summary = s

        case .haptic(let cue):
            WatchHaptics.play(cue)

        case .ping(let id, let sent):
            link.send(.pong(id: id, pingSentTime: sent, watchTime: Date().timeIntervalSince1970))

        default:
            break
        }
    }

    private func handle(_ command: WatchCommand) {
        switch command {
        case .setMode(let m):
            setMode(m)
        case .startCalibration:
            startCalibration()
        case .cancelCalibration:
            runner.cancel()
        case .setDebugStream(let on):
            lock.lock(); debugStream = on; lock.unlock()
        case .setConfig(let cfg):
            persist(config: cfg)
            motion.apply(config: cfg)
        case .setCalibration(let cal):
            persist(calibration: cal)
            motion.apply(calibration: cal)
        case .setLocalHaptics(let on):
            lock.lock(); localHaptics = on; lock.unlock()
            defaults.set(on, forKey: Key.localHaptics)
        }
    }

    private func apply(context: SyncContext) {
        persist(calibration: context.calibration)
        persist(config: context.config)
        lock.lock(); localHaptics = context.localHaptics; lock.unlock()
        motion.apply(config: context.config, calibration: context.calibration)
    }

    private func persist(calibration: SwingCalibration) {
        if let d = try? JSONEncoder().encode(calibration) { defaults.set(d, forKey: Key.calibration) }
    }

    private func persist(config: SwingConfig) {
        if let d = try? JSONEncoder().encode(config) { defaults.set(d, forKey: Key.config) }
    }

    // MARK: Modes

    /// `.play` streams strokes to the iPhone, `.practice` shows them here only.
    func setMode(_ newMode: MotionMode) {
        // The iPhone repeats its wanted mode whenever settings change; don't restart sensors for that.
        if newMode == mode, newMode == .off || motion.isRunning { return }
        mode = newMode
        lock.lock(); currentMode = newMode; seq = 0; lock.unlock()
        switch newMode {
        case .off:
            summary = MatchSummary()
            if !runner.isRunning {
                motion.stop()
                workout.stop()
            }
        case .play, .practice:
            motion.recognitionEnabled = !runner.isRunning
            motion.resetRecognizer()
            motion.start()
            workout.start()
            gestureCount = 0
        }
    }

    func workoutRequestedByPhone(_ configuration: HKWorkoutConfiguration) {
        workout.start(configuration: configuration)
    }

    // MARK: Calibration

    private func startCalibration() {
        guard motion.isAvailable else {
            link.send(.calibrationProgress(CalibrationProgress(step: .failed, message: "Motion sensors are not available on this Watch.")))
            return
        }
        motion.recognitionEnabled = false
        motion.start()
        workout.start()
        runner.start(at: Date().timeIntervalSince1970)
    }

    private func calibrationFinished(_ cal: SwingCalibration?) {
        motion.recognitionEnabled = true
        motion.resetRecognizer()
        // A cancelled run emits no final progress: drop the stale calibration screen.
        if cal == nil, let c = calibration, c.step != .failed { calibration = nil }
        if let cal {
            persist(calibration: cal)
            motion.apply(calibration: cal)
            link.send(.calibrationResult(cal))
        }
        if currentMode == .off {
            motion.stop()
            workout.stop()
        }
        // Keep the final progress (done / failed) visible for a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if let c = self?.calibration, c.step == .done || c.step == .failed { self?.calibration = nil }
        }
    }

    // MARK: Motion callbacks (motion queue)

    private func handle(sample: MotionSample) {
        if runner.isRunning { runner.feed(sample) }

        lock.lock()
        let streaming = debugStream
        let m = currentMode
        lock.unlock()

        let now = sample.timestamp
        if streaming, m != .off, now - lastRawSend >= 0.1 {
            lastRawSend = now
            link.send(.rawBatch(RawBatch(samples: [sample])))
        }
        if m == .practice, now - lastMeterUpdate >= 0.1 {
            lastMeterUpdate = now
            let mag = sample.worldAccel.magnitude
            DispatchQueue.main.async { [weak self] in self?.liveMagnitude = mag }
        }
    }

    private func deliver(_ events: [PaddleEvent]) {
        lock.lock()
        let m = currentMode
        let haptics = localHaptics
        lock.unlock()
        let sentTime = Date().timeIntervalSince1970

        for event in events {
            if m == .play {
                lock.lock()
                seq += 1
                let s = seq
                lock.unlock()
                link.send(.paddle(event, seq: s, sensorTime: event.timestamp, sentTime: sentTime))
            }
            if haptics, m != .off {
                DispatchQueue.main.async { WatchHaptics.tick() }
            }
            let code = event.code
            let conf = event.confidence
            DispatchQueue.main.async { [weak self] in
                self?.lastGesture = code
                self?.lastConfidence = conf
                self?.gestureCount += 1
            }
        }
    }

    private func report(decision: SwingDecision) {
        lock.lock()
        let streaming = debugStream
        lock.unlock()
        guard streaming else { return }
        link.send(.decision(time: decision.time, label: decision.label, peak: decision.peak, confidence: decision.confidence))
    }
}
