import Foundation
import QuartzCore

/// 60/120 Hz frame callback with the elapsed time since the last frame.
final class DisplayLinkDriver: NSObject {
    var onFrame: ((Double) -> Void)?

    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0

    func start() {
        stop()
        last = 0
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.preferredFramesPerSecond = 60
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    deinit { stop() }

    @objc private func tick(_ l: CADisplayLink) {
        let now = l.timestamp
        let dt = last == 0 ? 1.0 / 60.0 : now - last
        last = now
        onFrame?(min(dt, 0.1))
    }
}
