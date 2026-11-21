import AppKit
import SwiftUI

// A tab's whole title, under it, when the row had to cut it short with "…".
//
// macOS's own tooltip came after a second, in a small yellow-grey box in the
// system's font, and went on its own clock. This one is the browser's: on
// the same glass and corners as the site card and the menus, in a size
// that reads next to the column's titles, in after a third of a second on
// the quick ease-out with a short slide, and at once while one is already
// up, as the pointer runs down the column. A click, a scroll or a key puts
// it away. It never takes the pointer: what is under it is still clicked.

@MainActor
enum HoverTip {
    private static var panel: TipPanel?
    /// The view the tip is for, or about to be: a row the pointer has left
    /// lets go of the tip only if it is still that row's.
    private static var owner: ObjectIdentifier?
    private static var pending: DispatchWorkItem?
    /// Just after one went: the next comes at once, as the pointer moves on.
    private static var warmUntil = Date.distantPast
    /// Counts each showing and hiding, so a fade that ends after the next
    /// tip came up doesn't take it down.
    private static var generation = 0
    private static var monitor: Any?
    private static var resign: NSObjectProtocol?

    static let delay: TimeInterval = 0.35
    static let font = NSFont.systemFont(ofSize: 13)
    static let widest: CGFloat = 420
    static let padding = NSSize(width: 10, height: 6)

    /// The pointer is on `view`, whose text is cut short: `text` under it, soon.
    static func want(_ text: String, from view: NSView) {
        pending?.cancel()
        owner = ObjectIdentifier(view)
        let warm = panel?.isVisible == true || Date() < warmUntil
        let work = DispatchWorkItem { [weak view] in
            guard let view, view.window != nil, owner == ObjectIdentifier(view) else { return }
            show(text, under: view, slide: !warm)
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warm ? 0 : delay), execute: work)
    }

    /// The pointer left `view`, or it went away.
    static func drop(from view: NSView) {
        guard owner == ObjectIdentifier(view) else { return }
        owner = nil
        pending?.cancel()
        pending = nil
        hide()
    }

    static func hide() {
        pending?.cancel()
        pending = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        guard let panel, panel.isVisible else { return }
        warmUntil = Date().addingTimeInterval(0.5)
        generation += 1
        let mine = generation
        let duration = Motion.seconds(0.1)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = Motion.outCurve
            panel.animator().alphaValue = 0
        } completionHandler: {
            MainActor.assumeIsolated {
                guard mine == generation else { return }
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
        }
    }

    private static func show(_ text: String, under view: NSView, slide: Bool) {
        guard let window = view.window else { return }
        // The text's own width, up to the widest a tip goes; longer ones wrap.
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let natural = ceil((text as NSString).size(withAttributes: attributes).width)
        let line = min(natural + 1, widest - padding.width * 2)
        let tall = ceil((text as NSString).boundingRect(with: NSSize(width: line, height: 1000),
                                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                         attributes: attributes).height)
        let size = NSSize(width: line + padding.width * 2, height: tall + padding.height * 2)

        let panel = self.panel ?? TipPanel()
        self.panel = panel
        panel.show(text, size: size)

        // Under the title, its text lined up with the title's, so the eye
        // reads straight down from the cut to the rest of it.
        let spot = window.convertToScreen(view.convert(view.bounds, to: nil))
        var origin = NSPoint(x: spot.minX - padding.width, y: spot.minY - 8 - size.height)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
            if origin.y < screen.minY + 4 { origin.y = spot.maxY + 8 }
        }

        generation += 1
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        let duration = Motion.seconds(0.14)
        if slide, duration > 0 {
            panel.alphaValue = 0
            panel.setFrame(NSRect(origin: NSPoint(x: origin.x, y: origin.y + 3), size: size), display: true)
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(NSRect(origin: origin, size: size), display: true)
            }
        } else {
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            panel.orderFront(nil)
            panel.alphaValue = 1
        }

        // Anything done puts it away: the click was on the row, the scroll
        // moved the row from under it, the key went somewhere else.
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { event in
                MainActor.assumeIsolated { HoverTip.hide() }
                return event
            }
        }
        if resign == nil {
            resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { HoverTip.hide() }
            }
        }
    }

    /// The glass the tip sits on, made once and kept.
    private final class TipPanel: NSPanel {
        private let label = NSTextField(wrappingLabelWithString: "")
        private let glass = NSVisualEffectView()

        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                       styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = true
            ignoresMouseEvents = true
            hidesOnDeactivate = true
            isReleasedWhenClosed = false
            collectionBehavior = [.transient, .ignoresCycle]

            glass.material = .menu
            glass.state = .active
            glass.wantsLayer = true
            glass.layer?.cornerRadius = HoverTip.corner
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            glass.layer?.borderWidth = 0.5
            glass.layer?.borderColor = MenuMetrics.edge.cgColor
            glass.maskImage = HoverTip.rounded(HoverTip.corner)
            contentView = glass

            label.font = HoverTip.font
            label.textColor = .labelColor
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            label.isSelectable = false
            glass.addSubview(label)
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        func show(_ text: String, size: NSSize) {
            label.stringValue = text
            glass.frame = NSRect(origin: .zero, size: size)
            // A label insets its text by two points a side: given them
            // back, it wraps where the measure did.
            label.frame = NSRect(x: HoverTip.padding.width - 2, y: HoverTip.padding.height,
                                 width: size.width - HoverTip.padding.width * 2 + 4,
                                 height: size.height - HoverTip.padding.height * 2)
            // The edge follows light and dark as the menus' does.
            glass.layer?.borderColor = MenuMetrics.edge.cgColor
        }
    }

    static let corner: CGFloat = 8

    /// A rounded rectangle that stretches to any size, its corners kept: the
    /// material behind a window ignores a layer's corners, a mask doesn't.
    fileprivate static func rounded(_ corner: CGFloat) -> NSImage {
        let side = corner * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: corner, yRadius: corner).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: corner, left: corner, bottom: corner, right: corner)
        image.resizingMode = .stretch
        return image
    }
}

/// Where a tip hangs from: a view under the title that is never hit itself.
final class TipSpot {
    weak var view: NSView?
}

struct TipAnchor: NSViewRepresentable {
    let spot: TipSpot

    func makeNSView(context: Context) -> NSView {
        let view = Inert()
        spot.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { spot.view = view }

    private final class Inert: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
