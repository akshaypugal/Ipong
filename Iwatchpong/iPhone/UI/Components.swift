import SwiftUI
import PongCore

// MARK: - Buttons

struct BigButtonStyle: ButtonStyle {
    var colors: [Color] = [Theme.red, Theme.redDark]
    var height: CGFloat = 64

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.heavy(22))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: (colors.first ?? .red).opacity(0.45), radius: configuration.isPressed ? 2 : 10, y: configuration.isPressed ? 1 : 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SmallButtonStyle: ButtonStyle {
    var tint: Color = Theme.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(15))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(tint.opacity(configuration.isPressed ? 0.6 : 0.9))
            .clipShape(Capsule())
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Theme.cardStroke, lineWidth: 1)
            )
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String?
    var onBack: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.card)
                        .clipShape(Circle())
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.heavy(28)).foregroundColor(.white)
                if let subtitle {
                    Text(subtitle).font(.rounded(14)).foregroundColor(Theme.textDim)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Bars

/// Horizontal progress bar with a glossy fill.
struct BarView: View {
    var fraction: Double
    var colors: [Color]
    var height: CGFloat = 16
    var reversed = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: reversed ? .trailing : .leading) {
                Capsule().fill(Color.black.opacity(0.45))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    .frame(width: max(height * 0.6, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
                    .opacity(fraction <= 0.001 ? 0 : 1)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.22))
                            .frame(height: height * 0.35)
                            .padding(.horizontal, 5)
                            .offset(y: -height * 0.2),
                        alignment: .top
                    )
            }
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .frame(height: height)
    }
}

/// Label + bar, used for stamina / special / upgrade levels.
struct LabeledBar: View {
    let title: String
    var valueText: String?
    var fraction: Double
    var colors: [Color]
    var height: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.heavy(11)).foregroundColor(Theme.textDim)
                Spacer()
                if let valueText {
                    Text(valueText).font(.heavy(11)).foregroundColor(.white)
                }
            }
            BarView(fraction: fraction, colors: colors, height: height)
        }
    }
}

/// Segmented level meter (e.g. upgrade levels).
struct LevelMeter: View {
    let level: Int
    let maxLevel: Int
    var color: Color = Theme.gold

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxLevel, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i < level ? color : Color.white.opacity(0.14))
                    .frame(height: 10)
            }
        }
    }
}

// MARK: - Status

/// "WATCH CONNECTED" / "WATCH DISCONNECTED" / "SIMULATED CONTROLLER".
struct ConnectionBadge: View {
    @EnvironmentObject var controller: PaddleController

    var body: some View {
        let connected = controller.linkState.isConnected
        let simulated = controller.simulatorEnabled && !connected
        let color: Color = connected ? Theme.green : (simulated ? Theme.gold : Theme.red)
        let text = connected ? "WATCH CONNECTED" : (simulated ? "SIMULATED CONTROLLER" : "WATCH DISCONNECTED")
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.heavy(11)).foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var color: Color = .white

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.heavy(24)).foregroundColor(color).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.rounded(11)).foregroundColor(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Level badge with XP progress.
struct LevelBadge: View {
    let profile: PongProfile

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.fire).frame(width: 52, height: 52)
                Text("\(profile.level)").font(.heavy(24)).foregroundColor(.black.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("LEVEL \(profile.level)").font(.heavy(15)).foregroundColor(.white)
                    Text(profile.rank.title).font(.heavy(11)).foregroundColor(Theme.gold)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.gold.opacity(0.15)).clipShape(Capsule())
                }
                BarView(fraction: profile.xpFraction, colors: [Theme.blue, Color(hex: "7AB0FF")], height: 10)
                Text("\(profile.xp) / \(profile.xpToNextLevel) XP").font(.rounded(11)).foregroundColor(Theme.textDim)
            }
        }
    }
}

struct CoinLabel: View {
    let coins: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("🪙")
            Text("\(coins)").font(.heavy(16)).foregroundColor(Theme.gold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
        .clipShape(Capsule())
    }
}
