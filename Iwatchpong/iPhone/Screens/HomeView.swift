import SwiftUI
import PongCore

struct HomeView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var controller: PaddleController

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    LevelBadge(profile: env.profile)
                        .padding(14)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    connection
                    VStack(spacing: 12) {
                        Button { env.router.push(.play) } label: { menuLabel("🏓", "QUICK MATCH", "Pick an opponent and play") }
                            .buttonStyle(BigButtonStyle(height: 76))
                        Button { env.router.push(.career) } label: { menuLabel("🏆", "CAREER", careerSubtitle) }
                            .buttonStyle(BigButtonStyle(colors: [Theme.blue, Color(hex: "1F4FA8")], height: 76))
                        Button { env.router.push(.training) } label: { menuLabel("🎯", "TRAINING", "\(env.profile.totalDrillStars) stars \u{00B7} learn every stroke") }
                            .buttonStyle(BigButtonStyle(colors: [Theme.green, Color(hex: "177A4D")], height: 76))
                    }
                    HStack(spacing: 12) {
                        tile("UPGRADES", "⬆️", route: .upgrades)
                        tile("DAILY", "📅", route: .challenges, badge: env.profile.daily.claimableCount)
                        tile("STATS", "📊", route: .stats)
                    }
                    HStack(spacing: 12) {
                        tile("SETTINGS", "⚙️", route: .settings)
                        if env.profile.settings.developerMode {
                            tile("DEBUG", "🧪", route: .debug)
                        }
                    }
                }
                .padding(18)
            }
        }
    }

    private var careerSubtitle: String {
        let p = env.profile
        if p.careerCleared { return "Cleared! Pro Tour tier \(p.maxTier)" }
        return "Opponent \(p.careerProgress + 1) of \(OpponentProfile.roster.count)"
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("WRIST").font(.heavy(40)).foregroundColor(.white)
                Text("PONG").font(.heavy(40)).foregroundStyle(Theme.fire)
            }
            Spacer()
            CoinLabel(coins: env.profile.coins)
        }
    }

    @ViewBuilder private var connection: some View {
        HStack {
            ConnectionBadge()
            Spacer()
            if !controller.linkState.isConnected, !controller.simulatorEnabled {
                Button("Help") { env.router.push(.settings) }.buttonStyle(SmallButtonStyle(tint: Theme.blue))
            }
        }
    }

    private func menuLabel(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Text(icon).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.heavy(22))
                Text(subtitle).font(.rounded(12)).opacity(0.85)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold)).opacity(0.7)
        }
        .padding(.horizontal, 18)
    }

    private func tile(_ title: String, _ icon: String, route: Route, badge: Int = 0) -> some View {
        Button { env.router.push(route) } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Text(icon).font(.system(size: 28))
                    if badge > 0 {
                        Text("\(badge)").font(.heavy(11)).foregroundColor(.white)
                            .padding(5).background(Theme.red).clipShape(Circle())
                            .offset(x: 12, y: -8)
                    }
                }
                Text(title).font(.heavy(12)).foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.cardStroke, lineWidth: 1))
        }
    }
}

// MARK: - Quick match

struct PlayView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var opponent = 0
    @State private var tier = 0
    @State private var format: MatchFormat = .standard

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ScreenHeader(title: "QUICK MATCH", subtitle: "Exhibition. Rewards are reduced vs career") { env.router.pop() }
                    ConnectionBadge()

                    Text("OPPONENT").font(.heavy(13)).foregroundColor(Theme.textDim)
                    ForEach(OpponentProfile.roster) { o in
                        OpponentRow(opponent: o, selected: opponent == o.id, locked: !env.profile.isUnlocked(opponent: o.id),
                                    wins: env.profile.opponentWins[safe: o.id] ?? 0)
                            .onTapGesture {
                                if env.profile.isUnlocked(opponent: o.id) { opponent = o.id }
                            }
                    }

                    Text("FORMAT").font(.heavy(13)).foregroundColor(Theme.textDim)
                    HStack(spacing: 8) {
                        ForEach(MatchFormat.allCases) { f in
                            Button { format = f } label: {
                                VStack(spacing: 2) {
                                    Text(f.title).font(.heavy(14))
                                    Text(f.subtitle).font(.rounded(10)).opacity(0.8)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(format == f ? Theme.blue : Theme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }

                    if env.profile.maxTier > 0 {
                        Text("PRO TOUR TIER").font(.heavy(13)).foregroundColor(Theme.textDim)
                        Picker("Tier", selection: $tier) {
                            Text("Normal").tag(0)
                            ForEach(1...env.profile.maxTier, id: \.self) { Text("Tier \($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    Button("START MATCH") {
                        env.router.push(.match(MatchSetup(opponent: opponent, tier: tier, format: format)))
                    }
                    .buttonStyle(BigButtonStyle())
                    .padding(.top, 8)
                }
                .padding(18)
            }
        }
        .onAppear { format = env.profile.settings.matchFormat }
        .navigationBarBackButtonHidden(true)
    }
}

struct OpponentRow: View {
    let opponent: OpponentProfile
    var selected = false
    var locked = false
    var wins = 0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(hex: opponent.shirtHex)).frame(width: 46, height: 46)
                Text(locked ? "🔒" : String(opponent.name.prefix(1)))
                    .font(.heavy(20)).foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(opponent.name).font(.heavy(16)).foregroundColor(.white)
                    Text(opponent.style.title).font(.heavy(9)).foregroundColor(Theme.gold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.gold.opacity(0.15)).clipShape(Capsule())
                }
                Text(opponent.tagline).font(.rounded(11)).foregroundColor(Theme.textDim).lineLimit(2)
            }
            Spacer()
            if wins > 0 { Text("🏅\(wins)").font(.rounded(12)).foregroundColor(Theme.gold) }
        }
        .padding(12)
        .background(selected ? Theme.blue.opacity(0.28) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(selected ? Theme.blue : Theme.cardStroke, lineWidth: selected ? 2 : 1))
        .opacity(locked ? 0.45 : 1)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Career

struct CareerView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var tier = 0

    var body: some View {
        let p = env.profile
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "CAREER", subtitle: p.careerCleared ? "Pro Tour unlocked" : "Beat every opponent to the top") { env.router.pop() }
                    ConnectionBadge()
                    if p.maxTier > 0 {
                        Picker("Tier", selection: $tier) {
                            Text("Career").tag(0)
                            ForEach(1...p.maxTier, id: \.self) { Text("Pro Tour \($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    ForEach(OpponentProfile.roster) { o in
                        let unlocked = p.isUnlocked(opponent: o.id)
                        let current = o.id == p.careerProgress
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(o.rank.title).font(.heavy(11)).foregroundColor(Theme.gold)
                                Spacer()
                                if o.id < p.careerProgress { Text("DEFEATED \u{2713}").font(.heavy(11)).foregroundColor(Theme.green) }
                            }
                            OpponentRow(opponent: o, selected: current, locked: !unlocked, wins: p.opponentWins[safe: o.id] ?? 0)
                            if unlocked {
                                Button(current ? "PLAY" : "REMATCH") {
                                    env.router.push(.match(MatchSetup(opponent: o.id, tier: tier, format: p.settings.matchFormat)))
                                }
                                .buttonStyle(SmallButtonStyle(tint: current ? Theme.red : Theme.blue))
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Training

struct TrainingView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader(title: "TRAINING", subtitle: "A ball machine feeds you one shot at a time") { env.router.pop() }
                    ConnectionBadge()
                    ForEach(DrillKind.allCases) { kind in
                        let spec = DrillSpec.spec(for: kind)
                        let stars = env.profile.drillStars[kind.rawValue] ?? 0
                        let best = env.profile.drillBest[kind.rawValue] ?? 0
                        Button { env.router.push(.drill(kind)) } label: {
                            Card {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(spec.title.uppercased()).font(.heavy(16)).foregroundColor(.white)
                                        Text(spec.instruction).font(.rounded(12)).foregroundColor(Theme.textDim)
                                            .multilineTextAlignment(.leading).lineLimit(2)
                                        Text("Best \(best) / \(spec.totalBalls)").font(.rounded(11)).foregroundColor(Theme.textDim)
                                    }
                                    Spacer()
                                    HStack(spacing: 2) {
                                        ForEach(0..<3, id: \.self) { i in
                                            Image(systemName: i < stars ? "star.fill" : "star")
                                                .foregroundColor(i < stars ? Theme.gold : Color.white.opacity(0.3))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
