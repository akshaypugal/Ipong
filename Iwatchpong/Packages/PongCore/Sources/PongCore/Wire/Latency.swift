import Foundation

/// Estimates the offset between the Watch clock and the iPhone clock with
/// ping/pong round trips (NTP-style), so one-way latency can be measured.
public struct ClockSync: Sendable {
    /// watchClock - phoneClock, in seconds.
    public private(set) var offset: Double = 0
    public private(set) var bestRoundTrip: Double = .infinity
    public private(set) var sampleCount = 0

    public init() {}

    public var isSynced: Bool { sampleCount > 0 }

    /// - Parameters:
    ///   - pingSent: phone time when the ping left.
    ///   - watchTime: watch time when it answered.
    ///   - pongReceived: phone time when the answer arrived.
    public mutating func addSample(pingSent: Double, watchTime: Double, pongReceived: Double) {
        let rtt = pongReceived - pingSent
        guard rtt >= 0 else { return }
        let estimate = watchTime - (pingSent + rtt / 2)
        if sampleCount == 0 || rtt < bestRoundTrip {
            offset = estimate
            bestRoundTrip = rtt
        } else if rtt <= bestRoundTrip * 1.5 {
            offset = offset * 0.8 + estimate * 0.2
        }
        sampleCount += 1
    }

    public func toPhoneTime(_ watchTime: Double) -> Double { watchTime - offset }
}

public struct LatencyStats: Equatable, Sendable {
    public var last: Double = 0
    public var average: Double = 0
    public var minimum: Double = 0
    public var maximum: Double = 0
    public var p95: Double = 0
    public var count: Int = 0
    public init() {}
}

/// Rolling latency statistics in milliseconds.
public struct LatencyTracker: Sendable {
    public var capacity: Int
    private var samples: [Double] = []
    private var total = 0

    public init(capacity: Int = 100) { self.capacity = capacity }

    public mutating func record(milliseconds ms: Double) {
        guard ms.isFinite else { return }
        samples.append(max(0, ms))
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        total += 1
    }

    public mutating func reset() {
        samples.removeAll()
        total = 0
    }

    public var stats: LatencyStats {
        var s = LatencyStats()
        guard !samples.isEmpty else { return s }
        let sorted = samples.sorted()
        s.last = samples[samples.count - 1]
        s.average = samples.reduce(0, +) / Double(samples.count)
        s.minimum = sorted[0]
        s.maximum = sorted[sorted.count - 1]
        s.p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        s.count = total
        return s
    }
}
