import Foundation
@testable import PongCore

/// Synthetic wrist motion for a table-tennis swing: backswing, forward stroke,
/// follow-through, with noise. The world frame has x as the heading, z up.
struct SwingSynth {
    var time = 1_000.0
    var rate = 100.0
    var noise = 0.02
    var rng = SeededRNG(seed: 21)
    var gravity = Vec3(0, 0, -1)

    private mutating func noiseVec() -> Vec3 {
        Vec3(rng.gaussian(sigma: noise), rng.gaussian(sigma: noise), rng.gaussian(sigma: noise))
    }

    mutating func sample(accel: Vec3 = .zero, gyro: Vec3 = .zero) -> MotionSample {
        let a = accel + noiseVec()
        let s = MotionSample(timestamp: time, userAccel: a, gravity: gravity, rotationRate: gyro + noiseVec(), worldAccel: a)
        time += 1 / rate
        return s
    }

    mutating func rest(_ seconds: Double) -> [MotionSample] {
        (0..<Int(seconds * rate)).map { _ in sample() }
    }

    /// Half-sine lobe along `direction` with a yaw-rate envelope (and optional extra gyro).
    mutating func lobe(direction: Vec3, peak: Double, duration: Double, yaw: Double = 0, extraGyro: Vec3 = .zero) -> [MotionSample] {
        let n = max(2, Int(duration * rate))
        let d = direction.normalized
        var out: [MotionSample] = []
        for k in 0..<n {
            let env = sin(Double.pi * (Double(k) + 0.5) / Double(n))
            out.append(sample(accel: d * (peak * env), gyro: Vec3(0, 0, yaw * env) + extraGyro * env))
        }
        return out
    }

    /// Unit direction with the given vertical share (heading +x).
    static func direction(vertical vf: Double) -> Vec3 {
        let h = (max(0, 1 - vf * vf)).squareRoot()
        return Vec3(h, 0, vf)
    }

    /// A complete stroke.
    /// - Parameters:
    ///   - peak: forward-lobe peak (g)
    ///   - duration: forward-lobe duration (s)
    ///   - vertical: vertical share of the swing direction (+ up = topspin, - down = backspin)
    ///   - yaw: peak wrist yaw rate, signed (+ = counter-clockwise from above = forehand for a right-hander)
    mutating func stroke(peak: Double, duration: Double = 0.14, vertical: Double = 0, yaw: Double = 0,
                         extraGyro: Vec3 = .zero, backswing: Bool = true, followThrough: Bool = true) -> [MotionSample] {
        let fwd = SwingSynth.direction(vertical: vertical)
        var out: [MotionSample] = []
        if backswing {
            out += lobe(direction: -fwd, peak: peak * 0.4, duration: duration * 1.6, yaw: -yaw * 0.5)
            out += rest(0.04)
        }
        out += lobe(direction: fwd, peak: peak, duration: duration, yaw: yaw, extraGyro: extraGyro)
        if followThrough {
            out += lobe(direction: -fwd, peak: peak * 0.5, duration: duration * 1.4, yaw: -yaw * 0.3)
        }
        return out
    }
}

/// Runs samples through a recogniser one at a time, recording the wall time each event appeared.
func recognize(_ samples: [MotionSample], recognizer: SwingRecognizer = SwingRecognizer()) -> [(event: PaddleEvent, emittedAt: Double)] {
    var out: [(PaddleEvent, Double)] = []
    for s in samples {
        for e in recognizer.process(s) { out.append((e, s.timestamp)) }
    }
    return out
}
