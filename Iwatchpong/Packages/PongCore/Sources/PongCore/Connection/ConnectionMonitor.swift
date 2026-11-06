import Foundation

/// Link state shown to the player ("WATCH CONNECTED" / "WATCH DISCONNECTED").
public enum LinkState: String, Equatable, Sendable {
    /// WatchConnectivity is not supported on this device.
    case unsupported
    /// No Watch is paired with this iPhone.
    case notPaired
    /// A Watch is paired but the WristPong Watch app is not installed.
    case appNotInstalled
    /// Session not yet activated.
    case inactive
    /// Paired and installed, but the Watch app is not reachable (not running / out of range).
    case disconnected
    case connected

    public var isConnected: Bool { self == .connected }

    public var headline: String {
        isConnected ? "WATCH CONNECTED" : "WATCH DISCONNECTED"
    }

    public var detail: String {
        switch self {
        case .unsupported: return "This device does not support Apple Watch."
        case .notPaired: return "Pair an Apple Watch with this iPhone."
        case .appNotInstalled: return "Install WristPong on your Watch (Watch app > My Watch)."
        case .inactive: return "Connecting..."
        case .disconnected: return "Open WristPong on your Watch and keep it awake."
        case .connected: return "Ready to fight."
        }
    }
}

/// Pure state machine that decides whether the Watch counts as connected.
///
/// A Watch is "connected" when the OS reports it reachable *and* we have heard
/// from it (heartbeat or gesture) recently. This catches the common case where
/// the Watch app was suspended but `isReachable` has not flipped yet.
public struct ConnectionMonitor: Sendable {
    public var heartbeatTimeout: Double

    public private(set) var supported = true
    public private(set) var paired = true
    public private(set) var appInstalled = true
    public private(set) var activated = false
    public private(set) var reachable = false
    private var reachableSince: Double?
    private var lastHeard: Double?

    public init(heartbeatTimeout: Double = 4.0) {
        self.heartbeatTimeout = heartbeatTimeout
    }

    public mutating func update(supported: Bool? = nil, paired: Bool? = nil, appInstalled: Bool? = nil,
                                activated: Bool? = nil, reachable: Bool? = nil, now: Double) {
        if let v = supported { self.supported = v }
        if let v = paired { self.paired = v }
        if let v = appInstalled { self.appInstalled = v }
        if let v = activated { self.activated = v }
        if let v = reachable {
            if v && !self.reachable { reachableSince = now }
            if !v { reachableSince = nil }
            self.reachable = v
        }
    }

    /// Call whenever anything arrives from the Watch.
    public mutating func heard(at now: Double) {
        lastHeard = now
    }

    /// Forget everything (e.g. after the app restarts or the session is re-activated).
    public mutating func reset() {
        activated = false
        reachable = false
        reachableSince = nil
        lastHeard = nil
    }

    public func state(now: Double) -> LinkState {
        guard supported else { return .unsupported }
        guard activated else { return .inactive }
        guard paired else { return .notPaired }
        guard appInstalled else { return .appNotInstalled }
        guard reachable else { return .disconnected }
        let reference = max(lastHeard ?? -.infinity, reachableSince ?? -.infinity)
        return now - reference <= heartbeatTimeout ? .connected : .disconnected
    }
}
