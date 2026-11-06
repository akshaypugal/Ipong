import WatchKit
import PongCore

/// Haptic patterns for the Watch. The iPhone decides *what* happened and sends
/// a `PongHaptic`; the Watch decides how it feels on the wrist.
enum WatchHaptics {
    /// Instant feedback the moment a swing is detected (no round trip).
    static func tick() {
        WKInterfaceDevice.current().play(.click)
    }

    static func play(_ cue: PongHaptic) {
        for (type, delay) in pattern(for: cue) {
            if delay <= 0 {
                WKInterfaceDevice.current().play(type)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    WKInterfaceDevice.current().play(type)
                }
            }
        }
    }

    private static func pattern(for cue: PongHaptic) -> [(WKHapticType, Double)] {
        switch cue {
        case .ballOnYourSide:
            return [(.click, 0)]
        case .perfectHit:
            return [(.success, 0), (.click, 0.18)]
        case .goodHit:
            return [(.click, 0)]
        case .weakHit:
            return [(.directionDown, 0)]
        case .smashHit:
            return [(.success, 0), (.click, 0.10), (.click, 0.20)]
        case .whiff:
            return [(.retry, 0)]
        case .netCord:
            return [(.click, 0), (.click, 0.08)]
        case .serveReady:
            return [(.start, 0)]
        case .toss:
            return [(.directionUp, 0)]
        case .pointWon:
            return [(.success, 0)]
        case .pointLost:
            return [(.failure, 0)]
        case .gameWon:
            return [(.success, 0), (.success, 0.40)]
        case .gameLost:
            return [(.failure, 0), (.click, 0.30)]
        case .matchWon:
            return [(.success, 0), (.success, 0.35), (.success, 0.70)]
        case .matchLost:
            return [(.failure, 0), (.stop, 0.45)]
        }
    }
}
