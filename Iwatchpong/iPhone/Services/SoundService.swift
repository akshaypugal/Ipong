import AVFoundation
import Foundation

/// Sound effects synthesised in code: no audio assets to ship or license.
/// Each effect is rendered once into an in-memory WAV and played from a small
/// pool of players so rapid hits can overlap.
final class SoundService {
    enum Effect: CaseIterable {
        case tick, swing, paddle, spinBrush, smash, bounce, net, toss, cue
        case pointWon, pointLost, gameWon, matchWon, matchLost, crowd
    }

    var enabled = true

    private var pools: [Effect: [AVAudioPlayer]] = [:]
    private var cursor: [Effect: Int] = [:]
    private let sampleRate = 22_050.0

    init() {
        configureSession()
        for effect in Effect.allCases {
            guard let data = render(effect) else { continue }
            var players: [AVAudioPlayer] = []
            for _ in 0..<3 {
                if let p = try? AVAudioPlayer(data: data) {
                    p.prepareToPlay()
                    players.append(p)
                }
            }
            pools[effect] = players
        }
    }

    func play(_ effect: Effect, volume: Float = 1) {
        guard enabled, let players = pools[effect], !players.isEmpty else { return }
        let i = (cursor[effect] ?? 0) % players.count
        cursor[effect] = i + 1
        let p = players[i]
        p.currentTime = 0
        p.volume = volume
        p.play()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: Synthesis

    private func render(_ effect: Effect) -> Data? {
        switch effect {
        case .tick:
            return wav(duration: 0.1) { t in self.sine(1_000, t) * self.env(t, 0.1, attack: 0.002) * 0.45 }
        case .cue:
            return wav(duration: 0.07) { t in self.sine(1_400, t) * self.env(t, 0.07, attack: 0.002) * 0.3 }
        case .swing:
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 0.16) { t in
                let noise = Double.random(in: -1...1, using: &rng)
                return noise * self.env(t, 0.16, attack: 0.05) * 0.22 * (1 - t / 0.16)
            }
        case .paddle:
            // The classic "tok": a short resonant click.
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 0.09) { t in
                let click = Double.random(in: -1...1, using: &rng) * exp(-t * 180)
                return (self.sine(1_450, t) * exp(-t * 55) * 0.8 + click * 0.5) * 0.85
            }
        case .spinBrush:
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 0.13) { t in
                let noise = Double.random(in: -1...1, using: &rng)
                return (noise * exp(-t * 28) * 0.55 + self.sine(1_150, t) * exp(-t * 60) * 0.5) * 0.8
            }
        case .smash:
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 0.2) { t in
                let click = Double.random(in: -1...1, using: &rng) * exp(-t * 90)
                let high: Double = self.sine(900, t) * exp(-t * 30) * 0.9
                let low: Double = self.sine(220, t) * exp(-t * 18) * 0.7
                let sum: Double = high + low + click * 0.6
                return sum * 0.95
            }
        case .bounce:
            return wav(duration: 0.07) { t in self.sine(780, t) * exp(-t * 70) * 0.7 }
        case .net:
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 0.08) { t in Double.random(in: -1...1, using: &rng) * exp(-t * 50) * 0.35 }
        case .toss:
            return wav(duration: 0.18) { t in self.sine(500 + 900 * t, t) * self.env(t, 0.18, attack: 0.01) * 0.3 }
        case .pointWon:
            return wav(duration: 0.45) { t in
                let f = t < 0.12 ? 660.0 : (t < 0.24 ? 880.0 : 1_100.0)
                return (self.sine(f, t) + 0.3 * self.sine(f * 2, t)) * exp(-t * 4) * 0.45
            }
        case .pointLost:
            return wav(duration: 0.4) { t in
                let f = t < 0.15 ? 330.0 : 262.0
                return self.sine(f, t) * exp(-t * 5) * 0.45
            }
        case .gameWon:
            return wav(duration: 0.9) { t in
                let notes: [Double] = [523, 659, 784, 1_046]
                let idx = min(notes.count - 1, Int(t / 0.18))
                let local = t - Double(idx) * 0.18
                return (self.sine(notes[idx], t) + 0.3 * self.sine(notes[idx] * 2, t)) * exp(-local * 3.5) * 0.5
            }
        case .matchWon:
            return wav(duration: 1.5) { t in
                let notes: [Double] = [523, 659, 784, 1_046, 784, 1_046, 1_318]
                let idx = min(notes.count - 1, Int(t / 0.2))
                let local = t - Double(idx) * 0.2
                return (self.sine(notes[idx], t) + 0.35 * self.sine(notes[idx] * 2, t)) * exp(-local * 3) * 0.5
            }
        case .matchLost:
            return wav(duration: 1.1) { t in
                let notes: [Double] = [392, 349, 311, 262]
                let idx = min(notes.count - 1, Int(t / 0.25))
                let local = t - Double(idx) * 0.25
                return self.sine(notes[idx], t) * exp(-local * 2.5) * 0.5
            }
        case .crowd:
            var rng = SystemRandomNumberGenerator()
            return wav(duration: 1.0) { t in
                let swell = sin(Double.pi * min(1, t / 1.0))
                return Double.random(in: -1...1, using: &rng) * swell * 0.22
            }
        }
    }

    private func sine(_ hz: Double, _ t: Double) -> Double { sin(2 * Double.pi * hz * t) }

    private func env(_ t: Double, _ duration: Double, attack: Double) -> Double {
        let a = min(1, t / attack)
        let r = min(1, (duration - t) / 0.03)
        return max(0, min(a, r))
    }

    /// Renders mono 16-bit PCM and wraps it in a WAV container.
    private func wav(duration: Double, generator: (Double) -> Double) -> Data? {
        let count = Int(duration * sampleRate)
        guard count > 0 else { return nil }
        var pcm = Data(capacity: count * 2)
        for i in 0..<count {
            let t = Double(i) / sampleRate
            let v = max(-1, min(1, generator(t)))
            var s = Int16(v * 32_000).littleEndian
            withUnsafeBytes(of: &s) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { header.append(contentsOf: $0) } }
        header.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        u32(16)
        u16(1)
        u16(1)
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate) * 2)
        u16(2)
        u16(16)
        header.append(contentsOf: Array("data".utf8))
        u32(UInt32(pcm.count))
        return header + pcm
    }
}
