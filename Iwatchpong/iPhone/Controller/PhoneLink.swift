import Foundation
import WatchConnectivity
import PongCore

/// Thin wrapper around `WCSession` on the iPhone side.
///
/// Responsibilities: activate the session, expose a plain status snapshot,
/// send wire messages (instantly when reachable, never crashing when not), and
/// forward incoming dictionaries. All the decisions live in `PaddleController`.
final class PhoneLink: NSObject, WCSessionDelegate {
    struct Status {
        var supported = false
        var paired = false
        var installed = false
        var activated = false
        var reachable = false
    }

    /// Called on a background queue with every incoming message dictionary.
    var onMessage: (([String: Any]) -> Void)?
    /// Called on a background queue whenever pairing / reachability / activation changes.
    var onStatusChange: (() -> Void)?

    private let session: WCSession?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
    }

    var status: Status {
        guard let s = session else { return Status() }
        return Status(supported: true,
                      paired: s.isPaired,
                      installed: s.isWatchAppInstalled,
                      activated: s.activationState == .activated,
                      reachable: s.activationState == .activated && s.isReachable)
    }

    /// Safe to call repeatedly (e.g. every time the app returns to the foreground).
    func activate() {
        guard let s = session else { return }
        if s.activationState != .activated { s.activate() }
    }

    /// Sends immediately if the Watch app is reachable; otherwise drops the
    /// message (stale gameplay messages are worthless).
    func send(_ message: WireMessage) {
        guard let s = session, s.activationState == .activated, s.isReachable else { return }
        s.sendMessage(message.dictionary, replyHandler: nil, errorHandler: { _ in })
    }

    /// Publishes calibration / thresholds so the Watch has them even if its app
    /// is not running right now.
    func publishContext(_ context: SyncContext) {
        guard let s = session, s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        try? s.updateApplicationContext(context.dictionary)
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        onStatusChange?()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        onStatusChange?()
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // The user switched Watches: reactivate to talk to the new one.
        session.activate()
        onStatusChange?()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        onStatusChange?()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        onStatusChange?()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        onMessage?(message)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        onMessage?(message)
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        onMessage?(userInfo)
    }
}
