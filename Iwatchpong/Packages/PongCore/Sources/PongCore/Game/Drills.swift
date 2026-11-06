import Foundation

/// One ball fed by the ball machine. Positions are world coordinates on the human's half.
public struct BallFeed: Sendable {
    public var speed: Double
    public var spin: SpinSpec
    /// Distance of the bounce from the net, toward the human (positive).
    public var landingDepth: Double
    /// Lateral landing position (world z, + = human's right).
    public var landingZ: Double
    public var arc: Arc

    public init(speed: Double, spin: SpinSpec, landingDepth: Double, landingZ: Double, arc: Arc = .low) {
        self.speed = speed
        self.spin = spin
        self.landingDepth = landingDepth
        self.landingZ = landingZ
        self.arc = arc
    }
}

public enum DrillKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case forehandDrive, backhandDrive, topspinLoop, backspinChop, push, block, smash, lob, drop, flick, serve

    public var id: String { rawValue }
}

/// A training drill: the ball machine feeds a specific kind of ball and the
/// player has to answer it with the right stroke.
public struct DrillSpec: Sendable {
    public var kind: DrillKind
    public var title: String
    public var instruction: String
    /// Strokes that count as a correct answer.
    public var requiredStrokes: Set<StrokeKind>
    /// Required side (nil = either), judged against which side of the table the ball came to.
    public var requiredSide: StrokeSide?
    public var totalBalls: Int
    /// Successes needed for 1, 2 and 3 stars.
    public var starThresholds: [Int]

    private let feedBuilder: @Sendable (Int, inout SeededRNG) -> BallFeed

    public func feed(index: Int, rng: inout SeededRNG) -> BallFeed { feedBuilder(index, &rng) }

    public init(kind: DrillKind, title: String, instruction: String, requiredStrokes: Set<StrokeKind>,
                requiredSide: StrokeSide? = nil, totalBalls: Int = 10, starThresholds: [Int] = [4, 6, 8],
                feed: @escaping @Sendable (Int, inout SeededRNG) -> BallFeed) {
        self.kind = kind
        self.title = title
        self.instruction = instruction
        self.requiredStrokes = requiredStrokes
        self.requiredSide = requiredSide
        self.totalBalls = totalBalls
        self.starThresholds = starThresholds
        feedBuilder = feed
    }

    public func stars(for successes: Int) -> Int {
        starThresholds.filter { successes >= $0 }.count
    }

    public static func spec(for kind: DrillKind) -> DrillSpec {
        switch kind {
        case .forehandDrive:
            return DrillSpec(kind: kind, title: "Forehand Drive",
                             instruction: "Balls come to your forehand side. Hit a flat DRIVE.",
                             requiredStrokes: [.drive], requiredSide: .forehand) { _, rng in
                BallFeed(speed: 8.5, spin: SpinSpec(top: 60), landingDepth: 0.95, landingZ: 0.35 + rng.range(-0.1, 0.15))
            }
        case .backhandDrive:
            return DrillSpec(kind: kind, title: "Backhand Drive",
                             instruction: "Balls come to your backhand side. Hit a flat DRIVE.",
                             requiredStrokes: [.drive], requiredSide: .backhand) { _, rng in
                BallFeed(speed: 8.5, spin: SpinSpec(top: 60), landingDepth: 0.95, landingZ: -0.35 + rng.range(-0.15, 0.1))
            }
        case .topspinLoop:
            return DrillSpec(kind: kind, title: "Topspin Loop",
                             instruction: "Backspin balls need lift. Swing LOW TO HIGH for a TOPSPIN loop.",
                             requiredStrokes: [.topspin]) { _, rng in
                BallFeed(speed: 5.5, spin: SpinSpec(top: -230), landingDepth: 0.85, landingZ: rng.range(-0.3, 0.3))
            }
        case .backspinChop:
            return DrillSpec(kind: kind, title: "Backspin Chop",
                             instruction: "Fast topspin balls. Cut down through the ball: HIGH TO LOW for a CHOP.",
                             requiredStrokes: [.chop, .push]) { _, rng in
                BallFeed(speed: 10.5, spin: SpinSpec(top: 260), landingDepth: 1.0, landingZ: rng.range(-0.3, 0.3))
            }
        case .push:
            return DrillSpec(kind: kind, title: "Push",
                             instruction: "Short backspin balls. A short, soft downward PUSH.",
                             requiredStrokes: [.push, .drop]) { _, rng in
                BallFeed(speed: 5.0, spin: SpinSpec(top: -200), landingDepth: 0.42, landingZ: rng.range(-0.25, 0.25))
            }
        case .block:
            return DrillSpec(kind: kind, title: "Block",
                             instruction: "Fast balls! A tiny, quick BLOCK, no big swing.",
                             requiredStrokes: [.block]) { _, rng in
                BallFeed(speed: 13.5, spin: SpinSpec(top: 160), landingDepth: 1.0, landingZ: rng.range(-0.3, 0.3))
            }
        case .smash:
            return DrillSpec(kind: kind, title: "Smash",
                             instruction: "High balls! Swing as hard and fast as you can: SMASH.",
                             requiredStrokes: [.smash], starThresholds: [3, 5, 7]) { _, rng in
                BallFeed(speed: 6.8, spin: SpinSpec(top: 40), landingDepth: 0.9, landingZ: rng.range(-0.3, 0.3), arc: .high)
            }
        case .lob:
            return DrillSpec(kind: kind, title: "Lob",
                             instruction: "Hard, fast balls. Defend with a slow, high LOB.",
                             requiredStrokes: [.lob]) { _, rng in
                BallFeed(speed: 16, spin: SpinSpec(top: 80), landingDepth: 1.1, landingZ: rng.range(-0.3, 0.3))
            }
        case .drop:
            return DrillSpec(kind: kind, title: "Drop Shot",
                             instruction: "Slow balls. A slow, soft touch: a DROP SHOT just over the net.",
                             requiredStrokes: [.drop]) { _, rng in
                BallFeed(speed: 5.0, spin: SpinSpec(top: -100), landingDepth: 0.50, landingZ: rng.range(-0.25, 0.25))
            }
        case .flick:
            return DrillSpec(kind: kind, title: "Sidespin Flick",
                             instruction: "Short balls. Snap your wrist across the ball: SIDESPIN FLICK.",
                             requiredStrokes: [.flick]) { _, rng in
                BallFeed(speed: 5.0, spin: SpinSpec(top: 0), landingDepth: 0.50, landingZ: rng.range(-0.25, 0.25))
            }
        case .serve:
            return DrillSpec(kind: kind, title: "Serve",
                             instruction: "Flick UP to toss, then swing. Try topspin, backspin and sidespin serves.",
                             requiredStrokes: Set(StrokeKind.allCases), totalBalls: 8, starThresholds: [3, 5, 7]) { _, rng in
                BallFeed(speed: 0, spin: .flat, landingDepth: 0, landingZ: 0)
            }
        }
    }

    public static var all: [DrillSpec] { DrillKind.allCases.map { spec(for: $0) } }
}
