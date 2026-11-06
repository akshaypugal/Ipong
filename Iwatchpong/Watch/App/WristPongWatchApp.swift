import SwiftUI
import WatchKit
import HealthKit

@main
struct WristPongWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .onChange(of: scenePhase) { phase in
                    if phase == .active { WatchModel.shared.becameActive() }
                }
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        _ = WatchModel.shared
    }

    /// The iPhone started a match and launched this app through HealthKit.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchModel.shared.workoutRequestedByPhone(workoutConfiguration)
    }
}
