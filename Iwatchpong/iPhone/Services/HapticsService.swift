import UIKit
import PongCore

/// Haptics on the iPhone. The Watch plays its own patterns (see WatchHaptics);
/// this keeps the phone alive in your other hand or on a stand.
final class HapticsService {
    var enabled = true

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        light.prepare()
        medium.prepare()
        heavy.prepare()
        notification.prepare()
    }

    func play(_ cue: PongHaptic) {
        guard enabled else { return }
        switch cue {
        case .ballOnYourSide, .netCord, .toss:
            light.impactOccurred(intensity: 0.5)
        case .perfectHit, .smashHit:
            heavy.impactOccurred()
        case .goodHit:
            medium.impactOccurred()
        case .weakHit, .whiff:
            light.impactOccurred()
        case .serveReady:
            medium.impactOccurred(intensity: 0.7)
        case .pointWon, .gameWon, .matchWon:
            notification.notificationOccurred(.success)
        case .pointLost, .gameLost:
            notification.notificationOccurred(.warning)
        case .matchLost:
            notification.notificationOccurred(.error)
        }
    }
}
