import Foundation

public enum Arc: String, Sendable {
    /// Flat, fast trajectory (drives, smashes, blocks).
    case low
    /// Lofted trajectory (lobs).
    case high
}

public struct LaunchSolution: Sendable {
    /// Launch velocity in world coordinates.
    public var velocity: Vec3
    /// Where the ball is predicted to land on the target half (world coordinates).
    public var landing: Vec3?
    /// The solver could aim at the requested point (otherwise it did its best).
    public var reachedTarget: Bool
}

/// The "shooting method": given a launch speed, spin and a target spot, find the
/// launch pitch and yaw that make the *real* physics land the ball there
/// (including Magnus curve, drag, net clearance). The game then perturbs the
/// target by the shot's quality, so errors look natural: a rushed topspin
/// lands long, a stretched backhand hits the net.
public enum ShotSolver {
    struct Outcome {
        /// Landing x (hitter coordinates) or a sentinel: net -> very short.
        var landingX: Double
        var landing: Vec3?
    }

    private static let dt = BallPhysics.fixedStep

    // MARK: Simulation (hitter coordinates)

    /// Flies the ball until its first bounce on the far half, the net, or the floor.
    static func simulate(origin: Vec3, velocity: Vec3, spin: Vec3, params: PhysicsParams = .standard) -> Outcome {
        var ball = BallState(position: origin, velocity: velocity, spin: spin)
        let maxSteps = Int(2.6 / dt)
        for _ in 0..<maxSteps {
            let events = BallPhysics.step(&ball, dt: dt, params: params)
            for e in events {
                switch e {
                case .netTouch(let kind):
                    return Outcome(landingX: kind == .blocked ? -4 : -2, landing: nil)
                case .tableBounce(let side, let pos, _):
                    if side == .far { return Outcome(landingX: pos.x, landing: pos) }
                    return Outcome(landingX: pos.x, landing: nil)       // short: bounced on own half
                case .floorHit(let pos):
                    // Off the side of the table: long. Beyond the far end: how far long.
                    // Anywhere else the ball never touched the table (under it / behind the hitter): short.
                    if abs(pos.z) > Table.halfWidth + 0.02 { return Outcome(landingX: Table.halfLength + 0.05, landing: nil) }
                    if pos.x > Table.halfLength { return Outcome(landingX: pos.x, landing: nil) }
                    return Outcome(landingX: min(pos.x, -0.9), landing: nil)
                }
            }
            if ball.position.x > Table.halfLength + 3 { break }
        }
        return Outcome(landingX: ball.position.x, landing: nil)
    }

    private static func velocity(speed: Double, pitch: Double, yaw: Double) -> Vec3 {
        Vec3(speed * cos(pitch) * cos(yaw), speed * sin(pitch), speed * cos(pitch) * sin(yaw))
    }

    // MARK: Rally shots

    /// Solves a rally shot in hitter coordinates.
    public static func solveLocal(origin: Vec3,
                                  speed: Double,
                                  spin: SpinSpec,
                                  target: (x: Double, z: Double),
                                  arc: Arc,
                                  params: PhysicsParams = .standard) -> LaunchSolution {
        let omega = spin.vector
        var yaw = atan2(target.z - origin.z, max(0.3, target.x - origin.x))
        var pitch = 0.0
        var landing: Vec3?
        var reached = false

        for _ in 0..<4 {
            pitch = findPitch(origin: origin, speed: speed, yaw: yaw, omega: omega,
                              targetX: target.x, arc: arc, params: params)
            let out = simulate(origin: origin, velocity: velocity(speed: speed, pitch: pitch, yaw: yaw),
                               spin: omega, params: params)
            landing = out.landing
            guard let l = out.landing else { break }
            let zErr = target.z - l.z
            reached = abs(l.x - target.x) < 0.12 && abs(zErr) < 0.08
            if abs(zErr) < 0.02 { break }
            yaw += zErr / max(0.6, l.x - origin.x)
        }
        return LaunchSolution(velocity: velocity(speed: speed, pitch: pitch, yaw: yaw), landing: landing, reachedTarget: reached)
    }

    /// World-coordinate convenience wrapper.
    public static func solve(origin: Vec3,
                             facing: Facing,
                             speed: Double,
                             spin: SpinSpec,
                             target: (x: Double, z: Double),
                             arc: Arc,
                             params: PhysicsParams = .standard) -> LaunchSolution {
        let local = solveLocal(origin: facing.toLocal(origin),
                               speed: speed, spin: spin,
                               target: (target.x * facing.sign, target.z * facing.sign),
                               arc: arc, params: params)
        var out = local
        out.velocity = facing.toWorld(local.velocity)
        if let l = local.landing { out.landing = facing.toWorld(l) }
        return out
    }

    static func findPitch(origin: Vec3, speed: Double, yaw: Double, omega: Vec3,
                                  targetX: Double, arc: Arc, params: PhysicsParams) -> Double {
        let lo = arc == .low ? -0.9 : 0.75
        let hi = arc == .low ? 0.75 : 1.45
        let n = 34

        func f(_ pitch: Double) -> Double {
            simulate(origin: origin, velocity: velocity(speed: speed, pitch: pitch, yaw: yaw), spin: omega, params: params).landingX - targetX
        }

        var prevPitch = lo
        var prevF = f(lo)
        var bestPitch = lo
        var bestAbs = abs(prevF)
        for i in 1...n {
            let p = lo + (hi - lo) * Double(i) / Double(n)
            let fv = f(p)
            if abs(fv) < bestAbs {
                bestAbs = abs(fv)
                bestPitch = p
            }
            if prevF * fv <= 0 {
                // Bracketed a root: bisect.
                var a = prevPitch, b = p
                var fa = prevF
                for _ in 0..<12 {
                    let m = (a + b) / 2
                    let fm = f(m)
                    if fa * fm <= 0 { b = m } else { a = m; fa = fm }
                }
                // The root can sit on the net-clip discontinuity: never return a pitch that clips.
                let fa2 = f(a), fb2 = f(b)
                let aValid = fa2 + targetX > -1.5, bValid = fb2 + targetX > -1.5
                if aValid && bValid { return abs(fa2) <= abs(fb2) ? a : b }
                if aValid { return a }
                if bValid { return b }
                return (a + b) / 2
            }
            prevPitch = p
            prevF = fv
        }
        return bestPitch
    }

    // MARK: Serves

    /// Serve: the ball must first bounce on the server's own half, clear the net
    /// and land on the receiver's half. Returns nil if no legal serve exists for
    /// this speed/spin (e.g. far too fast).
    public static func solveServeLocal(origin: Vec3,
                                       speed: Double,
                                       spin: SpinSpec,
                                       target: (x: Double, z: Double),
                                       params: PhysicsParams = .standard) -> LaunchSolution? {
        let omega = spin.vector
        var yaw = atan2(target.z - origin.z, max(0.3, target.x - origin.x))
        var bestSolution: LaunchSolution?

        for _ in 0..<3 {
            var chosen: (pitch: Double, landing: Vec3, score: Double)?
            let n = 160
            for i in 0...n {
                let pitch = -0.85 + 1.35 * Double(i) / Double(n)
                guard let l = serveLanding(origin: origin, speed: speed, pitch: pitch, yaw: yaw, omega: omega, params: params) else { continue }
                let score = abs(l.x - target.x)
                if chosen == nil || score < chosen!.score { chosen = (pitch, l, score) }
            }
            guard let c = chosen else { return bestSolution }
            bestSolution = LaunchSolution(velocity: velocity(speed: speed, pitch: c.pitch, yaw: yaw),
                                          landing: c.landing,
                                          reachedTarget: abs(c.landing.x - target.x) < 0.2 && abs(c.landing.z - target.z) < 0.12)
            let zErr = target.z - c.landing.z
            if abs(zErr) < 0.03 { break }
            yaw += zErr / max(0.8, c.landing.x - origin.x)
        }
        return bestSolution
    }

    public static func solveServe(origin: Vec3,
                                  facing: Facing,
                                  speed: Double,
                                  spin: SpinSpec,
                                  target: (x: Double, z: Double),
                                  params: PhysicsParams = .standard) -> LaunchSolution? {
        guard var s = solveServeLocal(origin: facing.toLocal(origin), speed: speed, spin: spin,
                                      target: (target.x * facing.sign, target.z * facing.sign), params: params) else { return nil }
        s.velocity = facing.toWorld(s.velocity)
        if let l = s.landing { s.landing = facing.toWorld(l) }
        return s
    }

    /// Second-bounce landing of a *legal* serve, nil if illegal (first bounce not on own half, net, ...).
    private static func serveLanding(origin: Vec3, speed: Double, pitch: Double, yaw: Double, omega: Vec3, params: PhysicsParams) -> Vec3? {
        var ball = BallState(position: origin, velocity: velocity(speed: speed, pitch: pitch, yaw: yaw), spin: omega)
        var bounces = 0
        let maxSteps = Int(2.6 / dt)
        for _ in 0..<maxSteps {
            for e in BallPhysics.step(&ball, dt: dt, params: params) {
                switch e {
                case .netTouch:
                    return nil
                case .tableBounce(let side, let pos, _):
                    bounces += 1
                    if bounces == 1 {
                        guard side == .near, pos.x < -0.1, pos.x > -1.3 else { return nil }
                    } else {
                        return side == .far ? pos : nil
                    }
                case .floorHit:
                    return nil
                }
            }
        }
        return nil
    }

    // MARK: Prediction helpers

    /// Flies a copy of the ball and records its path (for AI prediction and the UI's timing guide).
    public static func predict(from start: BallState, duration: Double, params: PhysicsParams = .standard) -> [(t: Double, state: BallState)] {
        var ball = start
        var out: [(Double, BallState)] = [(0, ball)]
        let steps = Int(duration / dt)
        for i in 1...max(1, steps) {
            BallPhysics.step(&ball, dt: dt, params: params)
            out.append((Double(i) * dt, ball))
            if ball.velocity == .zero { break }
        }
        return out
    }
}
