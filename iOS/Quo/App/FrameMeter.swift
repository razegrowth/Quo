import QuartzCore
import UIKit

/// With QUO_TRACE set, counts each second's frames and the ones that came
/// late (a gap of more than one and a half frames), and logs them, so a
/// change to how something moves can be measured rather than eyeballed.
@MainActor
final class FrameMeter: NSObject {
    static let shared = FrameMeter()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var late = 0
    private var worst: CFTimeInterval = 0

    func start() {
        guard Trace.on, link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let expected = link.targetTimestamp - link.timestamp
        if last > 0 {
            let gap = now - last
            frames += 1
            if gap > expected * 1.5 {
                late += 1
                // Two or more frames missed in a row: logged on its own.
                if gap > expected * 2.5 { NSLog("QUOTRACE hitch %.0fms", gap * 1000) }
            }
            worst = max(worst, gap)
        }
        last = now
        if windowStart == 0 { windowStart = now }
        if now - windowStart >= 1 {
            if late > 0 || frames < Int(0.9 / max(expected, 0.001)) {
                NSLog("QUOFPS frames=%d late=%d worst=%.0fms", frames, late, worst * 1000)
            }
            windowStart = now
            frames = 0
            late = 0
            worst = 0
        }
    }
}
