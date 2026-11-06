import SwiftUI
import PongCore

/// Guided setup: connect the Watch, calibrate the wrist, then try a few strokes.
struct CalibrationFlowView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var controller: PaddleController
    var onFinish: () -> Void

    private enum Stage { case intro, calibrating, test }
    @State private var stage: Stage = .intro
    @State private var testLog: [String] = []

    var body: some View {
        ZStack {
            ScreenBackground()
            VStack(spacing: 18) {
                switch stage {
                case .intro: intro
                case .calibrating: calibrating
                case .test: test
                }
            }
            .padding(24)
        }
        .onDisappear {
            controller.onPaddle = nil
            controller.setMode(.off)
        }
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🏓").font(.system(size: 64))
            Text("SET UP YOUR PADDLE").font(.heavy(26)).foregroundColor(.white)
            Text("Your Apple Watch is the paddle. Wear it on the hand you play with, open WristPong on the Watch, then calibrate: hold still, then swing a forehand and a backhand.")
                .font(.rounded(14)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
            ConnectionBadge()
            Text(controller.linkState.detail).font(.rounded(12)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
            Spacer()
            if controller.linkState.isConnected {
                Button("START CALIBRATION") {
                    controller.startCalibration()
                    stage = .calibrating
                }.buttonStyle(BigButtonStyle())
            } else {
                Button("Open WristPong on my Watch") { WatchLauncher.launch() }
                    .buttonStyle(SmallButtonStyle(tint: Theme.green))
            }
            if controller.simulatorEnabled || !controller.linkState.isConnected {
                Button("Skip: use on-screen controller") {
                    env.updateSettings {
                        $0.simulatedController = true
                        $0.developerMode = true
                    }
                    onFinish()
                }.buttonStyle(SmallButtonStyle(tint: .gray))
            }
            Button("Not now") { onFinish() }
                .font(.rounded(13)).foregroundColor(Theme.textDim)
        }
    }

    // MARK: Calibrating

    @ViewBuilder private var calibrating: some View {
        let p = controller.calibrationProgress
        VStack(spacing: 18) {
            Spacer()
            Text(stepTitle(p?.step ?? .idle)).font(.heavy(26)).foregroundColor(Theme.gold).multilineTextAlignment(.center)
            Text(p?.message ?? "Waiting for the Watch...").font(.rounded(16)).foregroundColor(.white).multilineTextAlignment(.center)
            if let p, p.secondsLeft > 0 {
                Text("\(p.secondsLeft)").font(.heavy(64)).foregroundColor(.white)
            }
            BarView(fraction: p?.progress ?? 0, colors: [Theme.blue, Color(hex: "7AB0FF")], height: 14)
            HStack(spacing: 8) {
                stepDot("HOLD STILL", .neutral, p)
                stepDot("FOREHAND", .forehand, p)
                stepDot("BACKHAND", .backhand, p)
            }
            Spacer()
            if p?.step == .done {
                Button("TRY IT OUT") {
                    stage = .test
                    startTest()
                }.buttonStyle(BigButtonStyle())
            } else if p?.step == .failed {
                Button("TRY AGAIN") { controller.startCalibration() }.buttonStyle(BigButtonStyle())
            }
            Button("Cancel") {
                controller.cancelCalibration()
                onFinish()
            }.font(.rounded(13)).foregroundColor(Theme.textDim)
        }
    }

    private func stepTitle(_ s: CalibrationStep) -> String {
        switch s {
        case .idle: return "GET READY"
        case .neutral: return "HOLD STILL"
        case .forehand: return "FOREHAND SWING"
        case .backhand: return "BACKHAND SWING"
        case .done: return "CALIBRATED \u{2713}"
        case .failed: return "TRY AGAIN"
        }
    }

    private func stepDot(_ title: String, _ step: CalibrationStep, _ p: CalibrationProgress?) -> some View {
        let order: [CalibrationStep] = [.neutral, .forehand, .backhand, .done]
        let cur = order.firstIndex(of: p?.step ?? .idle) ?? -1
        let mine = order.firstIndex(of: step) ?? 0
        let color: Color = cur > mine ? Theme.green : (cur == mine ? Theme.gold : Color.white.opacity(0.2))
        return Text(title).font(.heavy(10)).foregroundColor(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(color.opacity(0.4)).clipShape(Capsule())
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }

    // MARK: Test

    private var test: some View {
        VStack(spacing: 16) {
            Text("TRY SOME STROKES").font(.heavy(26)).foregroundColor(.white)
            Text("Swing like you would at the table. Each stroke shows up here as the game sees it.")
                .font(.rounded(14)).foregroundColor(Theme.textDim).multilineTextAlignment(.center)
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST STROKE").font(.heavy(12)).foregroundColor(Theme.textDim)
                    Text(controller.lastGesture).font(.heavy(30)).foregroundColor(Theme.gold)
                    Text("confidence \(Int(controller.lastConfidence * 100))%  \u{00B7}  power \(String(format: "%.2f", controller.lastPower))")
                        .font(.mono(12)).foregroundColor(.white)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(testLog.indices, id: \.self) { i in
                        Text(testLog[i]).font(.mono(12)).foregroundColor(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if controller.simulatorEnabled { SimPaddleView() }
            Button("DONE") {
                var p = env.profile
                p.hasOnboarded = true
                env.profile = p
                onFinish()
            }.buttonStyle(BigButtonStyle())
        }
    }

    private func startTest() {
        controller.setMode(.practice)
        controller.onPaddle = { event, _ in
            DispatchQueue.main.async {
                testLog.insert(event.code, at: 0)
                if testLog.count > 30 { testLog.removeLast() }
            }
        }
    }
}

/// Full-screen first-run wrapper.
struct OnboardingView: View {
    @EnvironmentObject var env: AppEnvironment

    var body: some View {
        CalibrationFlowView {
            var p = env.profile
            p.hasOnboarded = true
            env.profile = p
        }
    }
}
