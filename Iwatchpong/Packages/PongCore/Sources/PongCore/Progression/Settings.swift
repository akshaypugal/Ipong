import Foundation

/// How long a match is.
public enum MatchFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    /// One game to 7: about 3 minutes.
    case quick
    /// Best of 3 games to 11 (official rules).
    case standard
    /// Best of 5 games to 11.
    case full

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .quick: return "QUICK"
        case .standard: return "STANDARD"
        case .full: return "FULL"
        }
    }

    public var subtitle: String {
        switch self {
        case .quick: return "1 game to 7"
        case .standard: return "Best of 3 to 11"
        case .full: return "Best of 5 to 11"
        }
    }

    public func config(firstServer: Player = .human) -> MatchConfig {
        var c = MatchConfig()
        c.firstServer = firstServer
        switch self {
        case .quick:
            c.pointsPerGame = 7
            c.gamesToWin = 1
        case .standard:
            c.pointsPerGame = 11
            c.gamesToWin = 2
        case .full:
            c.pointsPerGame = 11
            c.gamesToWin = 3
        }
        return c
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    /// The Watch ticks the moment it detects a swing.
    public var localWatchHaptics: Bool
    public var developerMode: Bool
    /// Developer Controller Mode: on-screen buttons replace the Watch.
    public var simulatedController: Bool
    public var showLatency: Bool
    /// Show the timing ring on the table.
    public var showTimingGuide: Bool
    /// Forehand on the right side of the table.
    public var rightHanded: Bool
    public var matchFormat: MatchFormat
    public var swingConfig: SwingConfig

    public init(soundEnabled: Bool = true, hapticsEnabled: Bool = true, localWatchHaptics: Bool = true,
                developerMode: Bool = false, simulatedController: Bool = false, showLatency: Bool = false,
                showTimingGuide: Bool = true, rightHanded: Bool = true, matchFormat: MatchFormat = .standard,
                swingConfig: SwingConfig = .default) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.localWatchHaptics = localWatchHaptics
        self.developerMode = developerMode
        self.simulatedController = simulatedController
        self.showLatency = showLatency
        self.showTimingGuide = showTimingGuide
        self.rightHanded = rightHanded
        self.matchFormat = matchFormat
        self.swingConfig = swingConfig
    }

    private enum CodingKeys: String, CodingKey {
        case soundEnabled, hapticsEnabled, localWatchHaptics, developerMode, simulatedController
        case showLatency, showTimingGuide, rightHanded, matchFormat, swingConfig
    }

    /// Tolerant decoding: missing or unreadable keys fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = (try? c.decode(Bool.self, forKey: .soundEnabled)) ?? true
        hapticsEnabled = (try? c.decode(Bool.self, forKey: .hapticsEnabled)) ?? true
        localWatchHaptics = (try? c.decode(Bool.self, forKey: .localWatchHaptics)) ?? true
        developerMode = (try? c.decode(Bool.self, forKey: .developerMode)) ?? false
        simulatedController = (try? c.decode(Bool.self, forKey: .simulatedController)) ?? false
        showLatency = (try? c.decode(Bool.self, forKey: .showLatency)) ?? false
        showTimingGuide = (try? c.decode(Bool.self, forKey: .showTimingGuide)) ?? true
        rightHanded = (try? c.decode(Bool.self, forKey: .rightHanded)) ?? true
        matchFormat = (try? c.decode(MatchFormat.self, forKey: .matchFormat)) ?? .standard
        swingConfig = (try? c.decode(SwingConfig.self, forKey: .swingConfig)) ?? .default
    }
}
