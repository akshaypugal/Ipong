import SwiftUI
import PongCore

/// The Watch UI is deliberately tiny: it is your paddle, not the game screen.
///
///     WRISTPONG
///     ● CONNECTED
///     7 - 5     (your serve)
struct WatchContentView: View {
    @ObservedObject private var model = WatchModel.shared

    var body: some View {
        Group {
            if let c = model.calibration, c.step != .idle {
                CalibrationWatchView(progress: c)
            } else if model.mode == .play, model.summary.phase != .idle {
                MatchWatchView(model: model)
            } else if model.mode == .practice {
                PracticeWatchView(model: model)
            } else {
                IdleWatchView(model: model)
            }
        }
        .animation(.easeOut(duration: 0.15), value: model.mode)
    }
}

private let sunset = LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.34), Color.orange, Color.red],
                                    startPoint: .top, endPoint: .bottom)

struct ConnectionDot: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(connected ? Color.green : Color.red).frame(width: 8, height: 8)
            Text(connected ? "CONNECTED" : "NOT CONNECTED")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(connected ? .green : .red)
        }
    }
}

// MARK: - Idle

struct IdleWatchView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(spacing: 6) {
            Text("WRISTPONG")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(sunset)
            ConnectionDot(connected: model.connected)
            Text("READY")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            if !model.motionAvailable {
                Text("No motion sensors").font(.system(size: 11)).foregroundColor(.orange)
            } else if !model.connected {
                Text("Open WristPong on your iPhone").font(.system(size: 11)).foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            Button("PRACTICE") { model.setMode(.practice) }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .tint(.red)
                .disabled(!model.motionAvailable)
        }
    }
}

// MARK: - Match

struct MatchWatchView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        let s = model.summary
        VStack(spacing: 4) {
            Text(headline(s))
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundColor(.yellow)
            HStack(spacing: 10) {
                Text("\(s.humanPoints)").foregroundColor(.cyan)
                Text("-").foregroundColor(.gray)
                Text("\(s.opponentPoints)").foregroundColor(.red)
            }
            .font(.system(size: 44, weight: .heavy, design: .rounded))
            .monospacedDigit()
            Text("GAMES \(s.humanGames) - \(s.opponentGames)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.gray)
            if s.rally >= 3 {
                Text("RALLY \(s.rally)")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(sunset)
            }
            ConnectionDot(connected: model.connected)
        }
    }

    private func headline(_ s: MatchSummary) -> String {
        switch s.phase {
        case .serveReady: return s.humanServes ? "YOUR SERVE" : "THEY SERVE"
        case .tossing: return "SWING!"
        case .rally: return "RALLY"
        case .pointOver: return "POINT"
        case .gameOver: return "GAME OVER"
        case .matchOver: return "MATCH OVER"
        case .idle: return ""
        }
    }
}

// MARK: - Practice

/// Shows what the Watch recognises, without needing the iPhone: handy for
/// feeling out the strokes before a match.
struct PracticeWatchView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        VStack(spacing: 4) {
            Text("PRACTICE").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundColor(.yellow)
            Text(model.lastGesture.replacingOccurrences(of: "_", with: " "))
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(sunset)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text("\(Int(model.lastConfidence * 100))% \u{00B7} \(model.gestureCount) detected")
                .font(.system(size: 12, design: .rounded))
                .foregroundColor(.gray)
            ProgressView(value: min(1, model.liveMagnitude / 6))
                .tint(.orange)
            Button("STOP") { model.setMode(.off) }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tint(.red)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Calibration

struct CalibrationWatchView: View {
    let progress: CalibrationProgress

    private var title: String {
        switch progress.step {
        case .neutral: return "KEEP STILL"
        case .forehand: return "FOREHAND"
        case .backhand: return "BACKHAND"
        case .done: return "CALIBRATED"
        case .failed: return "TRY AGAIN"
        case .idle: return ""
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(sunset)
            if progress.step == .neutral {
                Text("\(progress.secondsLeft)")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            } else if progress.step == .forehand || progress.step == .backhand {
                Text("\u{1F3D3}").font(.system(size: 44))
            } else if progress.step == .done {
                Text("\u{2705}").font(.system(size: 44))
            }
            Text(progress.message)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 4)
    }
}
