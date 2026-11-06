import XCTest
@testable import PongCore

final class PhysicsTests: XCTestCase {
    private func fly(_ start: BallState, until: (PhysicsEvent) -> Bool, maxTime: Double = 3) -> (state: BallState, time: Double, event: PhysicsEvent?) {
        var b = start
        var t = 0.0
        while t < maxTime {
            let events = BallPhysics.step(&b, dt: BallPhysics.fixedStep)
            t += BallPhysics.fixedStep
            if let e = events.first(where: until) { return (b, t, e) }
        }
        return (b, t, nil)
    }

    private func isBounce(_ e: PhysicsEvent) -> Bool {
        if case .tableBounce = e { return true }
        return false
    }

    // MARK: Basic motion

    func testFreeFallTimeAndBounceHeight() {
        let start = BallState(position: Vec3(0.5, 1.0, 0.2))
        let hit = fly(start, until: isBounce)
        XCTAssertNotNil(hit.event)
        XCTAssertEqual(hit.time, (2 * (1.0 - Table.ballRadius) / 9.81).squareRoot(), accuracy: 0.02)

        // Apex after the bounce: ~ e^2 of the drop height.
        var b = hit.state
        var apex = b.position.y
        for _ in 0..<400 {
            BallPhysics.step(&b, dt: BallPhysics.fixedStep)
            apex = max(apex, b.position.y)
            if b.velocity.y < 0 { break }
        }
        let ratio = (apex - Table.ballRadius) / (1.0 - Table.ballRadius)
        // Restitution 0.91 squared is 0.83; air drag on the way down and up takes some off.
        XCTAssertGreaterThan(ratio, 0.6)
        XCTAssertLessThan(ratio, 0.88)
    }

    func testBallThatMissesTheTableHitsTheFloor() {
        let start = BallState(position: Vec3(2.5, 0.5, 0), velocity: Vec3(1, 0, 0))
        let hit = fly(start, until: { if case .floorHit = $0 { return true } else { return false } })
        XCTAssertNotNil(hit.event)
        XCTAssertEqual(hit.state.velocity, .zero)
    }

    func testBouncesReportTheCorrectSide() {
        let near = fly(BallState(position: Vec3(-0.6, 0.5, 0)), until: isBounce)
        let far = fly(BallState(position: Vec3(0.6, 0.5, 0)), until: isBounce)
        if case .tableBounce(let s1, _, _)? = near.event { XCTAssertEqual(s1, .near) } else { XCTFail() }
        if case .tableBounce(let s2, _, _)? = far.event { XCTAssertEqual(s2, .far) } else { XCTFail() }
    }

    // MARK: Spin

    private func landingAfterBounce(spin: Vec3) -> (vx: Double, state: BallState) {
        // Ball travelling toward the far end, bouncing on the far half.
        var s = BallState(position: Vec3(0.3, 0.12, 0), velocity: Vec3(5, -2, 0), spin: spin)
        s.spin = spin
        let hit = fly(s, until: isBounce)
        return (hit.state.velocity.x, hit.state)
    }

    func testTopspinKicksForwardAndBackspinSlowsTheBall() {
        let flat = landingAfterBounce(spin: .zero).vx
        let top = landingAfterBounce(spin: SpinSpec(top: 350).vector).vx
        let back = landingAfterBounce(spin: SpinSpec(top: -350).vector).vx
        XCTAssertGreaterThan(top, flat, "topspin kicks forward")
        XCTAssertLessThan(back, top, "backspin is slower than topspin off the table")
    }

    func testTopspinDipsAndBackspinFloats() {
        func landingX(top: Double) -> Double {
            let start = BallState(position: Vec3(-1.4, 0.25, 0), velocity: Vec3(8, 1.6, 0), spin: SpinSpec(top: top).vector)
            return fly(start, until: isBounce).state.position.x
        }
        let flat = landingX(top: 0)
        XCTAssertLessThan(landingX(top: 400), flat, "topspin dives sooner")
        XCTAssertGreaterThan(landingX(top: -400), flat, "backspin floats further")
    }

    func testSidespinCurvesTheBall() {
        func landingZ(side: Double) -> Double {
            let start = BallState(position: Vec3(-1.4, 0.25, 0), velocity: Vec3(7, 1.4, 0), spin: SpinSpec(side: side).vector)
            return fly(start, until: isBounce).state.position.z
        }
        XCTAssertEqual(landingZ(side: 0), 0, accuracy: 0.01)
        XCTAssertLessThan(landingZ(side: 300), -0.03, "positive sidespin curves toward the hitter's left (-z)")
        XCTAssertGreaterThan(landingZ(side: -300), 0.03)
    }

    func testSpinAxisConventionsMatchPhysics() {
        // Moving +x with topspin: the Magnus force pushes the ball down.
        var b = BallState(position: Vec3(-1, 0.5, 0), velocity: Vec3(6, 0, 0), spin: SpinSpec(top: 300).vector)
        let withSpin = { () -> Double in
            var c = b
            for _ in 0..<60 { BallPhysics.step(&c, dt: BallPhysics.fixedStep) }
            return c.position.y
        }()
        b.spin = .zero
        var c = b
        for _ in 0..<60 { BallPhysics.step(&c, dt: BallPhysics.fixedStep) }
        XCTAssertLessThan(withSpin, c.position.y)
    }

    func testSpinIsGainedFromTheTableOnBounce() {
        // A flat ball skidding in with forward speed picks up topspin from table friction.
        var b = BallState(position: Vec3(0.3, 0.1, 0), velocity: Vec3(6, -2.5, 0))
        _ = fly(b, until: isBounce)
        var c = b
        while true {
            let ev = BallPhysics.step(&c, dt: BallPhysics.fixedStep)
            if ev.contains(where: isBounce) { break }
        }
        XCTAssertLessThan(c.spin.z, 0, "forward friction on the bottom of the ball creates topspin (omega_z < 0)")
        b = c
    }

    // MARK: Net

    func testBallIntoTheNetIsBlocked() {
        var b = BallState(position: Vec3(-0.5, 0.06, 0), velocity: Vec3(5, 0, 0))
        var touched: NetContact?
        for _ in 0..<400 {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                if case .netTouch(let k) = e { touched = k }
            }
            if touched != nil { break }
        }
        XCTAssertEqual(touched, .blocked)
        XCTAssertLessThan(b.position.x, 0.001, "stays on the hitter's side")
    }

    func testBallOverTheNetIsClean() {
        var b = BallState(position: Vec3(-0.5, 0.45, 0), velocity: Vec3(5, 0, 0))
        var touched = false
        for _ in 0..<300 {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                if case .netTouch = e { touched = true }
            }
        }
        XCTAssertFalse(touched)
        XCTAssertGreaterThan(b.position.x, 0)
    }

    func testBallAroundTheNetPostsPasses() {
        var b = BallState(position: Vec3(-0.5, 0.05, 1.2), velocity: Vec3(5, 0, 0))
        var touched = false
        for _ in 0..<200 {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                if case .netTouch = e { touched = true }
            }
        }
        XCTAssertFalse(touched)
    }

    func testNetCordClipSlowsTheBall() {
        // Skim the tape: centre just above the tape top minus part of a radius.
        var b = BallState(position: Vec3(-0.3, Table.netHeight + Table.ballRadius + 0.012, 0), velocity: Vec3(5, 0, 0))
        var clipped = false
        for _ in 0..<200 {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                if case .netTouch(.clip) = e { clipped = true }
            }
        }
        XCTAssertTrue(clipped)
    }

    // MARK: Determinism

    func testStepIsDeterministic() {
        func run() -> Vec3 {
            var b = BallState(position: Vec3(-1.4, 0.3, 0.2), velocity: Vec3(7, 1, -0.5), spin: Vec3(10, 50, -200))
            for _ in 0..<500 { BallPhysics.step(&b, dt: BallPhysics.fixedStep) }
            return b.position
        }
        XCTAssertEqual(run(), run())
    }

    // MARK: Solver

    private func landingOf(_ solution: LaunchSolution, origin: Vec3, spin: SpinSpec, facing: Facing = .towardFar) -> Vec3? {
        // Re-simulate in world coordinates to verify the solver's claim independently.
        var b = BallState(position: origin, velocity: solution.velocity, spin: facing.toWorld(spin.vector))
        for _ in 0..<Int(2.5 / BallPhysics.fixedStep) {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                switch e {
                case .tableBounce(let side, let p, _):
                    if side == (facing == .towardFar ? .far : .near) { return p }
                    return nil
                case .netTouch: return nil
                case .floorHit: return nil
                }
            }
        }
        return nil
    }

    func testSolverLandsOnTargetForDifferentShots() {
        let origin = Vec3(-1.6, 0.22, 0.1)
        let shots: [(speed: Double, spin: SpinSpec, target: (x: Double, z: Double))] = [
            (11, SpinSpec(top: 120), (0.9, 0.0)),
            (9, SpinSpec(top: 300), (1.0, 0.35)),
            (6, SpinSpec(top: -250), (0.7, -0.3)),
            (15, SpinSpec(top: 80), (1.1, 0.25)),
            (8, SpinSpec(side: 250), (0.8, 0.0))
        ]
        for s in shots {
            let sol = ShotSolver.solve(origin: origin, facing: .towardFar, speed: s.speed, spin: s.spin, target: s.target, arc: .low)
            guard let l = landingOf(sol, origin: origin, spin: s.spin) else {
                XCTFail("shot \(s) never landed on the far half"); continue
            }
            XCTAssertEqual(l.x, s.target.x, accuracy: 0.15, "depth for \(s)")
            XCTAssertEqual(l.z, s.target.z, accuracy: 0.12, "width for \(s)")
        }
    }

    func testSolverShotsClearTheNet() {
        let origin = Vec3(-1.6, 0.2, 0)
        let sol = ShotSolver.solve(origin: origin, facing: .towardFar, speed: 9, spin: SpinSpec(top: 150),
                                   target: (0.5, 0), arc: .low)
        var b = BallState(position: origin, velocity: sol.velocity, spin: SpinSpec(top: 150).vector)
        var touched = false
        for _ in 0..<400 {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) { if case .netTouch = e { touched = true } }
        }
        XCTAssertFalse(touched)
    }

    func testHighArcLobGoesHighAndLandsDeep() {
        let origin = Vec3(-2.0, 0.3, 0)
        let sol = ShotSolver.solve(origin: origin, facing: .towardFar, speed: 7.5, spin: SpinSpec(top: 60),
                                   target: (1.0, 0.0), arc: .high)
        var b = BallState(position: origin, velocity: sol.velocity, spin: SpinSpec(top: 60).vector)
        var apex = 0.0
        var landing: Vec3?
        for _ in 0..<Int(3 / BallPhysics.fixedStep) {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                if case .tableBounce(let side, let p, _) = e, landing == nil, side == .far { landing = p }
            }
            apex = max(apex, b.position.y)
            if landing != nil { break }
        }
        XCTAssertGreaterThan(apex, 1.0, "a lob goes high")
        XCTAssertNotNil(landing)
        XCTAssertEqual(landing?.x ?? 0, 1.0, accuracy: 0.25)
    }

    func testOpponentFacingMirrorsTheSolver() {
        // The far player hits toward -x: same solver, mirrored world.
        let origin = Vec3(1.6, 0.22, -0.1)
        let spin = SpinSpec(top: 200)
        let sol = ShotSolver.solve(origin: origin, facing: .towardNear, speed: 10, spin: spin, target: (-0.9, 0.2), arc: .low)
        guard let l = landingOf(sol, origin: origin, spin: spin, facing: .towardNear) else { return XCTFail("did not land on the near half") }
        XCTAssertEqual(l.x, -0.9, accuracy: 0.15)
        XCTAssertEqual(l.z, 0.2, accuracy: 0.12)
    }

    func testSidespinIsCompensatedByTheSolver() {
        let origin = Vec3(-1.6, 0.22, 0)
        let spin = SpinSpec(side: 350)
        let sol = ShotSolver.solve(origin: origin, facing: .towardFar, speed: 8, spin: spin, target: (0.9, 0.3), arc: .low)
        let l = landingOf(sol, origin: origin, spin: spin)
        XCTAssertEqual(l?.z ?? 9, 0.3, accuracy: 0.12)
        XCTAssertGreaterThan(sol.velocity.z, 0.4, "it aims right of the target so the curve brings it back")
    }

    func testServeSolverBouncesOnOwnHalfFirst() {
        let origin = Vec3(-1.5, 0.18, 0)
        guard let sol = ShotSolver.solveServe(origin: origin, facing: .towardFar, speed: 6,
                                              spin: SpinSpec(top: -150), target: (0.8, 0.2)) else {
            return XCTFail("no legal serve found")
        }
        var b = BallState(position: origin, velocity: sol.velocity, spin: SpinSpec(top: -150).vector)
        var bounces: [(CourtSide, Vec3)] = []
        for _ in 0..<Int(2.5 / BallPhysics.fixedStep) {
            for e in BallPhysics.step(&b, dt: BallPhysics.fixedStep) {
                if case .tableBounce(let side, let p, _) = e { bounces.append((side, p)) }
            }
            if bounces.count >= 2 { break }
        }
        XCTAssertEqual(bounces.count, 2)
        XCTAssertEqual(bounces[0].0, .near)
        XCTAssertEqual(bounces[1].0, .far)
        XCTAssertEqual(bounces[1].1.x, 0.8, accuracy: 0.25)
    }

    func testImpossibleServeReturnsNil() {
        // Absurdly fast: no pitch can bounce on the own half and still land on the far half.
        let sol = ShotSolver.solveServe(origin: Vec3(-1.5, 0.18, 0), facing: .towardFar, speed: 40,
                                        spin: .flat, target: (0.8, 0))
        XCTAssertNil(sol)
    }

    func testPredictFollowsTheBall() {
        let start = BallState(position: Vec3(-1, 0.4, 0), velocity: Vec3(6, 1, 0))
        let path = ShotSolver.predict(from: start, duration: 0.5)
        XCTAssertGreaterThan(path.count, 100)
        XCTAssertGreaterThan(path.last!.state.position.x, 1.3)
    }
}
