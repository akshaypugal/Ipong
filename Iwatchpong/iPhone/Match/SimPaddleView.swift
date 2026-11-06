import SwiftUI
import PongCore

/// Developer Controller Mode: one button per stroke, producing exactly the events the
/// Watch would. Hardware keyboard shortcuts work in the Simulator.
struct SimPaddleView: View {
    @EnvironmentObject var controller: PaddleController

    private let rows: [[SimulatedInput]] = [
        [.forehandDrive, .backhandDrive, .forehandTopspin, .backhandTopspin],
        [.chop, .push, .block, .drop],
        [.smash, .lob, .flickLeft, .flickRight]
    ]

    var body: some View {
        VStack(spacing: 8) {
            Button {
                controller.simulate(.toss)
            } label: {
                Text("TOSS  (space)")
                    .font(.heavy(15))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Theme.gold)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .keyboardShortcut(KeyEquivalent(SimulatedInput.toss.shortcutKey), modifiers: [])

            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r], id: \.self) { input in
                        key(input)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func key(_ input: SimulatedInput) -> some View {
        Button {
            controller.simulate(input)
        } label: {
            VStack(spacing: 2) {
                Text(input.title).font(.heavy(12)).minimumScaleFactor(0.7).lineLimit(1)
                Text(String(input.shortcutKey).uppercased()).font(.mono(9)).opacity(0.6)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(tint(input).opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .keyboardShortcut(KeyEquivalent(input.shortcutKey), modifiers: [])
    }

    private func tint(_ input: SimulatedInput) -> Color {
        switch input {
        case .forehandDrive, .backhandDrive: return Color(hex: "4A5368")
        case .forehandTopspin, .backhandTopspin: return Color(hex: "C2561C")
        case .chop, .push: return Color(hex: "2B5FBF")
        case .block, .drop: return Color(hex: "5F5A9E")
        case .smash: return Color(hex: "B3262A")
        case .lob: return Color(hex: "1F8F5B")
        case .flickLeft, .flickRight: return Color(hex: "B0399A")
        case .toss: return Theme.gold
        }
    }
}
