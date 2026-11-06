import Foundation
import Combine
import PongCore

/// The game's single source of input: your Apple Watch as a paddle (or, in
/// Developer Controller Mode, on-screen buttons that produce the very same events).
///
///     Watch motion -> swing recognition (on the Watch) -> WatchConnectivity
///                                                            |
///     Simulator buttons --------------------------------------+--> PaddleController --> onPaddle --> match engine
///
/// The game only ever sees `PaddleEvent`s plus an `age`: how long ago the contact
/// physically happened, so the engine can roll the ball back and compensate for
/// Watch detection and transport latency.
final class PaddleController: ObservableObject {
    struct LogEntry: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    // MARK: Published state
    @Published private(set) var linkState: LinkState = .inactive
    @Published private(set) var lastGesture = "-"
    @Published private(set) var lastConfidence = 0.0
    @Published private(set) var lastPower = 0.0
    @Published private(set) var latency = LatencyStats()
    @Published private(set) var eventLog: [LogEntry] = []
    @Published private(set) var rawAccel = Vec3.zero
    @Published private(set) var rawGyro = Vec3.zero
    @Published private(set) var lastDecision = "-"
    @Published private(set) var calibrationProgress: CalibrationProgress?
    @Published private(set) var watchMode: MotionMode = .off
    @Published private(set) var packetsLost = 0
    @Published private(set) var debugStreaming = false
    /// Developer Controller Mode: on-screen buttons replace the Watch.
    @Published var simulatorEnabled = false

    // MARK: Hooks
    /// The single consumer of paddle events (the active match / drill / onboarding test).
    var onPaddle: ((PaddleEvent, Double) -> Void)?
    var onLinkLost: (() -> Void)?
    var onCalibration: ((SwingCalibration) -> Void)?
    var syncProvider: (() -> SyncContext)?

    // MARK: Internals
    private let link = PhoneLink()
    private var monitor = ConnectionMonitor()
    private var clock = ClockSync()
    private var latencyTracker = LatencyTracker()
    private var sim = SimulatedPaddle(seed: UInt64.random(in: 1...UInt64.max))
    private var timer: Timer?
    private var tickCount = 0
    private var lastSeq = -1
    private var pingID = 0
    private var wantedMode: MotionMode = .off
    private var wantDebug = false

    init() {
        link.onMessage = { [weak self] dict in
            let received = Date().timeIntervalSince1970
            DispatchQueue.main.async { self?.handle(dict, receivedAt: received) }
        }
        link.onStatusChange = { [weak self] in
            DispatchQueue.main.async { self?.refreshLink() }
        }
    }

    // MARK: Lifecycle

    func start() {
        link.activate()
        refreshLink()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func appBecameActive() {
        link.activate()
        refreshLink()
        syncToWatch()
    }

    private func tick() {
        tickCount += 1
        refreshLink()
        if linkState.isConnected, !clock.isSynced || tickCount % 5 == 0 { sendPing() }
    }

    private func sendPing() {
        pingID += 1
        link.send(.ping(id: pingID, sentTime: Date().timeIntervalSince1970))
    }

    private func refreshLink() {
        let s = link.status
        let now = Date().timeIntervalSince1970
        monitor.update(supported: s.supported, paired: s.paired, appInstalled: s.installed,
                       activated: s.activated, reachable: s.reachable, now: now)
        let state = monitor.state(now: now)
        guard state != linkState else { return }
        let was = linkState
        linkState = state
        if was.isConnected, !state.isConnected {
            log("Watch disconnected")
            onLinkLost?()
        } else if !was.isConnected, state.isConnected {
            log("Watch connected")
            lastSeq = -1
            syncToWatch()
            sendPing()
        }
    }

    /// Pushes calibration, thresholds, mode and debug streaming to the Watch.
    func syncToWatch() {
        if let ctx = syncProvider?() {
            link.publishContext(ctx)
            guard linkState.isConnected else { return }
            link.send(.command(.setCalibration(ctx.calibration)))
            link.send(.command(.setConfig(ctx.config)))
            link.send(.command(.setLocalHaptics(ctx.localHaptics)))
        }
        guard linkState.isConnected else { return }
        if wantedMode != .off { link.send(.command(.setMode(wantedMode))) }
        link.send(.command(.setDebugStream(wantDebug)))
    }

    // MARK: Commands to the Watch

    var isWatchConnected: Bool { linkState.isConnected }

    /// True when paddle events can arrive (real Watch or simulated buttons).
    var hasController: Bool { linkState.isConnected || simulatorEnabled }

    func setMode(_ mode: MotionMode) {
        wantedMode = mode
        link.send(.command(.setMode(mode)))
        if mode != .off, !linkState.isConnected {
            let s = link.status
            if s.paired, s.installed { WatchLauncher.launch() }
        }
    }

    func setDebugStreaming(_ on: Bool) {
        wantDebug = on
        debugStreaming = on
        link.send(.command(.setDebugStream(on)))
    }

    func sendHaptic(_ cue: PongHaptic) {
        guard linkState.isConnected else { return }
        link.send(.haptic(cue))
    }

    func sendState(_ summary: MatchSummary) {
        guard linkState.isConnected else { return }
        var s = summary
        s.sentTime = Date().timeIntervalSince1970
        link.send(.state(s))
    }

    // MARK: Calibration

    /// Starts the guided calibration on the Watch: stand still (baselines), a forehand
    /// swing, a backhand swing (they teach the Watch which way your wrist rotates).
    func startCalibration() {
        guard linkState.isConnected else {
            calibrationProgress = CalibrationProgress(step: .failed, message: "Watch not connected. Open WristPong on your Watch and keep it awake.")
            return
        }
        calibrationProgress = CalibrationProgress(step: .neutral, progress: 0, secondsLeft: 3, message: "Hold the paddle hand still")
        link.send(.command(.startCalibration))
    }

    func cancelCalibration() {
        link.send(.command(.cancelCalibration))
        calibrationProgress = nil
    }

    func clearCalibrationStatus() { calibrationProgress = nil }

    func resetCalibration() {
        onCalibration?(.default)
        link.send(.command(.setCalibration(.default)))
        calibrationProgress = nil
    }

    // MARK: Simulated paddle

    func simulate(_ input: SimulatedInput) {
        let e = sim.event(for: input, at: Date().timeIntervalSince1970)
        ingest(e, age: 0, source: "SIM")
    }

    // MARK: Incoming

    private func handle(_ dict: [String: Any], receivedAt: Double) {
        guard let message = WireMessage(dictionary: dict) else { return }
        monitor.heard(at: receivedAt)
        switch message {
        case .paddle(let event, let seq, let sensorTime, _):
            if lastSeq >= 0, seq > lastSeq + 1 { packetsLost += seq - lastSeq - 1 }
            lastSeq = seq
            let now = Date().timeIntervalSince1970
            // How long ago did the contact happen? Exact when clocks are synced, assumed otherwise.
            let contact = clock.isSynced ? clock.toPhoneTime(sensorTime) : now - 0.15
            let age = max(0, min(0.6, now - contact))
            latencyTracker.record(milliseconds: age * 1000)
            latency = latencyTracker.stats
            ingest(event, age: age, source: "WATCH")

        case .heartbeat(_, _, let mode):
            watchMode = mode

        case .pong(_, let pingSent, let watchTime):
            clock.addSample(pingSent: pingSent, watchTime: watchTime, pongReceived: receivedAt)

        case .calibrationProgress(let p):
            calibrationProgress = p

        case .calibrationResult(let c):
            if let p = calibrationProgress, p.step != .done, p.step != .idle, p.step != .failed {
                calibrationProgress = CalibrationProgress(step: .done, progress: 1, message: "Calibrated")
            }
            onCalibration?(c)

        case .rawBatch(let batch):
            if let last = batch.last {
                rawAccel = last.accel
                rawGyro = last.gyro
            }

        case .decision(_, let label, _, let confidence):
            lastDecision = "\(label)  \(Int(confidence * 100))%"

        default:
            break
        }
        refreshLink()
    }

    private func ingest(_ event: PaddleEvent, age: Double, source: String) {
        lastGesture = event.code
        lastConfidence = event.confidence
        lastPower = event.swing?.power ?? 0
        log("\(event.code)  \(Int(event.confidence * 100))%  [\(source)]")
        onPaddle?(event, age)
    }

    private func log(_ text: String) {
        eventLog.insert(LogEntry(time: Date(), text: text), at: 0)
        if eventLog.count > 120 { eventLog.removeLast(eventLog.count - 120) }
    }

    func clearLog() {
        eventLog.removeAll()
        packetsLost = 0
        latencyTracker.reset()
        latency = LatencyStats()
    }
}
