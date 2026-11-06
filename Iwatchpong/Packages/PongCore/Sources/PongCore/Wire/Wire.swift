import Foundation

// MARK: - Supporting payload types

/// What the Watch's motion pipeline is doing.
public enum MotionMode: String, Codable, Sendable {
    /// Sensors off (battery friendly).
    case off
    /// Recognising strokes and streaming them to the iPhone.
    case play
    /// Recognising strokes and showing them on the Watch only.
    case practice
}

public enum CalibrationStep: String, Codable, Sendable {
    case idle
    case neutral
    case forehand
    case backhand
    case done
    case failed
}

public struct CalibrationProgress: Codable, Equatable, Sendable {
    public var step: CalibrationStep
    public var progress: Double
    public var secondsLeft: Int
    public var message: String

    public init(step: CalibrationStep, progress: Double = 0, secondsLeft: Int = 0, message: String = "") {
        self.step = step
        self.progress = progress
        self.secondsLeft = secondsLeft
        self.message = message
    }
}

public enum WatchPhase: String, Codable, Sendable {
    case idle
    case serveReady
    case tossing
    case rally
    case pointOver
    case gameOver
    case matchOver
}

/// What the Watch UI shows during a match.
public struct MatchSummary: Codable, Equatable, Sendable {
    public var phase: WatchPhase
    public var humanPoints: Int
    public var opponentPoints: Int
    public var humanGames: Int
    public var opponentGames: Int
    /// True when the human serves (or is about to).
    public var humanServes: Bool
    public var rally: Int
    public var sentTime: TimeInterval

    public init(phase: WatchPhase = .idle, humanPoints: Int = 0, opponentPoints: Int = 0, humanGames: Int = 0,
                opponentGames: Int = 0, humanServes: Bool = true, rally: Int = 0, sentTime: TimeInterval = 0) {
        self.phase = phase
        self.humanPoints = humanPoints
        self.opponentPoints = opponentPoints
        self.humanGames = humanGames
        self.opponentGames = opponentGames
        self.humanServes = humanServes
        self.rally = rally
        self.sentTime = sentTime
    }
}

/// Haptic patterns the iPhone can ask the Watch to play.
public enum PongHaptic: String, Codable, CaseIterable, Sendable {
    /// The ball just bounced on your side: swing on the beat.
    case ballOnYourSide
    case perfectHit
    case goodHit
    case weakHit
    case smashHit
    case whiff
    case netCord
    case serveReady
    case toss
    case pointWon
    case pointLost
    case gameWon
    case gameLost
    case matchWon
    case matchLost
}

public enum WatchCommand: Equatable, Sendable {
    case setMode(MotionMode)
    case startCalibration
    case cancelCalibration
    case setDebugStream(Bool)
    case setConfig(SwingConfig)
    case setCalibration(SwingCalibration)
    case setLocalHaptics(Bool)
}

/// A batch of raw sensor readings for the Debug screen. Flat array, stride 7:
/// `t, userAccelX, userAccelY, userAccelZ, gyroX, gyroY, gyroZ`.
public struct RawBatch: Equatable, Sendable {
    public static let stride = 7
    public var values: [Double]

    public init(values: [Double]) { self.values = values }

    public init(samples: [MotionSample]) {
        var v: [Double] = []
        v.reserveCapacity(samples.count * RawBatch.stride)
        for s in samples {
            v.append(contentsOf: [s.timestamp, s.userAccel.x, s.userAccel.y, s.userAccel.z,
                                  s.rotationRate.x, s.rotationRate.y, s.rotationRate.z])
        }
        values = v
    }

    public var count: Int { values.count / RawBatch.stride }

    public var last: (time: Double, accel: Vec3, gyro: Vec3)? {
        guard count > 0 else { return nil }
        let i = (count - 1) * RawBatch.stride
        return (values[i], Vec3(values[i + 1], values[i + 2], values[i + 3]), Vec3(values[i + 4], values[i + 5], values[i + 6]))
    }
}

// MARK: - Wire message

/// Everything exchanged between Watch and iPhone, as a plist-safe dictionary for WatchConnectivity.
public enum WireMessage: Equatable, Sendable {
    case paddle(PaddleEvent, seq: Int, sensorTime: Double, sentTime: Double)
    case heartbeat(seq: Int, sentTime: Double, mode: MotionMode)
    case ping(id: Int, sentTime: Double)
    case pong(id: Int, pingSentTime: Double, watchTime: Double)
    case state(MatchSummary)
    case haptic(PongHaptic)
    case command(WatchCommand)
    case calibrationProgress(CalibrationProgress)
    case calibrationResult(SwingCalibration)
    case rawBatch(RawBatch)
    case decision(time: Double, label: String, peak: Double, confidence: Double)

    // MARK: Encode

    public var dictionary: [String: Any] {
        switch self {
        case .paddle(let e, let seq, let sensor, let sent):
            var d: [String: Any] = ["k": "p", "seq": seq, "st": sensor, "tx": sent, "n": e.code, "c": e.confidence]
            if case .swing(let s) = e {
                d["sk"] = s.stroke.rawValue
                d["sd"] = s.side.rawValue
                d["pw"] = s.power
                d["sp"] = s.speed
                d["ts"] = s.topspin
                d["ss"] = s.sidespin
                d["du"] = s.duration
            }
            return d
        case .heartbeat(let seq, let sent, let mode):
            return ["k": "hb", "seq": seq, "tx": sent, "m": mode.rawValue]
        case .ping(let id, let sent):
            return ["k": "ping", "id": id, "tx": sent]
        case .pong(let id, let pingSent, let watchTime):
            return ["k": "pong", "id": id, "t0": pingSent, "tw": watchTime]
        case .state(let s):
            return ["k": "state", "d": Self.encode(s)]
        case .haptic(let cue):
            return ["k": "haptic", "h": cue.rawValue]
        case .command(let c):
            return Self.encodeCommand(c)
        case .calibrationProgress(let p):
            return ["k": "calp", "d": Self.encode(p)]
        case .calibrationResult(let c):
            return ["k": "calr", "d": Self.encode(c)]
        case .rawBatch(let b):
            return ["k": "raw", "v": b.values]
        case .decision(let t, let label, let peak, let conf):
            return ["k": "dec", "t": t, "l": label, "pk": peak, "c": conf]
        }
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    static func decode<T: Decodable>(_ type: T.Type, _ any: Any?) -> T? {
        guard let data = any as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func encodeCommand(_ c: WatchCommand) -> [String: Any] {
        switch c {
        case .setMode(let m): return ["k": "cmd", "c": "mode", "m": m.rawValue]
        case .startCalibration: return ["k": "cmd", "c": "calStart"]
        case .cancelCalibration: return ["k": "cmd", "c": "calCancel"]
        case .setDebugStream(let on): return ["k": "cmd", "c": "debug", "b": on]
        case .setConfig(let cfg): return ["k": "cmd", "c": "config", "d": encode(cfg)]
        case .setCalibration(let cal): return ["k": "cmd", "c": "calibration", "d": encode(cal)]
        case .setLocalHaptics(let on): return ["k": "cmd", "c": "localHaptics", "b": on]
        }
    }

    // MARK: Decode

    static func double(_ d: [String: Any], _ key: String) -> Double? {
        if let v = d[key] as? Double { return v }
        if let v = d[key] as? Int { return Double(v) }
        if let v = d[key] as? NSNumber { return v.doubleValue }
        return nil
    }

    static func int(_ d: [String: Any], _ key: String) -> Int? {
        if let v = d[key] as? Int { return v }
        if let v = d[key] as? Double { return Int(v) }
        if let v = d[key] as? NSNumber { return v.intValue }
        return nil
    }

    /// Returns nil for malformed or unknown messages (never crashes on bad input).
    public init?(dictionary d: [String: Any]) {
        guard let kind = d["k"] as? String else { return nil }
        switch kind {
        case "p":
            guard let name = d["n"] as? String,
                  let seq = Self.int(d, "seq"),
                  let sensor = Self.double(d, "st"),
                  let sent = Self.double(d, "tx") else { return nil }
            let conf = Self.double(d, "c") ?? 1
            if name == "TOSS" {
                self = .paddle(.toss(SwingMeta(confidence: conf, timestamp: sensor)), seq: seq, sensorTime: sensor, sentTime: sent)
                return
            }
            guard let skRaw = d["sk"] as? String, let stroke = StrokeKind(rawValue: skRaw) else { return nil }
            let side = (d["sd"] as? String).flatMap(StrokeSide.init(rawValue:)) ?? .either
            let result = SwingResult(stroke: stroke, side: side,
                                     power: Self.double(d, "pw") ?? 0.5,
                                     speed: Self.double(d, "sp") ?? 0,
                                     topspin: Self.double(d, "ts") ?? 0,
                                     sidespin: Self.double(d, "ss") ?? 0,
                                     confidence: conf, timestamp: sensor,
                                     duration: Self.double(d, "du") ?? 0.15)
            self = .paddle(.swing(result), seq: seq, sensorTime: sensor, sentTime: sent)

        case "hb":
            guard let seq = Self.int(d, "seq"), let sent = Self.double(d, "tx") else { return nil }
            let mode = (d["m"] as? String).flatMap(MotionMode.init(rawValue:)) ?? .off
            self = .heartbeat(seq: seq, sentTime: sent, mode: mode)

        case "ping":
            guard let id = Self.int(d, "id"), let sent = Self.double(d, "tx") else { return nil }
            self = .ping(id: id, sentTime: sent)

        case "pong":
            guard let id = Self.int(d, "id"), let t0 = Self.double(d, "t0"), let tw = Self.double(d, "tw") else { return nil }
            self = .pong(id: id, pingSentTime: t0, watchTime: tw)

        case "state":
            guard let s = Self.decode(MatchSummary.self, d["d"]) else { return nil }
            self = .state(s)

        case "haptic":
            guard let raw = d["h"] as? String, let cue = PongHaptic(rawValue: raw) else { return nil }
            self = .haptic(cue)

        case "cmd":
            guard let c = d["c"] as? String else { return nil }
            switch c {
            case "mode":
                guard let raw = d["m"] as? String, let m = MotionMode(rawValue: raw) else { return nil }
                self = .command(.setMode(m))
            case "calStart": self = .command(.startCalibration)
            case "calCancel": self = .command(.cancelCalibration)
            case "debug":
                guard let on = d["b"] as? Bool else { return nil }
                self = .command(.setDebugStream(on))
            case "config":
                guard let cfg = Self.decode(SwingConfig.self, d["d"]) else { return nil }
                self = .command(.setConfig(cfg))
            case "calibration":
                guard let cal = Self.decode(SwingCalibration.self, d["d"]) else { return nil }
                self = .command(.setCalibration(cal))
            case "localHaptics":
                guard let on = d["b"] as? Bool else { return nil }
                self = .command(.setLocalHaptics(on))
            default: return nil
            }

        case "calp":
            guard let p = Self.decode(CalibrationProgress.self, d["d"]) else { return nil }
            self = .calibrationProgress(p)

        case "calr":
            guard let c = Self.decode(SwingCalibration.self, d["d"]) else { return nil }
            self = .calibrationResult(c)

        case "raw":
            if let v = d["v"] as? [Double] {
                self = .rawBatch(RawBatch(values: v))
            } else if let v = d["v"] as? [NSNumber] {
                self = .rawBatch(RawBatch(values: v.map { $0.doubleValue }))
            } else {
                return nil
            }

        case "dec":
            guard let t = Self.double(d, "t"), let l = d["l"] as? String,
                  let pk = Self.double(d, "pk"), let c = Self.double(d, "c") else { return nil }
            self = .decision(time: t, label: l, peak: pk, confidence: c)

        default:
            return nil
        }
    }
}

/// Settings the iPhone keeps in sync with the Watch through `updateApplicationContext`:
/// delivered even when the Watch app is not running, and available after a restart.
public struct SyncContext: Equatable, Sendable {
    public var calibration: SwingCalibration
    public var config: SwingConfig
    public var localHaptics: Bool

    public init(calibration: SwingCalibration, config: SwingConfig, localHaptics: Bool) {
        self.calibration = calibration
        self.config = config
        self.localHaptics = localHaptics
    }

    public var dictionary: [String: Any] {
        ["k": "ctx",
         "cal": WireMessage.encode(calibration),
         "cfg": WireMessage.encode(config),
         "lh": localHaptics]
    }

    public init?(dictionary d: [String: Any]) {
        guard d["k"] as? String == "ctx" else { return nil }
        calibration = WireMessage.decode(SwingCalibration.self, d["cal"]) ?? .default
        config = WireMessage.decode(SwingConfig.self, d["cfg"]) ?? .default
        localHaptics = d["lh"] as? Bool ?? true
    }
}

// MARK: - Haptic mapping

public extension MatchEvent {
    /// The Watch haptic that should accompany this event, if any. One cue per moment.
    public var hapticCue: PongHaptic? {
        switch self {
        case .ballOnYourSide:
            return .ballOnYourSide
        case .shot(let s):
            guard s.hitter == .human else { return nil }
            if s.stroke == .smash, s.quality > 0.5 { return .smashHit }
            if s.timing == .perfect { return .perfectHit }
            if s.quality < 0.45 { return .weakHit }
            return .goodHit
        case .whiff(let reason):
            return reason == .needToss || reason == .notInPlay ? nil : .whiff
        case .netTouch(let kind):
            return kind == .clip ? .netCord : nil
        case .serveReady(let p):
            return p == .human ? .serveReady : nil
        case .tossStarted(let p):
            return p == .human ? .toss : nil
        case .point(let info):
            return info.winner == .human ? .pointWon : .pointLost
        case .gameWon(let w, _, _):
            return w == .human ? .gameWon : .gameLost
        case .matchWon(let w):
            return w == .human ? .matchWon : .matchLost
        default:
            return nil
        }
    }
}

public extension MatchEngine {
    /// Compact state for the Watch UI.
    var watchSummary: MatchSummary {
        let p: WatchPhase
        switch phase {
        case .notStarted, .drillOver: p = .idle
        case .serveReady: p = .serveReady
        case .tossing: p = .tossing
        case .rally: p = .rally
        case .pointOver: p = .pointOver
        case .gameOver: p = .gameOver
        case .matchOver: p = .matchOver
        }
        return MatchSummary(phase: p, humanPoints: score.humanPoints, opponentPoints: score.opponentPoints,
                            humanGames: score.humanGames, opponentGames: score.opponentGames,
                            humanServes: snapshot.server == .human, rally: rallyCount)
    }
}
