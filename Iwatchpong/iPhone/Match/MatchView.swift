import SwiftUI
import PongCore

/// The match / drill screen: court, HUD, feedback overlays and (optionally) the simulated controller.
struct MatchView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var controller: PaddleController
    @StateObject private var vm: MatchViewModel
    @State private var confirmQuit = false

    init(env: AppEnvironment, kind: MatchViewModel.Kind) {
        _vm = StateObject(wrappedValue: MatchViewModel(env: env, kind: kind))
    }

    var body: some View {
        ZStack {
            court
            VStack(spacing: 0) {
                hud
                Spacer(minLength: 0)
                bottomBar
            }
            feedback
            overlays
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .confirmationDialog("Leave this \(vm.isDrill ? "drill" : "match")?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Quit (no result saved)", role: .destructive) { vm.quit() }
            Button("Restart") { vm.restart() }
            Button("Keep playing", role: .cancel) { vm.resume() }
        }
    }

    // MARK: Court

    private var court: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let renderer = CourtRenderer(snapshot: vm.snapshot, opponent: vm.opponent, trail: vm.trail,
                                             bounceMarks: vm.bounceMarks, ballAngle: vm.ballAngle,
                                             rightHanded: vm.rightHanded, showGuide: vm.showGuide,
                                             now: Date(), size: size)
                renderer.draw(&ctx)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    // MARK: HUD

    private var hud: some View {
        HStack(alignment: .top) {
            Button {
                vm.pause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            Spacer()
            scoreboard
            Spacer()
            Button {
                vm.pause()
                confirmQuit = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    @ViewBuilder private var scoreboard: some View {
        let s = vm.snapshot
        if vm.isDrill, let spec = vm.drillSpec {
            VStack(spacing: 2) {
                Text(spec.title.uppercased()).font(.heavy(13)).foregroundColor(Theme.gold)
                Text("\(s.drillSuccesses) correct  \u{00B7}  \(s.drillAttempts) / \(spec.totalBalls)")
                    .font(.heavy(18)).foregroundColor(.white)
                HStack(spacing: 4) {
                    ForEach(0..<spec.totalBalls, id: \.self) { i in
                        Circle()
                            .fill(i < s.drillAttempts ? Theme.gold.opacity(0.9) : Color.white.opacity(0.2))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(spacing: 4) {
                HStack(spacing: 14) {
                    playerScore(name: "YOU", points: s.humanPoints, games: s.humanGames, serving: s.server == .human, color: Theme.blue)
                    Text("\(s.rally)")
                        .font(.mono(12)).foregroundColor(Theme.textDim)
                        .frame(minWidth: 18)
                    playerScore(name: vm.opponent.name.uppercased(), points: s.opponentPoints, games: s.opponentGames,
                                serving: s.server == .opponent, color: Theme.red)
                }
                Text("GAME \(s.gameNumber)").font(.rounded(10)).foregroundColor(Theme.textDim)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.black.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func playerScore(name: String, points: Int, games: Int, serving: Bool, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(serving ? Theme.gold : Color.clear).frame(width: 6, height: 6)
                Text(name).font(.heavy(11)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.6)
            }
            Text("\(points)").font(.heavy(30)).foregroundColor(.white).monospacedDigit()
            HStack(spacing: 3) {
                ForEach(0..<max(1, games), id: \.self) { i in
                    Circle().fill(i < games ? color : Color.white.opacity(0.15)).frame(width: 6, height: 6)
                }
            }
        }
        .frame(minWidth: 64)
    }

    // MARK: Bottom

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 8) {
            if controller.simulatorEnabled {
                SimPaddleView().padding(.horizontal, 10)
            } else {
                Text(hintText)
                    .font(.rounded(13))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
            }
            if env.profile.settings.showLatency, controller.linkState.isConnected {
                Text("latency \(Int(controller.latency.average)) ms  \u{00B7}  lost \(controller.packetsLost)")
                    .font(.mono(11)).foregroundColor(Theme.textDim)
            }
        }
        .padding(.bottom, 10)
    }

    private var hintText: String {
        switch vm.snapshot.phase {
        case .serveReady(.human): return "Flick your wrist up to toss, then swing"
        case .tossing(.human): return "Swing now!"
        case .rally: return "Swing when the ball bounces on your side"
        default: return "Swing your Apple Watch like a paddle"
        }
    }

    // MARK: Feedback (banners, popups)

    private var feedback: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                ZStack {
                    ForEach(vm.popups) { p in
                        let k = min(1, timeline.date.timeIntervalSince(p.created) / p.duration)
                        Text(p.text)
                            .font(.heavy(p.size))
                            .foregroundColor(p.color)
                            .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                            .opacity(k < 0.7 ? 1 : 1 - (k - 0.7) / 0.3)
                            .position(x: geo.size.width * p.x, y: geo.size.height * p.y - CGFloat(easeOut(k)) * 28)
                    }
                    ForEach(vm.banners) { b in
                        let k = b.progress(at: timeline.date)
                        let pop = 0.8 + 0.2 * easeOut(min(1, k * 6))
                        VStack(spacing: 4) {
                            Text(b.text).font(.heavy(b.size)).foregroundColor(b.color)
                            if let sub = b.subtitle {
                                Text(sub).font(.rounded(16)).foregroundColor(.white.opacity(0.9))
                            }
                        }
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.8), radius: 6, y: 2)
                        .scaleEffect(pop)
                        .opacity(k < 0.8 ? 1 : 1 - (k - 0.8) / 0.2)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.20)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Overlays

    @ViewBuilder private var overlays: some View {
        if vm.showIntro, let spec = vm.drillSpec {
            overlayCard {
                Text(spec.title.uppercased()).font(.heavy(26)).foregroundColor(Theme.gold)
                Text(spec.instruction).font(.rounded(16)).foregroundColor(.white).multilineTextAlignment(.center)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(spec.requiredStrokes).sorted { $0.rawValue < $1.rawValue }, id: \.self) { s in
                        Text("\u{2022} \(s.displayName): \(s.howTo)").font(.rounded(13)).foregroundColor(Theme.textDim)
                    }
                }
                Text("\(spec.totalBalls) balls  \u{00B7}  \(spec.starThresholds.map(String.init).joined(separator: " / ")) correct for stars")
                    .font(.rounded(12)).foregroundColor(Theme.textDim)
                Button("START") { vm.dismissIntro() }.buttonStyle(BigButtonStyle(height: 54))
            }
        } else if let reason = vm.pauseReason {
            overlayCard {
                switch reason {
                case .user:
                    Text("PAUSED").font(.heavy(30)).foregroundColor(.white)
                    Button("RESUME") { vm.resume() }.buttonStyle(BigButtonStyle(height: 54))
                    Button("RESTART") { vm.restart() }.buttonStyle(SmallButtonStyle(tint: Theme.blue))
                    Button("QUIT") { vm.quit() }.buttonStyle(SmallButtonStyle(tint: Theme.redDark))
                case .controllerLost:
                    Text("WATCH DISCONNECTED").font(.heavy(24)).foregroundColor(Theme.red)
                    Text(controller.linkState.detail).font(.rounded(14)).foregroundColor(Theme.textDim)
                        .multilineTextAlignment(.center)
                    ConnectionBadge()
                    Button("RESUME") { vm.resume() }
                        .buttonStyle(BigButtonStyle(height: 54))
                        .disabled(!controller.hasController)
                        .opacity(controller.hasController ? 1 : 0.4)
                    Button("QUIT") { vm.quit() }.buttonStyle(SmallButtonStyle(tint: Theme.redDark))
                }
            }
        }
    }

    private func overlayCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 14) { content() }
                .padding(22)
                .frame(maxWidth: 360)
                .background(Color(hex: "151826"))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
                .padding(24)
        }
    }
}
