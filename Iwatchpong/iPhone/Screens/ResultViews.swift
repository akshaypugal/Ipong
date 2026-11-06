import SwiftUI
import PongCore

struct MatchResultView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ZStack {
            ScreenBackground()
            if let r = env.lastMatch {
                ScrollView {
                    VStack(spacing: 16) {
                        Text(r.outcome.humanWon ? "VICTORY" : "DEFEAT")
                            .font(.heavy(46))
                            .foregroundColor(r.outcome.humanWon ? Theme.gold : Theme.red)
                            .padding(.top, 20)
                        Text("vs \(r.opponent.name)").font(.rounded(18)).foregroundColor(Theme.textDim)
                        Text("\(r.outcome.humanGames) - \(r.outcome.opponentGames)").font(.heavy(60)).foregroundColor(.white)

                        HStack(spacing: 8) {
                            ForEach(Array(r.outcome.gameScores.enumerated()), id: \.offset) { _, g in
                                VStack(spacing: 2) {
                                    Text("\(g.human)-\(g.opponent)").font(.heavy(16))
                                        .foregroundColor(g.human > g.opponent ? Theme.green : Theme.red)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Theme.card).clipShape(Capsule())
                            }
                        }

                        rewards(r.reward)
                        statGrid(r.outcome.stats)

                        VStack(spacing: 10) {
                            if r.reward.unlockedOpponent != nil {
                                Text("NEW OPPONENT UNLOCKED").font(.heavy(14)).foregroundColor(Theme.gold)
                            }
                            Button("PLAY AGAIN") {
                                env.router.replaceTop(with: .match(r.setup))
                            }.buttonStyle(BigButtonStyle())
                            Button("HOME") { env.router.popToRoot() }.buttonStyle(SmallButtonStyle(tint: Theme.blue))
                        }
                    }
                    .padding(18)
                }
            } else {
                Button("HOME") { env.router.popToRoot() }.buttonStyle(BigButtonStyle())
                    .padding(40)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func rewards(_ reward: RewardSummary) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("REWARDS").font(.heavy(13)).foregroundColor(Theme.textDim)
                ForEach(Array(reward.lines.enumerated()), id: \.offset) { _, line in
                    HStack {
                        Text(line.title).font(.rounded(14)).foregroundColor(.white)
                        Spacer()
                        Text("+\(line.xp) XP").font(.rounded(12)).foregroundColor(Theme.blue)
                        Text("+\(line.coins) 🪙").font(.rounded(12)).foregroundColor(Theme.gold)
                    }
                }
                Divider().background(Theme.cardStroke)
                HStack {
                    Text("TOTAL").font(.heavy(14)).foregroundColor(.white)
                    Spacer()
                    Text("+\(reward.xp) XP").font(.heavy(14)).foregroundColor(Theme.blue)
                    Text("+\(reward.coins) 🪙").font(.heavy(14)).foregroundColor(Theme.gold)
                }
                if reward.levelsGained > 0 {
                    Text("LEVEL UP! You are now level \(reward.newLevel)").font(.heavy(14)).foregroundColor(Theme.gold)
                }
                if !reward.completedChallenges.isEmpty {
                    Text("Daily challenge complete. Claim it in DAILY").font(.rounded(12)).foregroundColor(Theme.green)
                }
            }
        }
    }

    private func statGrid(_ s: MatchStats) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                StatTile(value: "\(s.pointsWon)-\(s.pointsLost)", label: "Points")
                StatTile(value: "\(s.longestRally)", label: "Longest rally")
                StatTile(value: "\(Int(s.fastestShotKmh.rounded()))", label: "Top km/h")
            }
            HStack(spacing: 8) {
                StatTile(value: "\(s.winners)", label: "Winners", color: Theme.green)
                StatTile(value: "\(s.aces)", label: "Aces", color: Theme.gold)
                StatTile(value: "\(s.unforcedErrors)", label: "Errors", color: Theme.red)
            }
            HStack(spacing: 8) {
                StatTile(value: "\(s.topspins + s.flicks)", label: "Spin shots", color: Theme.orange)
                StatTile(value: "\(s.chops + s.pushes + s.drops)", label: "Touch shots", color: Theme.blue)
                StatTile(value: "\(s.smashes)", label: "Smashes", color: Theme.red)
            }
        }
    }
}

struct DrillResultView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ZStack {
            ScreenBackground()
            if let r = env.lastDrill {
                let spec = DrillSpec.spec(for: r.kind)
                VStack(spacing: 18) {
                    Spacer()
                    Text(spec.title.uppercased()).font(.heavy(24)).foregroundColor(Theme.gold)
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < r.stars ? "star.fill" : "star")
                                .font(.system(size: 44))
                                .foregroundColor(i < r.stars ? Theme.gold : Color.white.opacity(0.25))
                        }
                    }
                    Text("\(r.successes) / \(r.attempts) correct").font(.heavy(36)).foregroundColor(.white)
                    Text("Stars at \(spec.starThresholds.map(String.init).joined(separator: " / "))")
                        .font(.rounded(13)).foregroundColor(Theme.textDim)
                    HStack(spacing: 14) {
                        Text("+\(r.xp) XP").font(.heavy(18)).foregroundColor(Theme.blue)
                        Text("+\(r.coins) 🪙").font(.heavy(18)).foregroundColor(Theme.gold)
                    }
                    if r.levelsGained > 0 { Text("LEVEL UP!").font(.heavy(20)).foregroundColor(Theme.gold) }
                    Spacer()
                    VStack(spacing: 10) {
                        Button("TRY AGAIN") { env.router.replaceTop(with: .drill(r.kind)) }.buttonStyle(BigButtonStyle())
                        Button("TRAINING MENU") { env.router.pop() }.buttonStyle(SmallButtonStyle(tint: Theme.blue))
                        Button("HOME") { env.router.popToRoot() }.buttonStyle(SmallButtonStyle(tint: Theme.redDark))
                    }
                }
                .padding(24)
            } else {
                Button("HOME") { env.router.popToRoot() }.buttonStyle(BigButtonStyle()).padding(40)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
