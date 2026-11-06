import Foundation

/// The buttons of Developer Controller Mode: every stroke the Watch can produce.
public enum SimulatedInput: String, CaseIterable, Sendable {
    case toss
    case forehandDrive, backhandDrive
    case forehandTopspin, backhandTopspin
    case chop, push
    case smash, lob
    case block, drop
    case flickLeft, flickRight

    public var title: String {
        switch self {
        case .toss: return "TOSS"
        case .forehandDrive: return "FH DRIVE"
        case .backhandDrive: return "BH DRIVE"
        case .forehandTopspin: return "FH LOOP"
        case .backhandTopspin: return "BH LOOP"
        case .chop: return "CHOP"
        case .push: return "PUSH"
        case .smash: return "SMASH"
        case .lob: return "LOB"
        case .block: return "BLOCK"
        case .drop: return "DROP"
        case .flickLeft: return "FLICK L"
        case .flickRight: return "FLICK R"
        }
    }

    /// Keyboard shortcut in the Simulator.
    public var shortcutKey: Character {
        switch self {
        case .toss: return " "
        case .forehandDrive: return "f"
        case .backhandDrive: return "b"
        case .forehandTopspin: return "t"
        case .backhandTopspin: return "y"
        case .chop: return "c"
        case .push: return "p"
        case .smash: return "s"
        case .lob: return "l"
        case .block: return "k"
        case .drop: return "d"
        case .flickLeft: return "q"
        case .flickRight: return "e"
        }
    }
}

/// Produces `PaddleEvent`s exactly like the Watch would, from button presses.
/// The game cannot tell the difference, so the whole game can be developed and
/// tested without hardware.
public struct SimulatedPaddle: Sendable {
    public var rng: SeededRNG
    /// Mean swing power (0...1).
    public var power: Double
    public var jitter: Double

    public init(seed: UInt64 = 1, power: Double = 0.6, jitter: Double = 0.08) {
        rng = SeededRNG(seed: seed)
        self.power = power
        self.jitter = jitter
    }

    public mutating func event(for input: SimulatedInput, at time: TimeInterval = Date().timeIntervalSince1970) -> PaddleEvent {
        switch input {
        case .toss:
            return .toss(SwingMeta(confidence: 1, timestamp: time))
        case .forehandDrive: return .swing(swing(.drive, .forehand, topspin: 0.1, at: time))
        case .backhandDrive: return .swing(swing(.drive, .backhand, topspin: 0.1, at: time))
        case .forehandTopspin: return .swing(swing(.topspin, .forehand, topspin: 0.7, at: time))
        case .backhandTopspin: return .swing(swing(.topspin, .backhand, topspin: 0.7, at: time))
        case .chop: return .swing(swing(.chop, .forehand, topspin: -0.7, at: time))
        case .push: return .swing(swing(.push, .either, topspin: -0.6, power: 0.3, at: time))
        case .smash: return .swing(swing(.smash, .forehand, topspin: 0.2, power: 0.95, at: time))
        case .lob: return .swing(swing(.lob, .forehand, topspin: 0.5, power: 0.45, at: time))
        case .block: return .swing(swing(.block, .either, topspin: 0, power: 0.3, at: time))
        case .drop: return .swing(swing(.drop, .either, topspin: -0.2, power: 0.2, at: time))
        case .flickLeft: return .swing(swing(.flick, .forehand, topspin: 0.1, sidespin: -0.8, at: time))
        case .flickRight: return .swing(swing(.flick, .forehand, topspin: 0.1, sidespin: 0.8, at: time))
        }
    }

    public mutating func swing(_ stroke: StrokeKind, _ side: StrokeSide, topspin: Double = 0, sidespin: Double = 0,
                               power p: Double? = nil, at time: TimeInterval = 0) -> SwingResult {
        let pw = clamp((p ?? power) + rng.range(-jitter, jitter))
        return SwingResult(stroke: stroke, side: side, power: pw, speed: 2 + 5 * pw, topspin: topspin, sidespin: sidespin,
                           confidence: 1, timestamp: time, duration: 0.15)
    }
}
