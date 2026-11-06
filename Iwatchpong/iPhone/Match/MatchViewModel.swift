import SwiftUI
import Combine
import PongCore

/// Runs one match or training drill: owns the engine, steps it every frame,
/// and turns `MatchEvent`s into banners, popups, sounds and haptics.
final class MatchViewModel: ObservableObject {
    enum Kind {
        case match(MatchSetup)
        case drill(DrillKind)
    }

    enum PauseReason {
        case user
        case controllerLost
    }

    // MARK: Published
    @Published private(set) var snapshot: MatchSnapshot
    @Published private(set) var banners: [Banner] = []
    @Published private(set) var popups: [ShotPopup] = []
    @Published private(set) var bounceMarks: [BounceMark] = []
    @Published private(set) var trail: [Vec3] = []
    @Published private(set) var ballAngle = 0.0
    @Published private(set) var pauseReason: PauseReason?
    @Published private(set) var lastShot: ShotReport?
    @Published var showIntro: Bool

    // MARK: Configuration
    let kind: Kind
    let opponent: OpponentProfile
    let drillSpec: DrillSpec?
    let rightHanded: Bool
    let showGuide: Bool

    private(set) var engine: MatchEngine
    private unowned let env: AppEnvironment
    private let driver = DisplayLinkDriver()
    private var finished = false
    private var finishWork: DispatchWorkItem?
    private var started = false
    private var lastSentSummary: MatchSummary?
    private var lastSendTime = 0.0
    private var trailTimer = 0.0

    var isDrill: Bool { drillSpec != nil }
    var isPaused: Bool { pauseReason != nil }

    var setup: MatchSetup? {
        if case .match(let s) = kind { return s }
        return nil
    }

    init(env: AppEnvironment, kind: Kind) {
        self.env = env
        self.kind = kind
        let profile = env.profile
        rightHanded = profile.settings.rightHanded
        showGuide = profile.settings.showTimingGuide
        let seed = UInt64.random(in: 1...UInt64.max)
        switch kind {
        case .match(let setup):
            let opp = env.opponent(id: setup.opponent, tier: setup.tier)
            opponent = opp
            drillSpec = nil
            engine = MatchEngine(opponent: opp, upgrades: profile.upgrades,
                                 config: setup.format.config(firstServer: .human), mode: .match, seed: seed)
            showIntro = false
        case .drill(let drillKind):
            let spec = DrillSpec.spec(for: drillKind)
            let opp = env.opponent(id: 0, tier: 0)
            opponent = opp
            drillSpec = spec
            engine = MatchEngine(opponent: opp, upgrades: profile.upgrades, config: MatchConfig(),
                                 mode: .drill(spec), seed: seed)
            showIntro = true
        }
        engine.rightHanded = rightHanded
        snapshot = engine.snapshot
    }

    deinit { driver.stop() }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        env.controller.onPaddle = { [weak self] event, age in
            DispatchQueue.main.async { self?.receive(event, age: age) }
        }
        env.controller.onLinkLost = { [weak self] in
            DispatchQueue.main.async {
                guard let self, !self.env.controller.simulatorEnabled else { return }
                self.pause(.controllerLost)
            }
        }
        env.controller.setMode(.play)
        driver.onFrame = { [weak self] dt in self?.frame(dt) }
        driver.start()
        engine.start()
        engine.isPaused = showIntro
        publish()
        sendWatchState(force: true)
    }

    func stop() {
        guard started else { return }
        driver.stop()
        env.controller.onPaddle = nil
        env.controller.onLinkLost = nil
        env.controller.setMode(.off)
        env.controller.sendState(MatchSummary(phase: .idle))
        started = false
    }

    func dismissIntro() {
        showIntro = false
        engine.isPaused = isPaused
    }

    // MARK: Pause

    func pause(_ reason: PauseReason = .user) {
        guard pauseReason == nil, !finished else { return }
        pauseReason = reason
        engine.isPaused = true
    }

    func resume() {
        guard pauseReason != nil else { return }
        if pauseReason == .controllerLost, !env.controller.hasController { return }
        pauseReason = nil
        engine.isPaused = showIntro
    }

    // MARK: Frame loop

    private func frame(_ dt: Double) {
        guard started else { return }
        if pauseReason == nil, !showIntro {
            if !env.controller.hasController {
                pause(.controllerLost)
            } else {
                engine.update(dt)
                for e in engine.drainEvents() { handle(e) }
                updateBall(dt)
            }
        }
        prune()
        publish()
        sendWatchState(force: false)
        checkFinished()
    }

    private func publish() {
        snapshot = engine.snapshot
    }

    private func updateBall(_ dt: Double) {
        let ball = snapshot.ball
        ballAngle += ball.spin.magnitude * 0.25 * dt
        if ballAngle > .pi * 2 { ballAngle -= .pi * 2 }
        trailTimer += dt
        if engine.snapshot.ballVisible {
            if trailTimer >= 0.016 {
                trailTimer = 0
                trail.append(engine.snapshot.ball.position)
                if trail.count > 14 { trail.removeFirst(trail.count - 14) }
            }
        } else if !trail.isEmpty {
            trail.removeAll()
        }
    }

    private func prune() {
        let now = Date()
        if banners.contains(where: { now.timeIntervalSince($0.created) > $0.duration }) {
            banners.removeAll { now.timeIntervalSince($0.created) > $0.duration }
        }
        if popups.contains(where: { now.timeIntervalSince($0.created) > $0.duration }) {
            popups.removeAll { now.timeIntervalSince($0.created) > $0.duration }
        }
        if bounceMarks.contains(where: { now.timeIntervalSince($0.created) > $0.duration }) {
            bounceMarks.removeAll { now.timeIntervalSince($0.created) > $0.duration }
        }
    }

    // MARK: Input

    private func receive(_ event: PaddleEvent, age: Double) {
        guard started, pauseReason == nil, !showIntro else { return }
        engine.handle(event, age: age)
        // Drain immediately so feedback does not wait for the next frame.
        for e in engine.drainEvents() { handle(e) }
        publish()
    }

    // MARK: Events

    private func handle(_ event: MatchEvent) {
        if let cue = event.hapticCue {
            env.haptics.play(cue)
            env.controller.sendHaptic(cue)
        }
        let now = Date()
        switch event {
        case .serveReady(let p):
            if p == .human {
                banner("YOUR SERVE", sub: "Flick up to toss, then swing", color: Theme.gold, size: 40, duration: 1.8)
            } else if !isDrill {
                banner("\(opponent.name.uppercased()) SERVES", color: .white, size: 30, duration: 1.4)
            }
            env.sound.play(.tick, volume: 0.5)

        case .tossStarted:
            env.sound.play(.toss)

        case .tossMissed:
            popup("TOSS MISSED", color: Theme.orange, x: 0.5, y: 0.66, size: 22)

        case .shot(let s):
            lastShot = s
            shotFeedback(s)

        case .whiff(let reason):
            env.sound.play(.swing, volume: 0.7)
            if let text = whiffText(reason) {
                popup(text, color: Theme.orange, x: 0.5, y: 0.72, size: 20)
            }

        case .bounce(_, let position, _):
            bounceMarks.append(BounceMark(position: position, created: now))
            env.sound.play(.bounce, volume: 0.6)

        case .netTouch(let kind):
            env.sound.play(.net)
            popup(kind == .clip ? "NET CORD!" : "NET", color: Theme.blue, x: 0.5, y: 0.45, size: 22)

        case .ballOnYourSide:
            env.sound.play(.cue, volume: 0.6)

        case .letServe:
            banner("LET", sub: "Net cord on serve. Serve again", color: Theme.blue, size: 40, duration: 1.4)

        case .point(let info):
            if isDrill { break }
            let mine = info.winner == .human
            env.sound.play(mine ? .pointWon : .pointLost, volume: 0.8)
            banner(info.reason.title, sub: mine ? "POINT YOU" : "POINT \(opponent.name.uppercased())",
                   color: mine ? Theme.green : Theme.red, size: 36, duration: 1.4)

        case .serverChanged:
            break

        case .gameWon(let winner, let h, let o):
            env.sound.play(.gameWon)
            banner(winner == .human ? "GAME YOU" : "GAME \(opponent.name.uppercased())", sub: "\(h) - \(o)",
                   color: winner == .human ? Theme.gold : Theme.red, size: 44, duration: 2.6)

        case .matchWon(let winner):
            env.sound.play(winner == .human ? .matchWon : .matchLost)
            banner(winner == .human ? "MATCH WON" : "MATCH LOST", color: winner == .human ? Theme.gold : Theme.red,
                   size: 50, duration: 3.0)

        case .rallyMilestone(let n):
            popup("RALLY \(n)", color: Theme.gold, x: 0.5, y: 0.2, size: 24)

        case .drill(let outcome, _, _):
            switch outcome {
            case .success:
                env.sound.play(.pointWon, volume: 0.7)
                popup("NICE!", color: Theme.green, x: 0.5, y: 0.5, size: 34)
            case .wrongStroke:
                env.sound.play(.pointLost, volume: 0.6)
                popup("WRONG STROKE", color: Theme.orange, x: 0.5, y: 0.5, size: 26)
            case .missed:
                env.sound.play(.pointLost, volume: 0.6)
                popup("MISSED", color: Theme.red, x: 0.5, y: 0.5, size: 30)
            case .netOrOut:
                env.sound.play(.pointLost, volume: 0.6)
                popup("NET / OUT", color: Theme.red, x: 0.5, y: 0.5, size: 28)
            }

        case .drillComplete:
            env.sound.play(.gameWon)
        }
    }

    private func shotFeedback(_ s: ShotReport) {
        switch s.stroke {
        case .smash:
            env.sound.play(.smash)
        case .topspin, .flick:
            env.sound.play(.spinBrush)
            env.sound.play(.paddle, volume: 0.6)
        default:
            env.sound.play(.paddle, volume: s.stroke == .push || s.stroke == .drop ? 0.55 : 0.9)
        }
        let human = s.hitter == .human
        let y: CGFloat = human ? 0.74 : 0.30
        var label = s.stroke.displayName
        if s.side != .either, human { label = "\(s.side.displayName) \(label)" }
        if s.isServe { label = "SERVE \u{00B7} \(label)" }
        popup("\(label)  \(Int(s.speedKmh.rounded())) km/h", color: s.stroke.tint, x: 0.5, y: y, size: human ? 20 : 17)
        if human {
            var extras: [String] = [s.timing.title]
            if s.stretched { extras.append("STRETCHED") }
            if s.wrongSide { extras.append("WRONG SIDE") }
            popup(extras.joined(separator: " \u{00B7} "), color: s.timing.tint, x: 0.5, y: 0.80, size: 24)
        }
    }

    private func whiffText(_ r: WhiffReason) -> String? {
        switch r {
        case .noBall: return "NO BALL YET"
        case .tooEarly: return "TOO EARLY"
        case .tooLate: return "TOO LATE"
        case .alreadyHit: return nil
        case .needToss: return "FLICK UP TO TOSS FIRST"
        case .notInPlay: return nil
        case .outOfReach: return "OUT OF REACH"
        }
    }

    private func banner(_ text: String, sub: String? = nil, color: Color, size: CGFloat, duration: Double) {
        banners = [Banner(text: text, subtitle: sub, color: color, size: size, created: Date(), duration: duration)]
    }

    private func popup(_ text: String, color: Color, x: CGFloat, y: CGFloat, size: CGFloat) {
        guard !text.isEmpty else { return }
        popups.append(ShotPopup(text: text, color: color, x: x, y: y, size: size, created: Date()))
        if popups.count > 5 { popups.removeFirst(popups.count - 5) }
    }

    // MARK: Watch mirror

    private func sendWatchState(force: Bool) {
        let s = snapshot
        let phase: WatchPhase
        switch s.phase {
        case .notStarted: phase = .idle
        case .serveReady: phase = .serveReady
        case .tossing: phase = .tossing
        case .rally: phase = .rally
        case .pointOver: phase = .pointOver
        case .gameOver: phase = .gameOver
        case .matchOver, .drillOver: phase = .matchOver
        }
        let summary = MatchSummary(phase: phase, humanPoints: isDrill ? s.drillSuccesses : s.humanPoints,
                                   opponentPoints: isDrill ? s.drillAttempts : s.opponentPoints,
                                   humanGames: s.humanGames, opponentGames: s.opponentGames,
                                   humanServes: s.server == .human, rally: s.rally)
        let now = Date().timeIntervalSince1970
        var changed = true
        if let last = lastSentSummary {
            changed = last.phase != summary.phase || last.humanPoints != summary.humanPoints
                || last.opponentPoints != summary.opponentPoints || last.humanGames != summary.humanGames
                || last.opponentGames != summary.opponentGames || last.humanServes != summary.humanServes
                || (last.rally != summary.rally && now - lastSendTime > 0.5)
        }
        guard force || changed else { return }
        lastSentSummary = summary
        lastSendTime = now
        env.controller.sendState(summary)
    }

    // MARK: Finish

    private func checkFinished() {
        guard !finished else { return }
        switch snapshot.phase {
        case .matchOver:
            guard let outcome = engine.outcome, let setup else { return }
            finished = true
            schedule(after: 2.6) { [weak self] in
                guard let self else { return }
                self.env.finishMatch(outcome, opponent: self.opponent, setup: setup)
                self.stop()
                self.env.router.replaceTop(with: .matchResult)
            }
        case .drillOver:
            guard case .drill(let k) = kind else { return }
            finished = true
            let successes = snapshot.drillSuccesses
            let attempts = snapshot.drillAttempts
            schedule(after: 1.6) { [weak self] in
                guard let self else { return }
                self.env.finishDrill(kind: k, successes: successes, attempts: attempts)
                self.stop()
                self.env.router.replaceTop(with: .drillResult)
            }
        default:
            break
        }
    }

    /// Runs the end-of-match navigation later; cancelled by `quit()` / `restart()`.
    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        finishWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.finished, self.started else { return }
            work()
        }
        finishWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Leave the match without recording a result.
    func quit() {
        finishWork?.cancel()
        finishWork = nil
        finished = true
        stop()
        env.router.pop()
    }

    /// Restart the same match or drill from scratch.
    func restart() {
        finishWork?.cancel()
        finishWork = nil
        stop()
        finished = false
        banners = []
        popups = []
        bounceMarks = []
        trail = []
        pauseReason = nil
        lastSentSummary = nil
        let seed = UInt64.random(in: 1...UInt64.max)
        let profile = env.profile
        switch kind {
        case .match(let setup):
            engine = MatchEngine(opponent: opponent, upgrades: profile.upgrades,
                                 config: setup.format.config(firstServer: .human), mode: .match, seed: seed)
        case .drill:
            engine = MatchEngine(opponent: opponent, upgrades: profile.upgrades, config: MatchConfig(),
                                 mode: .drill(drillSpec!), seed: seed)
            showIntro = false
        }
        engine.rightHanded = rightHanded
        publish()
        start()
    }
}
