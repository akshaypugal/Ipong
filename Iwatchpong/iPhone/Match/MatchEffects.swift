import SwiftUI
import PongCore

/// Short-lived visual effects. Each carries its creation time so views can animate
/// them from `TimelineView` without the view model publishing every frame.

struct Banner: Identifiable {
    let id = UUID()
    let text: String
    var subtitle: String?
    let color: Color
    let size: CGFloat
    let created: Date
    let duration: Double

    func progress(at now: Date) -> Double {
        min(1, max(0, now.timeIntervalSince(created) / duration))
    }
}

/// Small floating label ("TOPSPIN 62 km/h", "TOO LATE").
struct ShotPopup: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
    /// Screen anchor, 0...1 across and down.
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let created: Date
    let duration = 1.1
}

/// A ring that spreads from where the ball hit the table.
struct BounceMark: Identifiable {
    let id = UUID()
    let position: Vec3
    let created: Date
    let duration = 0.55
}

func easeOut(_ t: Double) -> Double { 1 - pow(1 - min(max(t, 0), 1), 3) }

func easeInOut(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

extension StrokeKind {
    /// Colour used in feedback labels.
    var tint: Color {
        switch self {
        case .drive: return Color(hex: "FFFFFF")
        case .topspin: return Theme.orange
        case .chop: return Theme.blue
        case .push: return Color(hex: "7AB0FF")
        case .smash: return Theme.red
        case .lob: return Theme.green
        case .block: return Color(hex: "B0B8C8")
        case .drop: return Color(hex: "C7B8FF")
        case .flick: return Color(hex: "FF7AD9")
        }
    }
}

extension TimingLabel {
    var tint: Color {
        switch self {
        case .perfect: return Theme.gold
        case .good: return Theme.green
        case .early: return Theme.blue
        case .late: return Theme.orange
        }
    }
}
