import Foundation

/// Regulation table-tennis dimensions (metres). The table surface is y = 0.
///
///     x: along the table, -1.37 (human end) ... +1.37 (opponent end), net at x = 0
///     y: up, table surface at 0
///     z: across the table, positive = the human player's right-hand side
public enum Table {
    public static let length = 2.74
    public static let width = 1.525
    public static let halfLength = 1.37
    public static let halfWidth = 0.7625
    public static let netHeight = 0.1525
    public static let netHalfWidth = 0.915
    public static let ballRadius = 0.02
    public static let floorY = -0.76
}

/// Which half of the table (and which player) something belongs to.
public enum CourtSide: String, Codable, Sendable {
    /// x < 0: the human player's half.
    case near
    /// x > 0: the opponent's half.
    case far

    public static func of(x: Double) -> CourtSide { x < 0 ? .near : .far }

    public var opposite: CourtSide { self == .near ? .far : .near }
}

public struct BallState: Equatable, Sendable {
    public var position: Vec3
    public var velocity: Vec3
    /// Angular velocity, rad/s.
    public var spin: Vec3

    public init(position: Vec3, velocity: Vec3 = .zero, spin: Vec3 = .zero) {
        self.position = position
        self.velocity = velocity
        self.spin = spin
    }

    public var speed: Double { velocity.magnitude }
}

public enum NetContact: String, Equatable, Sendable {
    /// Touched the tape and carried on (a "net cord").
    case clip
    /// Stopped by the net.
    case blocked
}

public enum PhysicsEvent: Equatable, Sendable {
    case tableBounce(side: CourtSide, position: Vec3, speed: Double)
    case netTouch(NetContact)
    case floorHit(position: Vec3)
}

public struct PhysicsParams: Sendable {
    public var gravity = 9.81
    /// Quadratic drag: a = -dragK * |v| * v.
    public var dragK = 0.112
    /// Magnus: a = magnusK * (omega x v).
    public var magnusK = 0.0034
    /// Vertical restitution of the table.
    public var restitution = 0.91
    /// Coulomb friction coefficient of the table.
    public var tableFriction = 0.26
    /// Spin decays slowly in the air (1/s).
    public var spinDecay = 0.35

    public init() {}
    public static let standard = PhysicsParams()
}

/// Ball flight, spin, table bounce and net, all in one deterministic fixed-step integrator.
public enum BallPhysics {
    public static let fixedStep = 1.0 / 240.0

    /// Advances the ball by `dt` seconds and reports what it touched.
    @discardableResult
    public static func step(_ b: inout BallState, dt: Double, params p: PhysicsParams = .standard) -> [PhysicsEvent] {
        var events: [PhysicsEvent] = []
        let prev = b.position
        let v = b.velocity
        let speed = v.magnitude

        // Gravity + drag + Magnus lift.
        var a = Vec3(0, -p.gravity, 0)
        a = a - v * (p.dragK * speed)
        a = a + b.spin.cross(v) * p.magnusK
        b.velocity = v + a * dt
        b.position = prev + b.velocity * dt
        b.spin = b.spin * exp(-p.spinDecay * dt)

        // Net: crossed the x = 0 plane this step?
        if (prev.x < 0 && b.position.x >= 0) || (prev.x > 0 && b.position.x <= 0) {
            let denom = abs(prev.x - b.position.x)
            let f = denom > 1e-12 ? abs(prev.x) / denom : 0
            let yc = prev.y + (b.position.y - prev.y) * f
            let zc = prev.z + (b.position.z - prev.z) * f
            if abs(zc) <= Table.netHalfWidth + Table.ballRadius, yc + Table.ballRadius > 0 {
                let clearance = yc - Table.ballRadius - Table.netHeight
                if clearance >= 0 {
                    // Clean.
                } else if clearance >= -Table.ballRadius * 0.9 {
                    // Clipped the tape: slowed, popped up.
                    b.velocity.x *= 0.6
                    b.velocity.y = max(b.velocity.y, 0) + 0.8
                    b.spin = b.spin * 0.5
                    events.append(.netTouch(.clip))
                } else {
                    // Into the net: drops dead on the hitter's side.
                    b.velocity.x = -b.velocity.x * 0.1
                    b.velocity.y = min(b.velocity.y, 0) * 0.2
                    b.velocity.z *= 0.3
                    b.spin = .zero
                    b.position.x = prev.x
                    events.append(.netTouch(.blocked))
                }
            }
        }

        // Table bounce.
        let r = Table.ballRadius
        if b.velocity.y < 0, prev.y - r > 0, b.position.y - r <= 0,
           abs(b.position.x) <= Table.halfLength + 0.005, abs(b.position.z) <= Table.halfWidth + 0.005 {
            bounce(&b, params: p)
            events.append(.tableBounce(side: CourtSide.of(x: b.position.x), position: b.position, speed: b.velocity.magnitude))
        }

        // Floor: the rally is dead.
        if b.position.y <= Table.floorY + r {
            b.position.y = Table.floorY + r
            b.velocity = .zero
            b.spin = .zero
            events.append(.floorHit(position: b.position))
        }
        return events
    }

    /// Rigid ball on a rough surface: restitution on the normal, Coulomb friction
    /// on the tangent (sliding until the contact point stops, then rolling).
    static func bounce(_ b: inout BallState, params p: PhysicsParams) {
        let r = Table.ballRadius
        b.position.y = r
        let vyIn = b.velocity.y
        let jn = (1 + p.restitution) * (-vyIn)       // normal impulse per unit mass
        b.velocity.y = -p.restitution * vyIn

        // Velocity of the contact point (below the ball centre).
        let ux = b.velocity.x + b.spin.z * r
        let uz = b.velocity.z - b.spin.x * r
        let uMag = (ux * ux + uz * uz).squareRoot()
        guard uMag > 1e-9 else { return }

        // Thin spherical shell: I = (2/3) m r^2  =>  m r^2 / I = 1.5.
        let jStick = uMag / (1 + 1.5)
        let jt = min(p.tableFriction * jn, jStick)
        let jx = -ux / uMag * jt
        let jz = -uz / uMag * jt
        b.velocity.x += jx
        b.velocity.z += jz
        let inertia = (2.0 / 3.0) * r * r
        b.spin.x += (-r * jz) / inertia
        b.spin.z += (r * jx) / inertia
    }
}

// MARK: - Spin conventions

/// Spin described relative to the direction of travel, independent of which
/// player hits.
///
/// * `top`  > 0 topspin (ball dips and kicks forward), < 0 backspin (floats, stops).
/// * `side` > 0 curves the ball toward the hitter's *left* (z' < 0 in hitter coordinates).
public struct SpinSpec: Equatable, Sendable {
    public var top: Double      // rad/s
    public var side: Double     // rad/s

    public init(top: Double = 0, side: Double = 0) {
        self.top = top
        self.side = side
    }

    public static let flat = SpinSpec()

    /// Angular velocity vector for a ball travelling along +x' (hitter coordinates).
    /// Topspin axis = y x d = -z; sidespin axis = y.
    public var vector: Vec3 { Vec3(0, side, -top) }
}

/// Hitters face opposite ways. Everything the solver does happens in "hitter
/// coordinates" where the hitter always hits toward +x'. For the far player
/// that is a 180 degree rotation about the vertical axis.
public enum Facing: Int, Sendable {
    /// Human: hits toward +x.
    case towardFar = 1
    /// Opponent: hits toward -x.
    case towardNear = -1

    public var sign: Double { Double(rawValue) }

    func toLocal(_ v: Vec3) -> Vec3 { Vec3(v.x * sign, v.y, v.z * sign) }
    func toWorld(_ v: Vec3) -> Vec3 { toLocal(v) }       // the rotation is its own inverse
}
