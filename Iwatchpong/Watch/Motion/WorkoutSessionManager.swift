import Foundation
import HealthKit

/// Keeps the Watch app running while you play.
///
/// watchOS suspends apps (and their motion updates) as soon as the wrist drops
/// or the screen sleeps. A workout session is the supported way to stay alive
/// and keep reading sensors; WristPong uses a *table tennis* workout and discards it
/// at the end - nothing is written to Apple Health.
///
/// If HealthKit is unavailable or not authorised, everything still works while
/// the app is in the foreground.
final class WorkoutSessionManager: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var starting = false
    /// Bumped by every start/stop so a stale authorisation callback cannot start a session.
    private var generation = 0

    var isActive: Bool { session != nil }

    /// Starts the session (requesting authorisation the first time).
    /// - Parameter configuration: pass the one the iPhone launched us with, if any.
    func start(configuration: HKWorkoutConfiguration? = nil) {
        guard HKHealthStore.isHealthDataAvailable(), session == nil, !starting else { return }
        starting = true
        generation += 1
        let gen = generation
        let types: Set<HKSampleType> = [HKObjectType.workoutType()]
        store.requestAuthorization(toShare: types, read: []) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, self.generation == gen else { return }
                self.begin(configuration: configuration)
            }
        }
    }

    private func begin(configuration: HKWorkoutConfiguration?) {
        defer { starting = false }
        guard session == nil else { return }
        let config = configuration ?? {
            let c = HKWorkoutConfiguration()
            c.activityType = .tableTennis
            c.locationType = .indoor
            return c
        }()
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            s.delegate = self
            b.delegate = self
            session = s
            builder = b
            let now = Date()
            s.startActivity(with: now)
            b.beginCollection(withStart: now) { _, _ in }
        } catch {
            session = nil
            builder = nil
        }
    }

    /// Ends the session and throws the workout away.
    func stop() {
        starting = false
        generation += 1
        guard let s = session else { return }
        let b = builder
        session = nil
        builder = nil
        s.end()
        b?.endCollection(withEnd: Date()) { _, _ in
            b?.discardWorkout()
        }
    }

    // MARK: HKWorkoutSessionDelegate

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {
        // The system can end a session on its own: forget it so a new one can start.
        if toState == .ended {
            DispatchQueue.main.async { [weak self] in
                if self?.session === workoutSession {
                    self?.session = nil
                    self?.builder = nil
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.session = nil
            self?.builder = nil
        }
    }

    // MARK: HKLiveWorkoutBuilderDelegate

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
