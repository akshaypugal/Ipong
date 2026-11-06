import Foundation
import WatchConnectivity
import PongCore

/// Thin wrapper around `WCSession` on the Watch side.
final class WatchLink: NSObject, WCSessionDelegate {
    /// Incoming message dictionaries (background queue).
    var onMessage: (([String: Any]) -> Void)?
    /// A new sync context from the iPhone (background queue).
    var onContext: ((SyncContext) -> Void)?
    /// Reachability or activation changed (background queue).
    var onStatusChange: (() -> Void)?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
    }

    var isReachable: Bool {
        guard let s = session else { return false }
        return s.activationState == .activated && s.isReachable
    }

    func activate() {
        guard let s = session else { return }
        if s.activationState != .activated { s.activate() }
    }

    /// Last context the iPhone published (available even before the first message).
    var lastContext: SyncContext? {
        guard let s = session, s.activationState == .activated else { return nil }
        return SyncContext(dictionary: s.receivedApplicationContext)
    }

    /// Sends immediately when the iPhone app is reachable, otherwise drops the
    /// message: stale gameplay events are worthless.
    func send(_ message: WireMessage) {
        guard let s = session, s.activationState == .activated, s.isReachable else { return }
        s.sendMessage(message.dictionary, replyHandler: nil, errorHandler: nil)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let ctx = SyncContext(dictionary: session.receivedApplicationContext) { onContext?(ctx) }
        onStatusChange?()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        onStatusChange?()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onMessage?(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        onMessage?(message)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let ctx = SyncContext(dictionary: applicationContext) { onContext?(ctx) }
    }
}
