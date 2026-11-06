import XCTest
@testable import PongCore

final class ProgressionTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    private func outcome(won: Bool, opponent: Int = 0, humanGames: Int? = nil, stats: MatchStats = MatchStats()) -> MatchOutcome {
        MatchOutcome(winner: won ? .human : .opponent, humanGames: humanGames ?? (won ? 2 : 0), opponentGames: won ? 0 : 2,
                     gameScores: [], stats: stats, duration: 300, opponentID: opponent)
    }

    private func goodStats() -> MatchStats {
        var s = MatchStats()
        s.aces = 3
        s.smashWinners = 2
        s.longestRally = 14
        s.perfectHits = 12
        s.pointsWon = 22
        s.smashes = 6
        s.topspins = 15
        s.serves = 12
        return s
    }

    // MARK: XP and rewards

    func testXPLevelsUp() {
        var p = PongProfile()
        XCTAssertEqual(p.addXP(PongProfile.xpNeeded(forLevel: 1)), 1)
        XCTAssertEqual(p.level, 2)
        XCTAssertGreaterThan(p.addXP(10_000), 3)
        XCTAssertTrue((0...1).contains(p.xpFraction))
        XCTAssertLessThan(PongProfile.xpNeeded(forLevel: 1), PongProfile.xpNeeded(forLevel: 2))
    }

    func testVictoryPaysXPAndCoins() {
        var p = PongProfile()
        let r = ProgressionService.apply(outcome: outcome(won: true, stats: goodStats()), opponent: OpponentProfile.roster[0],
                                         to: &p, now: date(2026, 11, 6), calendar: utc)
        XCTAssertTrue(r.won)
        XCTAssertGreaterThan(r.xp, 200)
        XCTAssertGreaterThan(r.coins, 80)
        XCTAssertEqual(p.coins, r.coins)
        XCTAssertEqual(p.totalXP, r.xp)
        XCTAssertEqual(r.lines.reduce(0) { $0 + $1.xp }, r.xp)
        XCTAssertTrue(r.lines.contains { $0.title.hasPrefix("Clean sweep") })
        XCTAssertEqual(p.matchesWon, 1)
        XCTAssertEqual(p.lifetime.aces, 3)
    }

    func testDefeatPaysLessButSomething() {
        var win = PongProfile(), loss = PongProfile()
        let w = ProgressionService.apply(outcome: outcome(won: true, stats: goodStats()), opponent: OpponentProfile.roster[0], to: &win, now: date(2026, 11, 6), calendar: utc)
        let l = ProgressionService.apply(outcome: outcome(won: false, stats: goodStats()), opponent: OpponentProfile.roster[0], to: &loss, now: date(2026, 11, 6), calendar: utc)
        XCTAssertGreaterThan(l.xp, 0)
        XCTAssertLessThan(l.xp, w.xp)
        XCTAssertLessThan(l.coins, w.coins)
        XCTAssertEqual(loss.matchesWon, 0)
    }

    func testHarderOpponentsPayMore() {
        var a = PongProfile(), b = PongProfile()
        let r0 = ProgressionService.apply(outcome: outcome(won: true, opponent: 0), opponent: OpponentProfile.roster[0], to: &a, now: date(2026, 11, 6), calendar: utc)
        let r5 = ProgressionService.apply(outcome: outcome(won: true, opponent: 5), opponent: OpponentProfile.roster[5], to: &b, now: date(2026, 11, 6), calendar: utc)
        XCTAssertGreaterThan(r5.xp, r0.xp * 2)
    }

    // MARK: Career

    func testBeatingTheCurrentOpponentUnlocksTheNext() {
        var p = PongProfile()
        XCTAssertEqual(p.rank, .rookie)
        XCTAssertTrue(p.isUnlocked(opponent: 0))
        XCTAssertFalse(p.isUnlocked(opponent: 1))
        let r = ProgressionService.apply(outcome: outcome(won: true), opponent: OpponentProfile.roster[0], to: &p, now: date(2026, 11, 6), calendar: utc)
        XCTAssertEqual(r.unlockedOpponent, 1)
        XCTAssertEqual(p.rank, .club)
        XCTAssertTrue(p.isUnlocked(opponent: 1))
    }

    func testLosingOrRematchingDoesNotAdvanceTheCareer() {
        var p = PongProfile()
        ProgressionService.apply(outcome: outcome(won: false), opponent: OpponentProfile.roster[0], to: &p, now: date(2026, 11, 6), calendar: utc)
        XCTAssertEqual(p.careerProgress, 0)
        p.careerProgress = 3
        let r = ProgressionService.apply(outcome: outcome(won: true, opponent: 0), opponent: OpponentProfile.roster[0], to: &p, now: date(2026, 11, 6), calendar: utc)
        XCTAssertNil(r.unlockedOpponent)
        XCTAssertEqual(p.careerProgress, 3)
    }

    func testBeatingTheDragonCompletesTheCareer() {
        var p = PongProfile()
        p.careerProgress = 5
        XCTAssertEqual(p.rank, .legend)
        let r = ProgressionService.apply(outcome: outcome(won: true, opponent: 5), opponent: OpponentProfile.roster[5], to: &p, now: date(2026, 11, 6), calendar: utc)
        XCTAssertTrue(r.careerCompleted)
        XCTAssertTrue(p.careerCleared)
        XCTAssertGreaterThanOrEqual(p.maxTier, 1)
        XCTAssertEqual(CareerRank.allCases.map { $0.title }, ["ROOKIE", "CLUB", "LEAGUE", "NATIONAL", "WORLD", "LEGEND"])
    }

    // MARK: Upgrades

    func testUpgradesCostAndEffects() {
        XCTAssertEqual(PlayerUpgrades.cost(fromLevel: 3), 100)
        var p = PongProfile()
        p.coins = 40
        XCTAssertTrue(ProgressionService.purchase(.power, profile: &p))
        XCTAssertEqual(p.upgrades.power, 1)
        XCTAssertEqual(p.coins, 0)
        XCTAssertFalse(ProgressionService.purchase(.spin, profile: &p))
        p.coins = 1_000_000
        for _ in 0..<30 { ProgressionService.purchase(.reflex, profile: &p) }
        XCTAssertEqual(p.upgrades.reflex, PlayerUpgrades.maxLevel)
        XCTAssertNil(p.upgrades.cost(for: .reflex))
        let max = PlayerUpgrades(power: 10, control: 10, spin: 10, reflex: 10)
        let base = PlayerUpgrades()
        XCTAssertGreaterThan(max.speedMultiplier, base.speedMultiplier)
        XCTAssertGreaterThan(max.spinMultiplier, base.spinMultiplier)
        XCTAssertLessThan(max.errorMultiplier, base.errorMultiplier)
        XCTAssertGreaterThan(max.timingWindowMultiplier, base.timingWindowMultiplier)
        XCTAssertGreaterThan(max.moveSpeed, base.moveSpeed)
        XCTAssertEqual(UpgradeStat.allCases.count, 4)
    }

    func testUpgradesMakeYouPlayBetter() {
        func quality(_ u: PlayerUpgrades) -> Double {
            let e = MatchEngine(opponent: flawlessOpponent(), upgrades: u, seed: 3)
            e.start()
            e.debugLaunch(ball: incomingBall(), hitter: .opponent)
            e.run(untilClock: e.snapshot.hint!.idealTime + 0.09)
            var pad = SimulatedPaddle(seed: 1, power: 0.6, jitter: 0)
            e.handle(pad.event(for: .forehandDrive))
            return shots(e.drainEvents()).first?.quality ?? 0
        }
        // A wider timing window forgives a late swing.
        XCTAssertGreaterThan(quality(PlayerUpgrades(reflex: 8)), quality(PlayerUpgrades()))
    }

    // MARK: Drills

    func testDrillRewardsAndStars() {
        var p = PongProfile()
        let spec = DrillSpec.spec(for: .push)
        let r1 = ProgressionService.applyDrill(kind: .push, successes: spec.starThresholds[1], attempts: 10, to: &p)
        XCTAssertEqual(r1.stars, 2)
        XCTAssertGreaterThan(r1.xp, 0)
        XCTAssertEqual(p.drillStars["push"], 2)
        let coins = p.coins
        // Repeating the same score only pays participation, not the star bonus again.
        let r2 = ProgressionService.applyDrill(kind: .push, successes: spec.starThresholds[1], attempts: 10, to: &p)
        XCTAssertLessThan(r2.xp, r1.xp)
        XCTAssertLessThan(p.coins - coins, r1.coins)
        // A better score raises the stars.
        let r3 = ProgressionService.applyDrill(kind: .push, successes: 10, attempts: 10, to: &p)
        XCTAssertEqual(r3.stars, 3)
        XCTAssertEqual(p.drillStars["push"], 3)
        XCTAssertEqual(p.drillBest["push"], 10)
        XCTAssertEqual(p.totalDrillStars, 3)
    }

    // MARK: Daily challenges

    func testDailyChallengesAreThreeDistinctAndDeterministic() {
        let a = DailyChallengeState.generate(for: date(2026, 11, 6), calendar: utc)
        XCTAssertEqual(a, DailyChallengeState.generate(for: date(2026, 11, 6), calendar: utc))
        XCTAssertEqual(a.challenges.count, 3)
        XCTAssertEqual(Set(a.challenges.map { $0.kind }).count, 3)
        XCTAssertEqual(a.dayKey, "2026-11-06")
        var sets = Set<[ChallengeKind]>()
        for d in 1...20 { sets.insert(DailyChallengeState.generate(for: date(2026, 11, d), calendar: utc).challenges.map { $0.kind }) }
        XCTAssertGreaterThan(sets.count, 3)
    }

    func testChallengesRefreshOnANewDayOnly() {
        var s = DailyChallengeState()
        XCTAssertTrue(s.refreshIfNeeded(now: date(2026, 11, 6), calendar: utc))
        s.challenges[0].progress = 2
        XCTAssertFalse(s.refreshIfNeeded(now: date(2026, 11, 6), calendar: utc))
        XCTAssertEqual(s.challenges[0].progress, 2)
        XCTAssertTrue(s.refreshIfNeeded(now: date(2026, 11, 7), calendar: utc))
        XCTAssertEqual(s.challenges[0].progress, 0)
    }

    func testChallengeProgressAndClaim() {
        var p = PongProfile()
        p.daily = DailyChallengeState(dayKey: "2026-11-06", challenges: [
            DailyChallenge(id: "a", kind: .smashes, target: 5),
            DailyChallenge(id: "b", kind: .aces, target: 3),
            DailyChallenge(id: "c", kind: .longRally, target: 20)
        ])
        let r = ProgressionService.apply(outcome: outcome(won: true, stats: goodStats()), opponent: OpponentProfile.roster[0],
                                         to: &p, now: date(2026, 11, 6), calendar: utc)
        XCTAssertEqual(Set(r.completedChallenges), ["a", "b"])
        XCTAssertEqual(p.daily.claimableCount, 2)
        let coins = p.coins, xp = p.totalXP
        let claim = ProgressionService.claimChallenge(id: "a", profile: &p)
        XCTAssertEqual(claim?.xp, 100)
        XCTAssertEqual(claim?.coins, 50)
        XCTAssertEqual(p.coins, coins + 50)
        XCTAssertEqual(p.totalXP, xp + 100)
        XCTAssertNil(ProgressionService.claimChallenge(id: "a", profile: &p), "cannot claim twice")
        XCTAssertNil(ProgressionService.claimChallenge(id: "c", profile: &p), "not finished")
    }

    func testLongestRallyChallengeTakesTheBestNotTheSum() {
        var s = DailyChallengeState(dayKey: "d", challenges: [DailyChallenge(id: "r", kind: .longRally, target: 30)])
        var stats = MatchStats()
        stats.longestRally = 12
        s.record(stats: stats, won: false)
        s.record(stats: stats, won: false)
        XCTAssertEqual(s.challenges[0].progress, 12)
    }

    func testEveryChallengeKindHasTitleAndTargets() {
        for k in ChallengeKind.allCases {
            XCTAssertFalse(k.targets.isEmpty)
            XCTAssertFalse(k.title(target: k.targets[0]).isEmpty)
        }
        XCTAssertEqual(ChallengeKind.smashes.title(target: 5), "Hit 5 Smashes")
        XCTAssertEqual(ChallengeKind.aces.title(target: 1), "Serve an Ace")
    }

    // MARK: Stats

    func testMatchStatsRecordAndMerge() {
        var a = MatchStats()
        a.record(stroke: .smash, side: .forehand)
        a.record(stroke: .chop, side: .backhand)
        a.record(stroke: .flick, side: .either)
        XCTAssertEqual(a.smashes, 1)
        XCTAssertEqual(a.chops, 1)
        XCTAssertEqual(a.flicks, 1)
        XCTAssertEqual(a.forehands, 1)
        XCTAssertEqual(a.backhands, 1)
        XCTAssertEqual(a.totalShots, 3)
        XCTAssertEqual(a.count(.smash), 1)
        var b = MatchStats()
        b.longestRally = 9
        b.pointsWon = 4
        b.merge(a)
        a.longestRally = 20
        b.merge(a)
        XCTAssertEqual(b.longestRally, 20)
        XCTAssertEqual(b.smashes, 2)
    }

    // MARK: Settings and formats

    func testMatchFormats() {
        XCTAssertEqual(MatchFormat.quick.config().pointsPerGame, 7)
        XCTAssertEqual(MatchFormat.quick.config().gamesToWin, 1)
        XCTAssertEqual(MatchFormat.standard.config().pointsPerGame, 11)
        XCTAssertEqual(MatchFormat.standard.config().gamesToWin, 2)
        XCTAssertEqual(MatchFormat.full.config().gamesToWin, 3)
        XCTAssertEqual(MatchFormat.standard.config(firstServer: .opponent).firstServer, .opponent)
    }

    // MARK: Persistence

    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("wristpong-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("profile.json")
    }

    func testProfileSurvivesSaveAndLoad() throws {
        let store = FileProfileStore(url: tempURL())
        XCTAssertNil(store.load())
        var p = PongProfile()
        p.level = 7
        p.coins = 321
        p.upgrades = PlayerUpgrades(power: 3, control: 1, spin: 2, reflex: 4)
        p.careerProgress = 3
        p.hasOnboarded = true
        p.settings.developerMode = true
        p.settings.matchFormat = .quick
        p.settings.swingConfig.smashMin = 6.2
        p.calibration = SwingCalibration(forehandYawSign: -1, drivePeak: 3.3, hasNeutral: true, hasStrokes: true)
        p.drillStars = ["push": 2]
        p.daily = DailyChallengeState.generate(for: date(2026, 11, 6), calendar: utc)
        try store.save(p)
        XCTAssertEqual(store.load(), p)
    }

    func testCorruptFileIsMovedAsideNotCrashed() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: url)
        XCTAssertNil(FileProfileStore(url: url).load())
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(contents.contains { $0.hasPrefix("profile.corrupt-") })
    }

    func testPartialAndGarbageProfilesStillLoad() throws {
        let partial = #"{"level": 5, "coins": 12, "settings": {"soundEnabled": false}, "upgrades": {"power": 2}}"#
        let p = try JSONDecoder().decode(PongProfile.self, from: Data(partial.utf8))
        XCTAssertEqual(p.level, 5)
        XCTAssertFalse(p.settings.soundEnabled)
        XCTAssertTrue(p.settings.hapticsEnabled)
        XCTAssertEqual(p.upgrades.power, 2)
        XCTAssertEqual(p.opponentWins.count, OpponentProfile.roster.count)
        let garbage = #"{"level": "five", "coins": -50, "careerProgress": 99, "settings": 3}"#
        let g = try JSONDecoder().decode(PongProfile.self, from: Data(garbage.utf8))
        XCTAssertEqual(g.level, 1)
        XCTAssertEqual(g.coins, 0)
        XCTAssertEqual(g.careerProgress, OpponentProfile.roster.count)
        XCTAssertEqual(g.settings, AppSettings())
    }

    func testInMemoryStore() throws {
        let store = InMemoryProfileStore()
        XCTAssertNil(store.load())
        try store.save(PongProfile())
        try store.save(PongProfile())
        XCTAssertEqual(store.saveCount, 2)
    }
}
