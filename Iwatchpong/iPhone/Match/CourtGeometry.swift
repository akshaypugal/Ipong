import SwiftUI
import PongCore

/// SwiftUI also has a `Table`; make the court table unambiguous across the app.
typealias Table = PongCore.Table

/// A simple perspective camera behind the human player's end of the table.
struct CourtCamera {
    var position = Vec3(-3.7, 1.3, 0)
    var target = Vec3(0.35, -0.1, 0)

    private var forward: Vec3 { (target - position).normalized }
    private var right: Vec3 { forward.cross(Vec3(0, 1, 0)).normalized }
    private var up: Vec3 { right.cross(forward) }

    func focal(for size: CGSize) -> CGFloat { size.width * 1.2 }
    private func center(for size: CGSize) -> CGPoint { CGPoint(x: size.width / 2, y: size.height * 0.40) }

    /// Screen position of a world point, nil if it is behind the camera.
    func project(_ p: Vec3, in size: CGSize) -> CGPoint? {
        let d = p - position
        let depth = d.dot(forward)
        guard depth > 0.25 else { return nil }
        let x = d.dot(right)
        let y = d.dot(up)
        let f = focal(for: size)
        let c = center(for: size)
        return CGPoint(x: c.x + f * CGFloat(x / depth), y: c.y - f * CGFloat(y / depth))
    }

    /// Pixels per metre at the depth of `p`.
    func scale(at p: Vec3, in size: CGSize) -> CGFloat {
        let depth = max(0.25, (p - position).dot(forward))
        return focal(for: size) / CGFloat(depth)
    }
}

/// Where a paddle is while a stroke plays out, in the hitter's own axes.
enum PaddleChoreography {
    struct Pose {
        var forward: Double
        var up: Double
        var right: Double
        /// Face tilt: positive = closed (face tips down, topspin), negative = open (backspin).
        var tilt: Double
    }

    static let duration = 0.46

    static func ready(handed: Double) -> Pose { Pose(forward: 0.02, up: 0.0, right: 0.30 * handed, tilt: 0.05) }

    private static func keyPoses(_ stroke: StrokeKind) -> (back: Pose, end: Pose) {
        switch stroke {
        case .drive: return (Pose(forward: -0.40, up: 0.00, right: 0.28, tilt: 0.10), Pose(forward: 0.30, up: 0.08, right: -0.22, tilt: 0.10))
        case .topspin: return (Pose(forward: -0.38, up: -0.30, right: 0.25, tilt: 0.35), Pose(forward: 0.28, up: 0.35, right: -0.18, tilt: 0.35))
        case .chop: return (Pose(forward: -0.35, up: 0.32, right: 0.20, tilt: -0.45), Pose(forward: 0.25, up: -0.28, right: -0.12, tilt: -0.45))
        case .push: return (Pose(forward: -0.18, up: 0.08, right: 0.12, tilt: -0.50), Pose(forward: 0.18, up: -0.10, right: -0.06, tilt: -0.50))
        case .smash: return (Pose(forward: -0.45, up: 0.55, right: 0.22, tilt: 0.25), Pose(forward: 0.30, up: -0.12, right: -0.28, tilt: 0.25))
        case .lob: return (Pose(forward: -0.30, up: -0.35, right: 0.18, tilt: -0.60), Pose(forward: 0.10, up: 0.75, right: -0.10, tilt: -0.60))
        case .block: return (Pose(forward: -0.08, up: 0.02, right: 0.05, tilt: 0.05), Pose(forward: 0.12, up: 0.0, right: 0.0, tilt: 0.05))
        case .drop: return (Pose(forward: -0.15, up: 0.05, right: 0.08, tilt: -0.35), Pose(forward: 0.14, up: -0.04, right: -0.04, tilt: -0.35))
        case .flick: return (Pose(forward: -0.10, up: 0.00, right: 0.18, tilt: 0.10), Pose(forward: 0.20, up: 0.05, right: -0.30, tilt: 0.10))
        }
    }

    private static func lerp(_ a: Pose, _ b: Pose, _ t: Double) -> Pose {
        Pose(forward: a.forward + (b.forward - a.forward) * t, up: a.up + (b.up - a.up) * t,
             right: a.right + (b.right - a.right) * t, tilt: a.tilt + (b.tilt - a.tilt) * t)
    }

    /// Pose at `progress` (0 = swing starts, 1 = back at ready).
    /// - Parameters:
    ///   - handed: +1 right-handed, -1 left-handed (which lateral side the paddle hand is on).
    static func pose(stroke: StrokeKind, side: StrokeSide, progress: Double, handed: Double) -> Pose {
        let rdy = ready(handed: handed)
        let sideSign: Double = side == .backhand ? -1 : 1
        var (back, end) = keyPoses(stroke)
        back.right = back.right * handed * sideSign
        end.right = end.right * handed * sideSign
        let contact = Pose(forward: 0.02, up: 0, right: 0.0, tilt: end.tilt)
        switch progress {
        case ..<0.0: return rdy
        case 0..<0.36: return lerp(rdy, back, easeInOut(progress / 0.36))
        case 0.36..<0.54: return lerp(back, contact, easeOut((progress - 0.36) / 0.18))
        case 0.54..<0.72: return lerp(contact, end, easeOut((progress - 0.54) / 0.18))
        case 0.72..<1.0: return lerp(end, rdy, easeInOut((progress - 0.72) / 0.28))
        default: return rdy
        }
    }
}

/// 3D disc of a paddle: where it is and how it is oriented.
struct PaddleGeometry {
    var center: Vec3
    var normal: Vec3
    var across: Vec3     // in the face plane, sideways
    var along: Vec3      // in the face plane, toward the handle's opposite end (up the face)

    static func make(anchor: Vec3, pose: PaddleChoreography.Pose, facing: Facing) -> PaddleGeometry {
        let s = facing.sign
        // Hitter axes in world space: forward = (s,0,0), up = y, right = (0,0,s).
        let center = anchor + Vec3(pose.forward * s, pose.up, pose.right * s)
        let normal = Vec3(cos(pose.tilt) * s, -sin(pose.tilt), 0).normalized
        let across = Vec3(0, 0, s)
        let along = across.cross(normal).normalized
        return PaddleGeometry(center: center, normal: normal, across: across, along: along)
    }

    func rimPoint(_ angle: Double, radius: Double) -> Vec3 {
        center + across * (cos(angle) * radius) + along * (sin(angle) * radius)
    }

    /// Where the handle meets the player's hand.
    func handlePoint(length: Double) -> Vec3 { center - along * length }
}
