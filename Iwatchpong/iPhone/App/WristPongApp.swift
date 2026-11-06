import SwiftUI
import PongCore

@main
struct WristPongApp: App {
    @StateObject private var env = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(router: env.router)
                .environmentObject(env)
                .environmentObject(env.controller)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { env.scenePhaseChanged($0) }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @ObservedObject var router: AppRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    destination(route)
                }
        }
        .fullScreenCover(isPresented: Binding(get: { !env.profile.hasOnboarded }, set: { _ in })) {
            OnboardingView()
                .environmentObject(env)
                .environmentObject(env.controller)
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .play: PlayView()
        case .career: CareerView()
        case .training: TrainingView()
        case .match(let setup): MatchView(env: env, kind: .match(setup))
        case .drill(let kind): MatchView(env: env, kind: .drill(kind))
        case .matchResult: MatchResultView()
        case .drillResult: DrillResultView()
        case .upgrades: UpgradesView()
        case .challenges: ChallengesView()
        case .stats: StatsView()
        case .settings: SettingsView()
        case .debug: DebugView()
        }
    }
}
