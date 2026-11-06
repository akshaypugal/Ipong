import SwiftUI
import PongCore

struct MatchSetup: Hashable {
    var opponent: Int
    var tier: Int = 0
    var format: MatchFormat = .standard
}

enum Route: Hashable {
    case play
    case career
    case training
    case match(MatchSetup)
    case drill(DrillKind)
    case matchResult
    case drillResult
    case upgrades
    case challenges
    case stats
    case settings
    case debug
}

final class AppRouter: ObservableObject {
    @Published var path = NavigationPath()

    func push(_ route: Route) { path.append(route) }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() { path = NavigationPath() }

    func replaceTop(with route: Route) {
        if !path.isEmpty { path.removeLast() }
        path.append(route)
    }
}

struct MatchResultSummary {
    let outcome: MatchOutcome
    let opponent: OpponentProfile
    let setup: MatchSetup
    let reward: RewardSummary
}

struct DrillResultSummary {
    let kind: DrillKind
    let successes: Int
    let attempts: Int
    let stars: Int
    let xp: Int
    let coins: Int
    let levelsGained: Int
}

/// App-wide state: the saved profile, input controller, audio and haptics.
final class AppEnvironment: ObservableObject {
    @Published var profile: PongProfile {
        didSet { persist() }
    }
    @Published var lastMatch: MatchResultSummary?
    @Published var lastDrill: DrillResultSummary?

    let store: ProfileStore
    let controller = PaddleController()
    let router = AppRouter()
    let haptics = HapticsService()
    let sound = SoundService()

    init(store: ProfileStore = FileProfileStore(url: FileProfileStore.defaultURL())) {
        self.store = store
        var loaded = store.load() ?? PongProfile()
        #if targetEnvironment(simulator)
        // No Watch in the Simulator: start in Developer Controller Mode.
        if !loaded.hasOnboarded {
            loaded.settings.simulatedController = true
            loaded.settings.developerMode = true
        }
        #endif
        loaded.daily.refreshIfNeeded(now: Date())
        profile = loaded

        controller.simulatorEnabled = loaded.settings.simulatedController
        controller.syncProvider = { [weak self] in
            guard let self else { return SyncContext(calibration: .default, config: .default, localHaptics: true) }
            return SyncContext(calibration: self.profile.calibration,
                               config: self.profile.settings.swingConfig,
                               localHaptics: self.profile.settings.localWatchHaptics)
        }
        controller.onCalibration = { [weak self] calibration in
            self?.profile.calibration = calibration
        }
        applySettings()
        controller.start()
        haptics.prepare()
    }

    // MARK: Persistence

    private func persist() {
        try? store.save(profile)
    }

    func applySettings() {
        sound.enabled = profile.settings.soundEnabled
        haptics.enabled = profile.settings.hapticsEnabled
        controller.simulatorEnabled = profile.settings.simulatedController
    }

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var s = profile.settings
        change(&s)
        profile.settings = s
        applySettings()
        controller.syncToWatch()
    }

    // MARK: Scene

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            controller.appBecameActive()
            profile.daily.refreshIfNeeded(now: Date())
        case .background:
            try? store.save(profile)
        default:
            break
        }
    }

    // MARK: Gameplay hooks

    func opponent(id: Int, tier: Int) -> OpponentProfile {
        OpponentProfile.roster[min(max(id, 0), OpponentProfile.roster.count - 1)].scaled(tier: tier)
    }

    func finishMatch(_ outcome: MatchOutcome, opponent: OpponentProfile, setup: MatchSetup) {
        var p = profile
        let reward = ProgressionService.apply(outcome: outcome, opponent: opponent, tier: setup.tier, to: &p)
        profile = p
        lastMatch = MatchResultSummary(outcome: outcome, opponent: opponent, setup: setup, reward: reward)
    }

    func finishDrill(kind: DrillKind, successes: Int, attempts: Int) {
        var p = profile
        let r = ProgressionService.applyDrill(kind: kind, successes: successes, attempts: attempts, to: &p)
        profile = p
        lastDrill = DrillResultSummary(kind: kind, successes: successes, attempts: attempts, stars: r.stars,
                                       xp: r.xp, coins: r.coins, levelsGained: r.levelsGained)
    }

    func buy(_ stat: UpgradeStat) -> Bool {
        var p = profile
        let ok = ProgressionService.purchase(stat, profile: &p)
        if ok { profile = p }
        return ok
    }

    func claim(challenge id: String) {
        var p = profile
        if ProgressionService.claimChallenge(id: id, profile: &p) != nil { profile = p }
    }

    func resetProgress() {
        var fresh = PongProfile()
        fresh.settings = profile.settings
        fresh.calibration = profile.calibration
        fresh.hasOnboarded = true
        fresh.daily.refreshIfNeeded(now: Date())
        profile = fresh
    }
}
