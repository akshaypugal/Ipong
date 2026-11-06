import SwiftUI
import PongCore

// MARK: - Upgrades

struct UpgradesView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var toast: String?

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        ScreenHeader(title: "UPGRADES", subtitle: "Spend coins to improve your player") { env.router.pop() }
                        CoinLabel(coins: env.profile.coins)
                    }
                    ForEach(UpgradeStat.allCases) { stat in
                        let level = env.profile.upgrades.level(stat)
                        let cost = env.profile.upgrades.cost(for: stat)
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("\(stat.icon) \(stat.title)").font(.heavy(18)).foregroundColor(.white)
                                    Spacer()
                                    Text("LV \(level)/\(PlayerUpgrades.maxLevel)").font(.heavy(13)).foregroundColor(Theme.gold)
                                }
                                Text(stat.blurb).font(.rounded(12)).foregroundColor(Theme.textDim)
                                BarView(fraction: Double(level) / Double(PlayerUpgrades.maxLevel),
                                        colors: [Theme.orange, Theme.gold], height: 10)
                                if let cost {
                                    Button {
                                        if env.buy(stat) { toast = "\(stat.title) upgraded" } else { toast = "Not enough coins" }
                                    } label: {
                                        Text("UPGRADE  \u{00B7}  \(cost) 🪙")
                                    }
                                    .buttonStyle(SmallButtonStyle(tint: env.profile.coins >= cost ? Theme.green : Color.gray))
                                } else {
                                    Text("MAXED").font(.heavy(13)).foregroundColor(Theme.green)
                                }
                            }
                        }
                    }
                    if let toast {
                        Text(toast).font(.rounded(13)).foregroundColor(Theme.textDim).frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Daily challenges

struct ChallengesView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "DAILY", subtitle: "Three new challenges every day") { env.router.pop() }
                    ForEach(env.profile.daily.challenges) { c in
                        Card {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text(c.kind.icon).font(.system(size: 26))
                                    Text(c.title).font(.heavy(15)).foregroundColor(.white)
                                    Spacer()
                                }
                                BarView(fraction: c.fraction, colors: [Theme.green, Color(hex: "7BE0A8")], height: 10)
                                HStack {
                                    Text("\(min(c.progress, c.target)) / \(c.target)").font(.rounded(12)).foregroundColor(Theme.textDim)
                                    Spacer()
                                    if c.claimed {
                                        Text("CLAIMED").font(.heavy(12)).foregroundColor(Theme.green)
                                    } else if c.isComplete {
                                        Button("CLAIM +\(DailyChallenge.rewardXP) XP +\(DailyChallenge.rewardCoins) 🪙") {
                                            env.claim(challenge: c.id)
                                        }.buttonStyle(SmallButtonStyle(tint: Theme.gold))
                                    } else {
                                        Text("+\(DailyChallenge.rewardXP) XP  +\(DailyChallenge.rewardCoins) 🪙")
                                            .font(.rounded(12)).foregroundColor(Theme.textDim)
                                    }
                                }
                            }
                        }
                    }
                    if env.profile.daily.challenges.isEmpty {
                        Text("No challenges yet. Check back soon.").font(.rounded(14)).foregroundColor(Theme.textDim)
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}

// MARK: - Stats

struct StatsView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        let p = env.profile
        let s = p.lifetime
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "STATS", subtitle: p.rank.title + " \u{00B7} level \(p.level)") { env.router.pop() }
                    HStack(spacing: 8) {
                        StatTile(value: "\(p.matchesPlayed)", label: "Matches")
                        StatTile(value: "\(p.matchesWon)", label: "Wins", color: Theme.green)
                        StatTile(value: p.matchesPlayed == 0 ? "-" : "\(Int(Double(p.matchesWon) / Double(p.matchesPlayed) * 100))%", label: "Win rate", color: Theme.gold)
                    }
                    HStack(spacing: 8) {
                        StatTile(value: "\(s.longestRally)", label: "Longest rally")
                        StatTile(value: "\(Int(s.fastestShotKmh.rounded()))", label: "Fastest km/h", color: Theme.red)
                        StatTile(value: "\(s.aces)", label: "Aces", color: Theme.gold)
                    }
                    Text("STROKES PLAYED").font(.heavy(13)).foregroundColor(Theme.textDim)
                    Card {
                        VStack(spacing: 10) {
                            ForEach(StrokeKind.allCases, id: \.self) { k in
                                let n = s.strokeCounts[k.rawValue] ?? 0
                                HStack {
                                    Text(k.displayName).font(.heavy(12)).foregroundColor(k.tint)
                                        .frame(width: 130, alignment: .leading)
                                    BarView(fraction: s.totalShots == 0 ? 0 : Double(n) / Double(max(1, s.totalShots)),
                                            colors: [k.tint, k.tint.opacity(0.6)], height: 8)
                                    Text("\(n)").font(.mono(12)).foregroundColor(.white).frame(width: 40, alignment: .trailing)
                                }
                            }
                            HStack {
                                Text("Forehand \(s.forehands)").font(.rounded(12)).foregroundColor(Theme.textDim)
                                Spacer()
                                Text("Backhand \(s.backhands)").font(.rounded(12)).foregroundColor(Theme.textDim)
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        StatTile(value: "\(s.smashWinners)", label: "Smash winners", color: Theme.red)
                        StatTile(value: "\(s.perfectHits)", label: "Perfect hits", color: Theme.gold)
                        StatTile(value: "\(p.totalDrillStars)", label: "Drill stars", color: Theme.green)
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
    }
}
