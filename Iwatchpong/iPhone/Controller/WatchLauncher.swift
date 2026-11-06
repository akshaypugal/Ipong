import Foundation
import HealthKit

/// Wakes the WristPong Watch app from the iPhone.
///
/// Starting a (table tennis) workout on the Watch through HealthKit is the supported
/// way to launch a Watch app in the background; the Watch app then starts its
/// own workout session, which keeps the motion sensors running while you play.
enum WatchLauncher {
    private static let store = HKHealthStore()

    static func launch(completion: ((Bool) -> Void)? = nil) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion?(false)
            return
        }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .tableTennis
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { success, _ in
            DispatchQueue.main.async { completion?(success) }
        }
    }
}
