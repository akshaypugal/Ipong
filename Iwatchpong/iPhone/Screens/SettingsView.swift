import SwiftUI
import PongCore

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var controller: PaddleController
    @State private var showCalibration = false
    @State private var confirmReset = false

    var body: some View {
        let s = env.profile.settings
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "SETTINGS") { env.router.pop() }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("APPLE WATCH").font(.heavy(13)).foregroundColor(Theme.textDim)
                            ConnectionBadge()
                            Text(controller.linkState.detail).font(.rounded(12)).foregroundColor(Theme.textDim)
                            HStack {
                                Text(env.profile.calibration.isCalibrated ? "Calibrated \u{2713}" : "Not calibrated")
                                    .font(.heavy(13))
                                    .foregroundColor(env.profile.calibration.isCalibrated ? Theme.green : Theme.orange)
                                Spacer()
                                Button("CALIBRATE") { showCalibration = true }.buttonStyle(SmallButtonStyle(tint: Theme.blue))
                            }
                            Button("Open WristPong on my Watch") { WatchLauncher.launch() }
                                .buttonStyle(SmallButtonStyle(tint: Theme.green))
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GAMEPLAY").font(.heavy(13)).foregroundColor(Theme.textDim)
                            toggle("Right-handed", s.rightHanded) { v in env.updateSettings { $0.rightHanded = v } }
                            toggle("Show timing guide", s.showTimingGuide) { v in env.updateSettings { $0.showTimingGuide = v } }
                            Picker("Format", selection: Binding(get: { s.matchFormat }, set: { v in env.updateSettings { $0.matchFormat = v } })) {
                                ForEach(MatchFormat.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 6)
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("FEEDBACK").font(.heavy(13)).foregroundColor(Theme.textDim)
                            toggle("Sound", s.soundEnabled) { v in env.updateSettings { $0.soundEnabled = v } }
                            toggle("iPhone haptics", s.hapticsEnabled) { v in env.updateSettings { $0.hapticsEnabled = v } }
                            toggle("Watch tick on swing", s.localWatchHaptics) { v in env.updateSettings { $0.localWatchHaptics = v } }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DEVELOPER").font(.heavy(13)).foregroundColor(Theme.textDim)
                            toggle("Developer mode (Debug screen)", s.developerMode) { v in env.updateSettings { $0.developerMode = v } }
                            toggle("Simulated controller (no Watch)", s.simulatedController) { v in env.updateSettings { $0.simulatedController = v } }
                            toggle("Show latency in match", s.showLatency) { v in env.updateSettings { $0.showLatency = v } }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TROUBLESHOOTING").font(.heavy(13)).foregroundColor(Theme.textDim)
                            Text("Watch not connecting? Open WristPong on the Watch and keep the wrist raised. Make sure both apps are installed (Watch app > My Watch). Swings misread? Recalibrate, wearing the Watch the way you will play.")
                                .font(.rounded(12)).foregroundColor(Theme.textDim)
                            Button("Reset progress") { confirmReset = true }
                                .buttonStyle(SmallButtonStyle(tint: Theme.redDark))
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showCalibration) {
            CalibrationFlowView(onFinish: { showCalibration = false })
                .environmentObject(env)
                .environmentObject(controller)
        }
        .confirmationDialog("Reset all progress? Settings and calibration are kept.", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset progress", role: .destructive) { env.resetProgress() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func toggle(_ title: String, _ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { value }, set: set)) {
            Text(title).font(.rounded(15)).foregroundColor(.white)
        }
        .tint(Theme.green)
    }
}

// MARK: - Debug

struct DebugView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var controller: PaddleController

    var body: some View {
        let cfg = env.profile.settings.swingConfig
        ZStack {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ScreenHeader(title: "DEBUG", subtitle: "Swing recognition and connection") { env.router.pop() }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            ConnectionBadge()
                            Group {
row("Link", controller.linkState.rawValue)
                            row("Watch mode", controller.watchMode.rawValue)
                            row("Last gesture", controller.lastGesture)
                            row("Confidence", String(format: "%.0f%%", controller.lastConfidence * 100))
                            row("Power", String(format: "%.2f", controller.lastPower))
                            row("Decision", controller.lastDecision)
                            row("Latency avg / p95 / max", String(format: "%.0f / %.0f / %.0f ms", controller.latency.average, controller.latency.p95, controller.latency.maximum))
                            row("Samples", "\(controller.latency.count)  lost \(controller.packetsLost)")
                            row("Accel g", vec(controller.rawAccel))
                            row("Gyro rad/s", vec(controller.rawGyro))
                            }
                            Toggle("Stream raw sensors", isOn: Binding(get: { controller.debugStreaming },
                                                                       set: { controller.setDebugStreaming($0) }))
                                .tint(Theme.green).font(.rounded(14)).foregroundColor(.white)
                            HStack {
                                Button("Practice mode") { controller.setMode(.practice) }.buttonStyle(SmallButtonStyle(tint: Theme.blue))
                                Button("Sensors off") { controller.setMode(.off) }.buttonStyle(SmallButtonStyle(tint: Theme.redDark))
                                Button("Clear") { controller.clearLog() }.buttonStyle(SmallButtonStyle(tint: .gray))
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("SWING THRESHOLDS").font(.heavy(13)).foregroundColor(Theme.textDim)
                                Spacer()
                                Button("Reset") { env.updateSettings { $0.swingConfig = .default } }
                                    .buttonStyle(SmallButtonStyle(tint: Theme.redDark))
                            }
                            Group {
slider("Start threshold (g)", \.startThreshold, 0.2...1.5, cfg)
                            slider("Drive min (g)", \.driveMin, 0.8...4, cfg)
                            slider("Smash min (g)", \.smashMin, 3...12, cfg)
                            slider("Block max (g)", \.blockMax, 1...4, cfg)
                            slider("Drop max (g)", \.dropMax, 0.8...3.5, cfg)
                            slider("Push max (g)", \.pushMax, 0.8...3.5, cfg)
                            }
                            Group {
                            slider("Flick gyro min (rad/s)", \.flickGyroMin, 4...16, cfg)
                            slider("Toss max peak (g)", \.tossMaxPeak, 1...6, cfg)
                            slider("Yaw side min (rad/s)", \.yawSideMin, 0.5...6, cfg)
                            slider("Topspin vertical frac", \.topspinVerticalFrac, 0...0.8, cfg)
                            slider("Chop vertical frac", \.chopVerticalFrac, -0.8...0, cfg)
                            slider("Confirm delay (s)", \.confirmDelay, 0.08...0.35, cfg)
                            slider("Cooldown (s)", \.cooldown, 0.15...0.8, cfg)
                            }
                        }
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EVENT LOG").font(.heavy(13)).foregroundColor(Theme.textDim)
                            if controller.eventLog.isEmpty {
                                Text("Nothing yet. Swing the Watch.").font(.rounded(12)).foregroundColor(Theme.textDim)
                            }
                            ForEach(controller.eventLog.prefix(40)) { e in
                                HStack {
                                    Text(timeString(e.time)).font(.mono(10)).foregroundColor(Theme.textDim)
                                    Text(e.text).font(.mono(12)).foregroundColor(.white)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear { controller.setMode(.practice) }
        .onDisappear {
            controller.setMode(.off)
            controller.setDebugStreaming(false)
        }
    }

    private var cfg: SwingConfig { env.profile.settings.swingConfig }

    private func slider(_ title: String, _ key: WritableKeyPath<SwingConfig, Double>, _ range: ClosedRange<Double>, _ cfg: SwingConfig) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.rounded(12)).foregroundColor(.white)
                Spacer()
                Text(String(format: "%.2f", cfg[keyPath: key])).font(.mono(12)).foregroundColor(Theme.gold)
            }
            Slider(value: Binding(get: { cfg[keyPath: key] },
                                  set: { v in env.updateSettings { $0.swingConfig[keyPath: key] = v } }),
                   in: range)
                .tint(Theme.orange)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.rounded(12)).foregroundColor(Theme.textDim)
            Spacer()
            Text(value).font(.mono(12)).foregroundColor(.white)
        }
    }

    private func vec(_ v: Vec3) -> String { String(format: "%.2f %.2f %.2f", v.x, v.y, v.z) }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: d)
    }
}
