import Foundation

/// Every table-tennis stroke the Watch can recognise.
public enum StrokeKind: String, Codable, CaseIterable, Sendable {
    /// Flat, firm drive.
    case drive
    /// Upward brushing swing (loop): heavy topspin, dips and kicks.
    case topspin
    /// Downward cutting swing: backspin chop/slice, floats and stops.
    case chop
    /// Short, soft backspin touch.
    case push
    /// Fast, hard swing at a high ball.
    case smash
    /// Slow, high, defensive arc.
    case lob
    /// Short compact stroke that uses the opponent's pace.
    case block
    /// Very soft, very short touch.
    case drop
    /// Sharp wrist flick: heavy sidespin that curves in the air.
    case flick

    public var displayName: String {
        switch self {
        case .drive: return "DRIVE"
        case .topspin: return "TOPSPIN"
        case .chop: return "BACKSPIN CHOP"
        case .push: return "PUSH"
        case .smash: return "SMASH"
        case .lob: return "LOB"
        case .block: return "BLOCK"
        case .drop: return "DROP SHOT"
        case .flick: return "SIDESPIN FLICK"
        }
    }

    public var code: String { rawValue.uppercased() }

    /// How to perform it on the Watch (shown in training and help).
    public var howTo: String {
        switch self {
        case .drive: return "A firm, flat swing straight through the ball."
        case .topspin: return "Brush the ball: swing from low to high with a fast wrist."
        case .chop: return "Cut down through the ball: swing from high to low."
        case .push: return "A short, soft downward touch."
        case .smash: return "Swing as hard and fast as you can at a high ball."
        case .lob: return "A slow, big swing upward to send the ball high."
        case .block: return "A tiny, quick stab: let the ball's own pace do the work."
        case .drop: return "A slow, soft, short touch just over the net."
        case .flick: return "A sharp wrist flick across the ball for sidespin."
        }
    }
}

/// Forehand or backhand, from the direction the wrist rotates through the swing.
public enum StrokeSide: String, Codable, CaseIterable, Sendable {
    case forehand
    case backhand
    /// Not enough rotation to tell (compact blocks, drops).
    case either

    public var displayName: String {
        switch self {
        case .forehand: return "FOREHAND"
        case .backhand: return "BACKHAND"
        case .either: return ""
        }
    }
}

/// One recognised stroke with its quality scores.
public struct SwingResult: Codable, Equatable, Sendable {
    public var stroke: StrokeKind
    public var side: StrokeSide
    /// Overall strength, 0...1 (relative to this player's calibrated drive).
    public var power: Double
    /// Estimated wrist speed, m/s.
    public var speed: Double
    /// Spin from the swing path: -1 backspin ... +1 topspin.
    public var topspin: Double
    /// Sidespin: -1 ... +1 (sign follows the wrist's rotation).
    public var sidespin: Double
    public var confidence: Double
    /// Sensor time (unix seconds, Watch clock) of the estimated moment of contact.
    public var timestamp: TimeInterval
    /// Duration of the forward swing, seconds.
    public var duration: Double

    public init(stroke: StrokeKind, side: StrokeSide = .either, power: Double, speed: Double = 0,
                topspin: Double = 0, sidespin: Double = 0, confidence: Double = 1,
                timestamp: TimeInterval = 0, duration: Double = 0.15) {
        self.stroke = stroke
        self.side = side
        self.power = power
        self.speed = speed
        self.topspin = topspin
        self.sidespin = sidespin
        self.confidence = confidence
        self.timestamp = timestamp
        self.duration = duration
    }
}

public struct SwingMeta: Codable, Equatable, Sendable {
    public var confidence: Double
    public var timestamp: TimeInterval

    public init(confidence: Double = 1, timestamp: TimeInterval = 0) {
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

/// High-level input consumed by the game. The Watch, the simulator buttons and
/// the unit tests all produce the same type.
public enum PaddleEvent: Equatable, Sendable {
    case swing(SwingResult)
    /// The upward flick that tosses the ball for a serve.
    case toss(SwingMeta)

    public var code: String {
        switch self {
        case .swing(let s): return s.side == .either ? s.stroke.code : "\(s.side.rawValue.uppercased())_\(s.stroke.code)"
        case .toss: return "TOSS"
        }
    }

    public var confidence: Double {
        switch self {
        case .swing(let s): return s.confidence
        case .toss(let m): return m.confidence
        }
    }

    public var timestamp: TimeInterval {
        switch self {
        case .swing(let s): return s.timestamp
        case .toss(let m): return m.timestamp
        }
    }

    public var swing: SwingResult? {
        if case .swing(let s) = self { return s }
        return nil
    }

    public func withTimestamp(_ t: TimeInterval) -> PaddleEvent {
        switch self {
        case .swing(var s): s.timestamp = t; return .swing(s)
        case .toss(var m): m.timestamp = t; return .toss(m)
        }
    }
}
