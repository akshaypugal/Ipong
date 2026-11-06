import SwiftUI
import PongCore

/// Draws the whole court in perspective with SwiftUI's `Canvas`: arena, table, net,
/// both players with animated paddles, the ball with trail, shadow and spin,
/// bounce rings and the timing guide.
struct CourtRenderer {
    let snapshot: MatchSnapshot
    let opponent: OpponentProfile
    let trail: [Vec3]
    let bounceMarks: [BounceMark]
    let ballAngle: Double
    let rightHanded: Bool
    let showGuide: Bool
    let now: Date
    let size: CGSize

    private let camera = CourtCamera()
    private var handed: Double { rightHanded ? 1 : -1 }

    private func pt(_ v: Vec3) -> CGPoint? { camera.project(v, in: size) }

    private func polygon(_ points: [Vec3]) -> Path? {
        var path = Path()
        var first = true
        for p in points {
            guard let s = pt(p) else { return nil }
            if first { path.move(to: s); first = false } else { path.addLine(to: s) }
        }
        path.closeSubpath()
        return path
    }

    private func line(_ a: Vec3, _ b: Vec3) -> Path? {
        guard let p = pt(a), let q = pt(b) else { return nil }
        var path = Path()
        path.move(to: p)
        path.addLine(to: q)
        return path
    }

    // MARK: Entry point

    func draw(_ ctx: inout GraphicsContext) {
        drawBackground(&ctx)
        drawFloorAndTable(&ctx)
        drawOpponent(&ctx)
        drawNet(&ctx)
        drawBounceMarks(&ctx)
        drawBallShadow(&ctx)
        drawTimingGuide(&ctx)
        drawBall(&ctx)
        drawHuman(&ctx)
    }

    // MARK: Background

    private func drawBackground(_ ctx: inout GraphicsContext) {
        let rect = CGRect(origin: .zero, size: size)
        ctx.fill(Path(rect), with: .linearGradient(
            Gradient(colors: [Color(hex: "0A0C1A"), Color(hex: "1C1238"), Color(hex: "2A1440")]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height * 0.62)))
        // Crowd: rows of silhouettes along the back wall.
        for row in 0..<3 {
            let y = size.height * (0.06 + 0.035 * CGFloat(row))
            let count = 22 + row * 4
            for i in 0..<count {
                let x = (CGFloat(i) + 0.5 * CGFloat(row)) / CGFloat(count) * size.width
                let r = size.width * (0.016 + 0.002 * CGFloat(row))
                let shade = 0.10 + 0.05 * Double((i * 7 + row * 3) % 4)
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2.2)),
                         with: .color(Color.white.opacity(shade)))
            }
        }
        // Spotlights.
        for dx in [-0.28, 0.0, 0.28] as [CGFloat] {
            let c = CGPoint(x: size.width * (0.5 + dx), y: 0)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - size.width * 0.25, y: -size.height * 0.1,
                                            width: size.width * 0.5, height: size.height * 0.55)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.10), .clear]),
                                           center: CGPoint(x: c.x, y: size.height * 0.12), startRadius: 4, endRadius: size.width * 0.3))
        }
    }

    // MARK: Floor and table

    private func drawFloorAndTable(_ ctx: inout GraphicsContext) {
        let fy = Table.floorY
        // Floor.
        if let floor = polygon([Vec3(-3.2, fy, -6), Vec3(9, fy, -6), Vec3(9, fy, 6), Vec3(-3.2, fy, 6)]) {
            ctx.fill(floor, with: .linearGradient(
                Gradient(colors: [Color(hex: "1B1030"), Color(hex: "3A2A5C")]),
                startPoint: CGPoint(x: 0, y: size.height * 0.30), endPoint: CGPoint(x: 0, y: size.height)))
        }
        // Soft shadow under the table.
        if let shadow = polygon([Vec3(-1.6, fy, -0.95), Vec3(1.6, fy, -0.95), Vec3(1.6, fy, 0.95), Vec3(-1.6, fy, 0.95)]) {
            ctx.fill(shadow, with: .color(Color.black.opacity(0.35)))
        }
        // Legs.
        for (x, z) in [(-1.25, -0.65), (-1.25, 0.65), (1.25, -0.65), (1.25, 0.65)] as [(Double, Double)] {
            if let leg = line(Vec3(x, -0.04, z), Vec3(x, fy, z)) {
                let w = camera.scale(at: Vec3(x, -0.3, z), in: size) * 0.045
                ctx.stroke(leg, with: .color(Color(hex: "2A2F3A")), lineWidth: max(2, w))
            }
        }
        // Table thickness (front edge) and top.
        let hl = Table.halfLength, hw = Table.halfWidth
        if let front = polygon([Vec3(-hl, 0, -hw), Vec3(-hl, 0, hw), Vec3(-hl, -0.05, hw), Vec3(-hl, -0.05, -hw)]) {
            ctx.fill(front, with: .color(Color(hex: "123A73")))
        }
        if let side = polygon([Vec3(-hl, 0, hw), Vec3(hl, 0, hw), Vec3(hl, -0.05, hw), Vec3(-hl, -0.05, hw)]) {
            ctx.fill(side, with: .color(Color(hex: "16438A")))
        }
        if let top = polygon([Vec3(-hl, 0, -hw), Vec3(hl, 0, -hw), Vec3(hl, 0, hw), Vec3(-hl, 0, hw)]) {
            ctx.fill(top, with: .linearGradient(
                Gradient(colors: [Color(hex: "1B4F99"), Color(hex: "2467BE")]),
                startPoint: CGPoint(x: 0, y: size.height * 0.30), endPoint: CGPoint(x: 0, y: size.height * 0.62)))
            ctx.stroke(top, with: .color(.white), lineWidth: max(1.5, camera.scale(at: Vec3(0, 0, 0), in: size) * 0.02))
        }
        // Centre line and (faint) halves.
        if let center = line(Vec3(-hl, 0, 0), Vec3(hl, 0, 0)) {
            ctx.stroke(center, with: .color(Color.white.opacity(0.75)), lineWidth: max(1, camera.scale(at: Vec3(0, 0, 0), in: size) * 0.008))
        }
    }

    // MARK: Net

    private func drawNet(_ ctx: inout GraphicsContext) {
        let h = Table.netHeight, nw = Table.netHalfWidth
        // Mesh.
        var mesh = Path()
        var z = -nw
        while z <= nw + 0.001 {
            if let p = pt(Vec3(0, 0, z)), let q = pt(Vec3(0, h, z)) {
                mesh.move(to: p)
                mesh.addLine(to: q)
            }
            z += 0.07
        }
        for y in stride(from: 0.03, through: h, by: 0.03) {
            if let p = pt(Vec3(0, y, -nw)), let q = pt(Vec3(0, y, nw)) {
                mesh.move(to: p)
                mesh.addLine(to: q)
            }
        }
        ctx.stroke(mesh, with: .color(Color.white.opacity(0.35)), lineWidth: 0.6)
        // Tape and posts.
        let scale = camera.scale(at: Vec3(0, h, 0), in: size)
        if let tape = line(Vec3(0, h, -nw), Vec3(0, h, nw)) {
            ctx.stroke(tape, with: .color(.white), lineWidth: max(2, scale * 0.012))
        }
        for zz in [-nw, nw] {
            if let post = line(Vec3(0, -0.01, zz), Vec3(0, h + 0.01, zz)) {
                ctx.stroke(post, with: .color(Color(hex: "C9CED8")), lineWidth: max(2, scale * 0.016))
            }
        }
    }

    // MARK: People

    private func ageProgress(_ start: Double?) -> Double? {
        guard let s = start else { return nil }
        let p = (snapshot.time - s) / PaddleChoreography.duration
        return p >= 0 && p < 1 ? p : nil
    }

    private func bob(_ phase: Double) -> Double { sin(now.timeIntervalSinceReferenceDate * 3 + phase) * 0.012 }

    private func drawOpponent(_ ctx: inout GraphicsContext) {
        let o = snapshot.opponent
        let facing = Facing.towardNear
        let shirt = Color(hex: opponent.shirtHex)
        let skin = Color(hex: opponent.skinHex)
        let hair = Color(hex: opponent.hairHex)
        let x = o.x + 0.25
        let z = o.z
        let floorY = Table.floorY

        let hip = Vec3(x, 0.02, z)
        let shoulder = Vec3(x, 0.60 + bob(0), z)
        let head = Vec3(x, 0.80 + bob(0.5), z)
        let unit = camera.scale(at: hip, in: size)

        // Legs.
        for dz in [-0.10, 0.10] {
            if let l = line(Vec3(x, hip.y, z + dz), Vec3(x + 0.02, floorY + 0.03, z + dz * 1.3)) {
                ctx.stroke(l, with: .color(Color(hex: "20242E")), style: StrokeStyle(lineWidth: max(3, unit * 0.11), lineCap: .round))
            }
        }
        // Shorts and torso.
        if let t = line(hip, shoulder) {
            ctx.stroke(t, with: .color(shirt), style: StrokeStyle(lineWidth: max(6, unit * 0.30), lineCap: .round))
        }
        // Off arm.
        let offShoulder = Vec3(x, shoulder.y - 0.04, z - 0.17 * facing.sign)
        if let a = line(offShoulder, Vec3(x - 0.05, 0.25, z - 0.28 * facing.sign)) {
            ctx.stroke(a, with: .color(skin), style: StrokeStyle(lineWidth: max(2.5, unit * 0.07), lineCap: .round))
        }
        // Head and hair.
        if let hc = pt(head) {
            let r = max(5, unit * 0.115)
            ctx.fill(Path(ellipseIn: CGRect(x: hc.x - r, y: hc.y - r, width: r * 2, height: r * 2)), with: .color(skin))
            ctx.fill(Path(ellipseIn: CGRect(x: hc.x - r, y: hc.y - r * 1.05, width: r * 2, height: r * 1.2)), with: .color(hair))
        }
        // Paddle arm.
        let anchor = Vec3(o.x + facing.sign * 0.28, 0.20 + bob(1), o.z)
        let progress = ageProgress(o.swingStart)
        let pose = progress != nil && o.swingStroke != nil
            ? PaddleChoreography.pose(stroke: o.swingStroke!, side: o.swingSide, progress: progress!, handed: 1)
            : PaddleChoreography.ready(handed: 1)
        let geo = PaddleGeometry.make(anchor: anchor, pose: pose, facing: facing)
        let handShoulder = Vec3(x, shoulder.y - 0.04, z + 0.17 * facing.sign)
        if let a = line(handShoulder, geo.handlePoint(length: 0.12)) {
            ctx.stroke(a, with: .color(skin), style: StrokeStyle(lineWidth: max(2.5, unit * 0.075), lineCap: .round))
        }
        drawPaddle(&ctx, geo, rubber: Color(hex: opponent.paddleHex))
    }

    private func drawHuman(_ ctx: inout GraphicsContext) {
        let h = snapshot.human
        let facing = Facing.towardFar
        let anchor = Vec3(h.x + 0.28, 0.20 + bob(2), h.z)
        let progress = ageProgress(h.swingStart)
        let pose = progress != nil && h.swingStroke != nil
            ? PaddleChoreography.pose(stroke: h.swingStroke!, side: h.swingSide, progress: progress!, handed: handed)
            : PaddleChoreography.ready(handed: handed)
        let geo = PaddleGeometry.make(anchor: anchor, pose: pose, facing: facing)
        let unit = camera.scale(at: geo.center, in: size)
        // Forearm from out of frame.
        let hand = geo.handlePoint(length: 0.10)
        let elbow = Vec3(hand.x - 0.75, hand.y - 0.36, hand.z + 0.18 * handed)
        if let a = line(elbow, hand) {
            ctx.stroke(a, with: .color(Color(hex: "E2B88A")), style: StrokeStyle(lineWidth: max(8, unit * 0.12), lineCap: .round))
        }
        if let hp = pt(hand) {
            let r = max(6, unit * 0.06)
            ctx.fill(Path(ellipseIn: CGRect(x: hp.x - r, y: hp.y - r, width: r * 2, height: r * 2)), with: .color(Color(hex: "E2B88A")))
        }
        drawPaddle(&ctx, geo, rubber: Color(hex: "D7263D"))
    }

    private func drawPaddle(_ ctx: inout GraphicsContext, _ geo: PaddleGeometry, rubber: Color) {
        let radius = 0.115
        // Handle first (behind the blade).
        if let a = line(geo.handlePoint(length: 0.04), geo.handlePoint(length: 0.19)) {
            let w = camera.scale(at: geo.center, in: size) * 0.03
            ctx.stroke(a, with: .color(Color(hex: "C69B6D")), style: StrokeStyle(lineWidth: max(3, w), lineCap: .round))
        }
        var rim: [Vec3] = []
        for i in 0..<20 { rim.append(geo.rimPoint(Double(i) / 20 * 2 * .pi, radius: radius)) }
        guard let blade = polygon(rim) else { return }
        ctx.fill(blade, with: .color(rubber))
        ctx.stroke(blade, with: .color(Color.black.opacity(0.8)), lineWidth: max(1.5, camera.scale(at: geo.center, in: size) * 0.012))
        // Highlight so the face tilt reads.
        var inner: [Vec3] = []
        for i in 0..<14 { inner.append(geo.rimPoint(Double(i) / 14 * 2 * .pi, radius: radius * 0.55) + geo.along * (radius * 0.18)) }
        if let hi = polygon(inner) {
            ctx.fill(hi, with: .color(Color.white.opacity(0.14 + 0.1 * max(0, geo.normal.y * -1))))
        }
    }

    // MARK: Ball

    private func drawBallShadow(_ ctx: inout GraphicsContext) {
        guard snapshot.ballVisible else { return }
        let b = snapshot.ball.position
        let onTable = abs(b.x) <= Table.halfLength && abs(b.z) <= Table.halfWidth && b.y > 0.02
        let surfaceY = onTable ? 0.0 : Table.floorY
        guard b.y > surfaceY + 0.01, let p = pt(Vec3(b.x, surfaceY, b.z)) else { return }
        let height = max(0, b.y - surfaceY)
        let r = camera.scale(at: b, in: size) * 0.05 * (1 + height * 0.5)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 1.3, y: p.y - r * 0.5, width: r * 2.6, height: r)),
                 with: .color(Color.black.opacity(max(0.1, 0.45 - height * 0.4))))
    }

    private func drawBounceMarks(_ ctx: inout GraphicsContext) {
        for m in bounceMarks {
            let k = min(1, max(0, now.timeIntervalSince(m.created) / m.duration))
            guard let p = pt(Vec3(m.position.x, 0, m.position.z)) else { continue }
            let r = camera.scale(at: m.position, in: size) * (0.03 + 0.12 * easeOut(k))
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r * 0.4, width: r * 2, height: r * 0.8)),
                       with: .color(Color.white.opacity(0.8 * (1 - k))), lineWidth: 2)
        }
    }

    private func drawTimingGuide(_ ctx: inout GraphicsContext) {
        guard showGuide, let h = snapshot.hint else { return }
        let remaining = h.idealTime - snapshot.time
        guard remaining > -0.2, remaining < 0.9, let p = pt(h.position) else { return }
        let unit = camera.scale(at: h.position, in: size)
        let spread = max(0, min(1, remaining / 0.9))
        let r = unit * (0.07 + 0.42 * spread)
        let target = unit * 0.07
        let tint: Color
        let a = abs(remaining)
        if a <= 0.045 { tint = Theme.gold } else if a <= 0.095 { tint = Theme.green } else { tint = Color.white.opacity(0.8) }
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - target, y: p.y - target, width: target * 2, height: target * 2)),
                   with: .color(tint.opacity(0.9)), lineWidth: 2)
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                   with: .color(tint.opacity(remaining < 0 ? max(0, 1 + remaining / 0.2) : 0.85)), lineWidth: 3)
    }

    private func drawBall(_ ctx: inout GraphicsContext) {
        guard snapshot.ballVisible else { return }
        // Trail.
        for (i, p) in trail.enumerated() {
            guard let s = pt(p) else { continue }
            let k = Double(i + 1) / Double(max(1, trail.count))
            let r = camera.scale(at: p, in: size) * 0.032 * CGFloat(0.25 + 0.7 * k)
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(hex: "FFB347").opacity(0.35 * k)))
        }
        let b = snapshot.ball.position
        guard let c = pt(b) else { return }
        let r = max(3.5, camera.scale(at: b, in: size) * 0.045)
        // Glow.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 2, y: c.y - r * 2, width: r * 4, height: r * 4)),
                 with: .radialGradient(Gradient(colors: [Color(hex: "FFB347").opacity(0.45), .clear]),
                                       center: c, startRadius: 0, endRadius: r * 2))
        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [Color(hex: "FFE0A8"), Color(hex: "FF9F1C"), Color(hex: "C26A00")]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.4))
        // Spin marker: a dark band that rotates with the ball.
        let a = ballAngle
        var band = Path()
        band.move(to: CGPoint(x: c.x - cos(a) * r * 0.9, y: c.y - sin(a) * r * 0.9))
        band.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.9, y: c.y + sin(a) * r * 0.9))
        ctx.stroke(band, with: .color(Color.black.opacity(0.55)), lineWidth: max(1, r * 0.18))
        ctx.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.5)), lineWidth: 0.8)
    }
}
