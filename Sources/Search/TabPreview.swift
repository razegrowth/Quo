import AppKit
import SwiftUI

// A tab's page beside the column while the pointer rests on its row, as
// Chrome's hover cards: the whole title, the site, and a small picture of
// the page, so ten tabs called "Inbox" tell themselves apart.
//
// Built as HoverTip is: one panel, made once and kept, on the same glass as
// the menus, that never takes the pointer. It comes after a moment, then at
// once while one is up and the pointer runs down the column, and a click,
// a scroll, a key or leaving the app puts it away. The tab you're on has
// none: its page is already in front of you. The picture comes from the
// page's own process (Tab.preview), a sleeping tab's from the one kept for
// waking it, and a tab never opened since last time shows its title alone.

@MainActor
enum TabPreview {
    static let width: CGFloat = 264
    static let pictureHeight: CGFloat = 156
    static let delay: TimeInterval = 0.4
    /// From the row's edge to the card's.
    static let gap: CGFloat = 10

    private static var panel: Panel?
    private static var owner: ObjectIdentifier?
    private static var pending: DispatchWorkItem?
    private static var warmUntil = Date.distantPast
    private static var generation = 0
    private static var monitor: Any?
    private static var resign: NSObjectProtocol?
    /// Pictures taken lately, so running back up the column doesn't ask
    /// every page for a new one.
    private static var pictures: [Tab.ID: (image: NSImage, at: Date)] = [:]
    private static let fresh: TimeInterval = 15
    /// What the card shows, filled in as the picture comes.
    static let shown = Shown()

    /// For the bench: whether a card is up, and for which tab.
    static var showing: Bool { panel?.isVisible == true && panel?.alphaValue ?? 0 > 0 }
    private(set) static var tabID: Tab.ID?

    /// The pointer is on `tab`'s row, `view`: its card beside the row, soon.
    static func want(_ tab: Tab, from view: NSView) {
        pending?.cancel()
        owner = ObjectIdentifier(view)
        let warm = showing || Date() < warmUntil
        // The picture is asked for at once, so it's there when the card is.
        let wanted = tab.id
        if tab.canPreview, picture(for: wanted) == nil {
            tab.preview(width: width) { image in
                MainActor.assumeIsolated {
                    guard let image else { return }
                    pictures[wanted] = (image, Date())
                    if tabID == wanted { shown.picture = image }
                }
            }
        }
        let work = DispatchWorkItem { [weak view, weak tab] in
            MainActor.assumeIsolated {
                guard let view, let tab, view.window != nil, owner == ObjectIdentifier(view) else { return }
                show(tab, beside: view, slide: !warm)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (warm ? 0 : delay), execute: work)
    }

    /// The pointer left `view`, or the row went away.
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
        tabID = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resign { NotificationCenter.default.removeObserver(resign) }
        resign = nil
        guard let panel, panel.isVisible else { return }
        warmUntil = Date().addingTimeInterval(0.5)
        generation += 1
        let mine = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Motion.seconds(0.1)
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

    private static func picture(for id: Tab.ID) -> NSImage? {
        pictures = pictures.filter { Date().timeIntervalSince($0.value.at) < fresh }
        return pictures[id]?.image
    }

    private static func show(_ tab: Tab, beside view: NSView, slide: Bool) {
        guard let window = view.window else { return }
        tabID = tab.id
        shown.title = tab.label
        shown.site = tab.address.flatMap(site)
        shown.hasPicture = tab.canPreview
        shown.picture = picture(for: tab.id)

        let panel = self.panel ?? Panel()
        self.panel = panel
        let size = panel.fit()

        // Beside the row, on the page's side of the column, its top level
        // with the row's: the eye goes straight across from the title.
        let spot = window.convertToScreen(view.convert(view.bounds, to: nil))
        let column = window.frame
        let toRight = spot.midX < column.midX
        var origin = NSPoint(x: toRight ? spot.maxX + gap : spot.minX - gap - size.width,
                             y: spot.maxY - size.height)
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 4), screen.maxX - size.width - 4)
            origin.y = min(max(origin.y, screen.minY + 4), screen.maxY - size.height - 4)
        }

        generation += 1
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        let duration = Motion.seconds(0.14)
        let frame = NSRect(origin: origin, size: size)
        if slide, duration > 0 {
            panel.alphaValue = 0
            panel.setFrame(frame.offsetBy(dx: toRight ? -4 : 4, dy: 0), display: true)
            panel.orderFront(nil)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
            panel.orderFront(nil)
            panel.alphaValue = 1
        }

        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .keyDown]) { event in
                MainActor.assumeIsolated { TabPreview.hide() }
                return event
            }
        }
        if resign == nil {
            resign = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TabPreview.hide() }
            }
        }
    }

    /// The site as people say it: the host without "www.".
    private static func site(_ url: URL) -> String? {
        guard let host = url.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// For the bench: the card as it would be drawn for `tab`, without
    /// showing it, as PNG data.
    static func render(_ tab: Tab, picture: NSImage?) -> Data? {
        let model = Shown()
        model.title = tab.label
        model.site = tab.address.flatMap(site)
        model.hasPicture = tab.canPreview
        model.picture = picture
        let host = NSHostingView(rootView: Card(shown: model).frame(width: width).background(Color(nsColor: .windowBackgroundColor)))
        host.frame.size = host.fittingSize
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    final class Shown: ObservableObject {
        @Published var title = ""
        @Published var site: String?
        @Published var hasPicture = false
        @Published var picture: NSImage?
    }

    /// The card's face: the picture on top, the title and site under it.
    struct Card: View {
        @ObservedObject var shown: Shown

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if shown.hasPicture {
                    ZStack(alignment: .top) {
                        Rectangle().fill(Color.primary.opacity(0.06))
                        if let picture = shown.picture {
                            Image(nsImage: picture)
                                .resizable()
                                .interpolation(.high)
                                .aspectRatio(contentMode: .fill)
                                .frame(width: TabPreview.width, height: TabPreview.pictureHeight, alignment: .top)
                                .transition(.opacity)
                        }
                    }
                    .frame(width: TabPreview.width, height: TabPreview.pictureHeight, alignment: .top)
                    .clipped()
                    .animation(Motion.reduced ? nil : .easeOut(duration: 0.12), value: shown.picture != nil)
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let site = shown.site {
                        Text(site)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: TabPreview.width)
        }
    }

    /// The glass the card sits on, made once and kept.
    private final class Panel: NSPanel {
        private let glass = NSVisualEffectView()
        private let host = NSHostingView(rootView: Card(shown: TabPreview.shown))
        static let corner: CGFloat = 10

        init() {
            super.init(contentRect: NSRect(x: 0, y: 0, width: TabPreview.width, height: 60),
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
            glass.layer?.cornerRadius = Panel.corner
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            glass.layer?.borderWidth = 0.5
            glass.layer?.borderColor = MenuMetrics.edge.cgColor
            glass.maskImage = Panel.rounded(Panel.corner)
            contentView = glass
            glass.addSubview(host)
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }

        /// Its size for what it shows now, laid out to it.
        func fit() -> NSSize {
            host.layoutSubtreeIfNeeded()
            let size = NSSize(width: TabPreview.width, height: ceil(host.fittingSize.height))
            glass.frame = NSRect(origin: .zero, size: size)
            host.frame = glass.bounds
            glass.layer?.borderColor = MenuMetrics.edge.cgColor
            return size
        }

        private static func rounded(_ corner: CGFloat) -> NSImage {
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
}
