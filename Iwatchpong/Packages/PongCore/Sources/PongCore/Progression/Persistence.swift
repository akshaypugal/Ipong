import Foundation

/// Local, offline persistence for the player profile.
public protocol ProfileStore: AnyObject {
    /// Returns nil when nothing is saved yet (or the data was unreadable).
    func load() -> PongProfile?
    func save(_ profile: PongProfile) throws
}

public final class InMemoryProfileStore: ProfileStore {
    public private(set) var stored: PongProfile?
    public private(set) var saveCount = 0

    public init(_ initial: PongProfile? = nil) { stored = initial }

    public func load() -> PongProfile? { stored }

    public func save(_ profile: PongProfile) throws {
        stored = profile
        saveCount += 1
    }
}

/// JSON file in Application Support. Writes are atomic; an unreadable file is
/// moved aside (never silently deleted) and the app starts fresh.
public final class FileProfileStore: ProfileStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("WristPong", isDirectory: true).appendingPathComponent("profile.json")
    }

    public func load() -> PongProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(PongProfile.self, from: data)
        } catch {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("profile.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            return nil
        }
    }

    public func save(_ profile: PongProfile) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }
}
