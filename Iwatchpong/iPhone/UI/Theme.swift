import SwiftUI

extension Color {
    /// `Color(hex: "E5383B")`
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

enum Theme {
    static let bgTop = Color(hex: "0B0D14")
    static let bgBottom = Color(hex: "1B1030")
    static let card = Color.white.opacity(0.07)
    static let cardStroke = Color.white.opacity(0.12)
    static let red = Color(hex: "E5383B")
    static let redDark = Color(hex: "9B1D20")
    static let gold = Color(hex: "FFC857")
    static let blue = Color(hex: "3A86FF")
    static let green = Color(hex: "2EC27E")
    static let orange = Color(hex: "FF8A3D")
    static let textDim = Color.white.opacity(0.62)

    static var background: LinearGradient {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .top, endPoint: .bottom)
    }

    static var fire: LinearGradient {
        LinearGradient(colors: [gold, orange, red], startPoint: .top, endPoint: .bottom)
    }
}

extension Font {
    /// Chunky rounded display font used everywhere in the UI.
    static func heavy(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    static func rounded(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

/// Full-screen dark background used by every non-fight screen.
struct ScreenBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            Circle()
                .fill(Theme.red.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: -140, y: -300)
            Circle()
                .fill(Theme.blue.opacity(0.14))
                .frame(width: 380, height: 380)
                .blur(radius: 90)
                .offset(x: 160, y: 320)
        }
        .ignoresSafeArea()
    }
}
