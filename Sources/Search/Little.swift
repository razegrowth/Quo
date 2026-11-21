import SwiftUI
import WebKit

// A small window for a link from another app: the page, and a thin line over
// it with the site, Open in Search and nothing else — to read and close, or
// to keep. Arc calls it Little Arc; the idea came to Search as #227.
//
// On for a new install, in Settings › General; an install from before it
// was the default keeps it off, and a link from Mail opens in the browser's
// window, as it always did, until it is turned on (see
// Preferences.settleLittleLinks).
//
// The page is a tab of its own, as a peek is (see Peek.swift), only in a
// window of its own: Open in Search moves it into the browser's row, where
// the space on screen is, loaded as it is and nothing loaded twice.
//
// It comes alone. The browser's window stays where it was — closed, in the
// Dock, behind another app — until Open in Search asks for it (see
// Links.little).

@MainActor
final class LittleWindow: NSObject, NSWindowDelegate {
    /// Open ones, each until it is closed or kept.
    private static var open: [LittleWindow] = []

    let tab: Tab
    /// The browser it was opened for: the planet for ⌃Tab when no window is in front.
    private weak var browser: Browser?
    private let window: NSWindow
    private var kept = false
    /// Placed a step down from another one, not where anybody put it: the
    /// place is not worth keeping until it is moved or resized. Closed in
    /// any order, a stack of them walked the kept place across the screen.
    private var cascaded = false
    /// What it says for a moment at its foot: "Address copied".
    private let note = LittleNote()
    /// Its size before it has been given one: room to read a page as it is
    /// laid out on a laptop, and never more than most of the screen.
    static var firstSize: NSSize {
        let room = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        return NSSize(width: min(1120, (room.width * 0.82).rounded()), height: min(780, (room.height * 0.86).rounded()))
    }

    /// Where its size and place are kept. A new name with the larger first
    /// size, so a place kept at the old, smaller one doesn't hold it there.
    static let frameKey = "little.frame.2"

    /// No smaller than this, by hand or from a kept place.
    private static let smallest = NSSize(width: 420, height: 320)

    /// A link from another app, in a small window in front of it.
    /// `front: false` makes it without showing it — for the bench, which
    /// must never put a window on screen.
    static func show(_ url: URL, for browser: Browser, front: Bool = true) {
        let tab = Tab(configuration: Web.configuration(space: browser.spaceID))
        browser.prepare(tab)
        tab.go(to: url)
        show(tab, for: browser, front: front)
    }

    /// A page already made for it: a new window a small window's page asked
    /// for (see Browser's createWebViewWith), which WebKit loads itself.
    static func show(_ tab: Tab, for browser: Browser, front: Bool = true) {
        // Not in the row until kept: extensions are told of it here, as of a
        // peek (see Extensions.openedAside).
        if #available(macOS 15.4, *) { Extensions.shared.openedAside(tab) }
        let little = LittleWindow(tab: tab, browser: browser)
        // A step down and in from the newest one on screen, so that five
        // links from Mail are five windows you can see are there, not one
        // on top of four.
        if let last = open.last(where: { $0.window.isVisible }) {
            little.window.cascadeTopLeft(from: last.window.cascadeTopLeft(from: .zero))
            little.cascaded = true
        }
        open.append(little)
        watchKeys()
        watch()
        // Never a test run's in front: a probe started hidden stays off every screen.
        guard front, !Store.testing else { return }
        little.popIn()
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    // MARK: - coming and going

    /// Set while it goes, so the close the animation ends with isn't held.
    private var going = false

    /// Its page and frame grown from a little smaller, on a spring, as it
    /// fades in: Arc's Little Arc. Only the content grows; the window is its
    /// full size from the first frame, so the page lays out once. Its shadow
    /// comes once the content fills it, or it would ring an empty frame.
    /// With Reduce Motion, a fade.
    private func popIn() {
        guard let view = window.contentView else { return window.makeKeyAndOrderFront(nil) }
        view.wantsLayer = true
        window.alphaValue = 0
        let grows = !Motion.reduced
        if grows {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
        }
        window.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = grows ? 0.16 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
        guard grows, let layer = view.layer else { return }
        let spring = CASpringAnimation(keyPath: "transform")
        // From well short of its size, past it a touch, and back: Arc's spring.
        spring.fromValue = LittleWindow.scaled(0.86, in: view.bounds)
        spring.toValue = CATransform3DIdentity
        spring.mass = 1
        spring.stiffness = 290
        spring.damping = 21
        spring.initialVelocity = 0
        spring.duration = spring.settlingDuration
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, !going else { return }
            window.backgroundColor = NSColor.windowBackgroundColor
            window.isOpaque = true
            window.hasShadow = true
            window.invalidateShadow()
        }
        layer.add(spring, forKey: "littleIn")
        CATransaction.commit()
    }

    /// A scale about the middle of `bounds`, for a layer whose anchor is its corner.
    private static func scaled(_ scale: CGFloat, in bounds: CGRect) -> CATransform3D {
        var t = CATransform3DMakeTranslation(bounds.midX, bounds.midY, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        return CATransform3DTranslate(t, -bounds.midX, -bounds.midY, 0)
    }

    /// Closed with its button, ⌘W or Escape: it shrinks a little as it
    /// fades, then goes. Kept into the browser, it simply goes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !going, !Store.testing, !Motion.reduced, window.isVisible, let layer = window.contentView?.layer else { return true }
        going = true
        window.hasShadow = false
        window.isOpaque = false
        window.backgroundColor = .clear
        let shrink = CABasicAnimation(keyPath: "transform")
        shrink.fromValue = CATransform3DIdentity
        shrink.toValue = LittleWindow.scaled(0.96, in: window.contentView?.bounds ?? .zero)
        shrink.duration = 0.14
        shrink.timingFunction = Motion.outCurve
        shrink.fillMode = .forwards
        shrink.isRemovedOnCompletion = false
        layer.add(shrink, forKey: "littleOut")
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = Motion.outCurve
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.window.close() }
        })
        return false
    }

    /// The small windows open now, newest last — for the bench.
    static var all: [LittleWindow] { open }

    /// Closed as its button closes it — for the bench.
    func close() { window.performClose(nil) }

    /// The picture that flies into the browser when it's kept, for the bench.
    func flightPicture(to path: String, then done: @escaping (Bool) -> Void) {
        guard let page = tab.built else { return done(false) }
        LittleFlight.picture(of: window, page: page) { image in
            guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return done(false) }
            done((try? png.write(to: URL(fileURLWithPath: path))) != nil)
        }
    }

    /// A picture of it drawn off screen, for the bench: the window is never
    /// shown on a test run.
    func picture(to path: String) -> Bool {
        guard let view = window.contentView else { return false }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        return (try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))) != nil
    }

    /// Its window, for the bench to press keys on, and what its foot says.
    var windowNumber: Int { window.windowNumber }
    var said: String? { note.text }

    /// The small window a key was pressed in, if it was one.
    static func owning(_ window: NSWindow?) -> LittleWindow? {
        guard let window else { return nil }
        return open.first { $0.window === window }
    }

    /// The small window a tab is the page of, if it is one's.
    static func holding(_ id: Tab.ID) -> LittleWindow? {
        open.first { $0.tab.id == id }
    }

    /// The small windows' tabs as the Mac stacks their windows, the one in
    /// front first; any never shown after them, newest first. The browser's
    /// switcher shows them in this order, beside its tabs.
    static var stacked: [Tab.ID] {
        // The Mac lists windows it has never shown too, oldest first: only
        // the ones on screen have a place in the stack.
        let stack = NSApp.orderedWindows.filter(\.isVisible)
        let depth = { (little: LittleWindow) in stack.firstIndex { $0 === little.window } ?? stack.count }
        return open.reversed().enumerated()
            .sorted { (depth($0.element), $0.offset) < (depth($1.element), $1.offset) }
            .map(\.element.tab.id)
    }

    /// ⌃Tab in a small window: the browser's switcher as it looks from
    /// here, the tabs as the planet and the small windows as its moons,
    /// walked from this moon. One for all of them, so the moons' order is
    /// the same whichever one it starts in; it shows over the one it started
    /// in, its home.
    static let switcher = TabSwitcher()

    /// The browser whose tabs are the planet for this gesture: the window
    /// in front, as Open in Search takes.
    private(set) static weak var planet: Browser?

    /// The last one brought forward on a test run, which never puts one
    /// on a screen — for the bench.
    private(set) static var fronted: Tab.ID?

    /// In front, with the keys, as a click on it would leave it.
    func front() {
        guard !Store.testing else { return LittleWindow.fronted = tab.id }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
    }

    /// The card the switcher is on, or the one clicked: a small window
    /// forward, or a tab in its browser window.
    static func commit(picking id: Tab.ID? = nil) {
        guard let target = switcher.finish(picking: id) else { return }
        if let little = holding(target) { little.front() } else { planet?.bringForward(target) }
    }

    /// Letting go of ⌃, and a click while the switcher is up, in whichever
    /// small window it is up in. The browser windows' own monitors hear
    /// these too, and leave them: a small window isn't theirs.
    private static var watching: [Any] = []

    private static func watch() {
        guard watching.isEmpty else { return }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseDown], handler: { event in
            guard switcher.active, let little = owning(event.window), switcher.home == little.tab.id
            else { return event }
            if event.type == .flagsChanged {
                if !ShortcutStore.shared.recentHeld(event.modifierFlags) { commit() }
                return event
            }
            // As in a browser window (Browser.clickTabSwitcher): ⌃ is held,
            // and a ⌃-click is a right-click to AppKit, so the switcher
            // takes the click before any view does.
            guard let height = little.window.contentView?.bounds.height else { return event }
            let at = event.locationInWindow
            return switcher.click(at: CGPoint(x: at.x, y: height - at.y)) { commit(picking: $0) } ? nil : event
        }) {
            watching.append(monitor)
        }
        watching.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { switcher.cancel() } })
    }

    private init(tab: Tab, browser: Browser) {
        self.tab = tab
        self.browser = browser
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LittleWindow.firstSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = Self.smallest
        if let frame = Self.remembered {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        window.delegate = self
        let id = tab.id
        if Shared.prefs.roomyTabs {
            Lights.keep(window, centreX: { _ in LittleView.roomyBar / 2 }, height: { _ in LittleView.roomyBar }) {}
        }
        // Roomy (Appearance › Size): a taller bar, the lights centred in it
        // as the browser's window has them in its strip; Compact keeps the
        // title bar's own.
        let roomy = Shared.prefs.roomyTabs
        window.contentView = NSHostingView(rootView: LittleView(tab: tab, note: note, roomy: roomy,
                                                                place: .of(Browsers.front ?? browser),
                                                                keep: { [weak self] space in self?.keep(in: space) },
                                                                copy: { [weak self] in self?.copy(markdown: false) })
            .overlay {
                TabSwitcherOverlay(
                    switcher: LittleWindow.switcher,
                    tab: { id in LittleWindow.holding(id)?.tab ?? LittleWindow.planet?.tabs.first { $0.id == id } },
                    current: id, host: id,
                    pick: { LittleWindow.commit(picking: $0) }
                )
            })
        // Back from the page it opened on is back to before it opened: a
        // swipe closes it (see PageView.leave).
        tab.leave = { [weak self] in self?.close() }
        // A zoom said at this window's foot, not the browser's behind it,
        // where Browser.prepare pointed it; kept, the tab is prepared again
        // and says it there.
        tab.onZoom = { [weak note] _, value in note?.say("\(Int((value * 100).rounded()))%") }
    }

    /// Its own key monitor. A browser window's (see ContentView.watchKeys)
    /// hands it these too, but a link that launched the app has no browser
    /// window to lend one any more, and ⌘W went on to close a tab in a
    /// window nobody could see.
    private static var keys: Any?

    private static func watchKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            owning(event.window)?.take(event) == true ? nil : event
        }
    }

    /// Its keys, before the browser's: ⌃Tab goes to the other small
    /// windows, ⌘O keeps it, Escape and ⌘W close it, and the page's own
    /// commands — copying its address, reloading it, zooming it — act on
    /// this page, on whatever keys Settings › Shortcuts gives them.
    /// Left to the menus, they acted on the browser's tab, in a window
    /// behind this one or none, and said so there if anywhere. Everything
    /// else is the page's.
    func take(_ event: NSEvent) -> Bool {
        if let combo = KeyCombo(event: event) {
            let keys = ShortcutStore.shared
            if combo == keys.key(for: "tabs.copyAddress") { copy(markdown: false); return true }
            if combo == keys.key(for: "tabs.copyMarkdown") { copy(markdown: true); return true }
            if combo == keys.key(for: "view.reload") { tab.reload(fromOrigin: false); return true }
            if combo == keys.key(for: "view.reloadOrigin") { tab.reload(fromOrigin: true); return true }
            // By the same factor as the browser's window, and remembered
            // for the site the same way (see Tab.magnify).
            if combo == keys.key(for: "view.zoomIn") { tab.magnify(by: 1.1); return true }
            if combo == keys.key(for: "view.zoomOut") { tab.magnify(by: 1 / 1.1); return true }
            if combo == keys.key(for: "view.actualSize") { tab.resetZoom(); return true }
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.shortcutCharacters
        let switcher = LittleWindow.switcher
        // ⌃Tab, or the key Settings › Shortcuts gave the switcher.
        if let backwards = ShortcutStore.shared.recentSwitch(event) {
            // A Tab held down doesn't race through them.
            guard !event.isARepeat else { return true }
            if !switcher.active {
                let browser = Browsers.front ?? self.browser
                LittleWindow.planet = browser
                switcher.partners = browser?.switcherPartners ?? [:]
            }
            switcher.step(fromMoon: tab.id, moons: LittleWindow.stacked,
                          planet: LittleWindow.planet?.switcherPlanet ?? [], backwards: backwards)
            return true
        }
        // While the switcher is up, ⌃ and the arrows move through it; any
        // other key puts it away. Escape does nothing else: it would close
        // this window too, on the way out of the switcher.
        if switcher.active {
            if ShortcutStore.shared.recentOnly(flags) {
                let direction: TabSwitcher.Direction? = switch event.keyCode {
                case 123: .left
                case 124: .right
                case 125: .down
                case 126: .up
                default: nil
                }
                if let direction {
                    switcher.move(direction)
                    return true
                }
            }
            // ⌃W, ⌃R, ⌃M, ⌃O on the card picked, a moon or a tab, when
            // Settings › Tabs has them on.
            if Shared.prefs.switcherKeys, let action = TabSwitcher.Action(event), let id = switcher.selectedID {
                guard !event.isARepeat else { return true }
                if let little = LittleWindow.holding(id) {
                    little.act(action, in: switcher)
                } else {
                    LittleWindow.planet?.act(action, onCard: id, in: switcher)
                }
                return true
            }
            switcher.cancel()
            if event.keyCode == 53 { return true }
        }
        if event.keyCode == 53 && flags.isEmpty || key == "w" && flags == .command {
            window.performClose(nil)
            return true
        }
        if key == "o" && flags == .command {
            keep()
            return true
        }
        return false
    }

    /// A letter pressed on this window's card in a switcher (see
    /// TabSwitcher.Action): closed, reloaded, muted, or kept in the row.
    func act(_ action: TabSwitcher.Action, in switcher: TabSwitcher) {
        switch action {
        case .close:
            switcher.remove(tab.id)
            close()
        case .reload:
            tab.reload()
        case .mute:
            tab.toggleMute()
            switcher.redraw()
        case .keep:
            // Going to it in the row: nothing left to switch between here.
            switcher.cancel()
            keep()
        }
    }

    /// Its page's address on the pasteboard, plain or as a Markdown link,
    /// said at the foot of the window as the browser's window says it.
    private func copy(markdown: Bool) {
        guard let url = tab.address else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown ? Browser.markdownLink(tab.label, url) : url.absoluteString, forType: .string)
        note.say(markdown ? "Link copied" : "Address copied")
    }

    /// Into the browser's row, after the tab on screen (never among the
    /// pins), and in front; the small window goes. The one time a link in
    /// a small window brings the browser's window: the window in front, or
    /// one brought back for it.
    func keep() { keep(in: nil) }

    /// The same, into the space named, which the browser's window turns to.
    func keep(in space: UUID?) {
        // On screen, it flies into its place in the browser's window, as
        // Arc's does: a picture of it, taken first, while the page itself
        // goes there at once (LittleFlight).
        if !flying, window.isVisible, !Store.testing, !Motion.reduced, let page = tab.built {
            flying = true
            LittleFlight.picture(of: window, page: page) { [weak self] picture in
                self?.settle(in: space, picture: picture)
            }
            return
        }
        settle(in: space, picture: nil)
    }

    /// Set while its picture is taken, so a second ⌘O waits for the first.
    private var flying = false

    private func settle(in space: UUID?, picture: NSImage?) {
        let browser = Browsers.ensureWindow()
        if let space, space != browser.spaceID, browser.spaces.contains(where: { $0.id == space }) {
            browser.switchSpace(to: space)
        }
        let flight = picture.map { LittleFlight(picture: $0, from: window.frame, level: window.level) }
        kept = true
        // In the row, back from the first page goes nowhere, as any tab's.
        tab.leave = nil
        // As a tab moved from another window is: this window's delegate,
        // and this window's space, with its sign-ins.
        browser.receive(tab)
        if flight != nil { going = true }
        window.close()
        guard let front = browser.window else { flight?.land(on: nil, page: nil); return }
        // Put away in the Dock, it stayed there (#95).
        if front.isMiniaturized { front.deminiaturize(nil) }
        front.makeKeyAndOrderFront(nil)
        flight?.land(on: front, page: tab)
    }

    /// Stepping away puts the switcher away, and makes this the one ⌃Tab
    /// comes back to first.
    func windowDidResignKey(_ notification: Notification) {
        let switcher = LittleWindow.switcher
        if switcher.home == tab.id { switcher.cancel() }
        guard !kept else { return }
        switcher.left(tab, alive: Set(LittleWindow.open.map(\.tab.id)))
    }

    /// The last place used, given back only while a screen still shows most
    /// of it, as the floating video's is: a screen removed since the last
    /// visit must not strand the next link off screen.
    private static var remembered: NSRect? {
        guard let text = Store.settings.string(forKey: frameKey) else { return nil }
        let frame = NSRectFromString(text)
        guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
              frame.width >= smallest.width, frame.height >= smallest.height else { return nil }
        return NSScreen.screens.contains {
            let seen = $0.visibleFrame.intersection(frame)
            return !seen.isNull && seen.width * seen.height > 0.6 * frame.width * frame.height
        } ? frame : nil
    }

    /// Not in full screen: the screen's whole size, given back to a window
    /// that is not in full screen, covered the menu bar.
    private func rememberFrame() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        Store.settings.set(NSStringFromRect(window.frame), forKey: LittleWindow.frameKey)
    }

    func windowDidMove(_ notification: Notification) {
        guard window.isVisible else { return }
        cascaded = false
        rememberFrame()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        cascaded = false
        rememberFrame()
    }

    func windowWillClose(_ notification: Notification) {
        if !cascaded { rememberFrame() }
        if LittleWindow.switcher.home == tab.id { LittleWindow.switcher.cancel() }
        tab.leave = nil
        if !kept { tab.close() }
        LittleWindow.open.removeAll { $0 === self }
    }
}

/// The small window on its way into the browser's window, kept with ⌘O or
/// Open in: a picture of it in a window of its own, over everything, that
/// moves and grows on a spring to where the page now is, and fades as it
/// lands, so the page itself shows through. The page is already there,
/// loaded as it was; the picture is all that travels.
@MainActor
final class LittleFlight {
    private let window: NSWindow

    /// The window as it looks: its line and frame as drawn, and the page from
    /// WebKit, which drawing the window leaves out, laid in where it is.
    static func picture(of window: NSWindow, page: WKWebView, then done: @escaping (NSImage?) -> Void) {
        guard let view = window.contentView else { return done(nil) }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return done(nil) }
        view.cacheDisplay(in: view.bounds, to: rep)
        let drawn = NSImage(size: view.bounds.size)
        drawn.addRepresentation(rep)
        // The page's place in the picture, top down.
        var where_ = page.convert(page.bounds, to: view)
        if !view.isFlipped { where_.origin.y = view.bounds.height - where_.maxY }
        page.takeSnapshot(with: nil) { snapshot, _ in
            MainActor.assumeIsolated {
                let image = NSImage(size: view.bounds.size)
                image.lockFocusFlipped(true)
                drawn.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                if let snapshot {
                    // Its card's round corners, as on screen.
                    NSGraphicsContext.current?.saveGraphicsState()
                    NSBezierPath(roundedRect: where_, xRadius: 10, yRadius: 10).addClip()
                    snapshot.draw(in: where_, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                    NSGraphicsContext.current?.restoreGraphicsState()
                }
                image.unlockFocus()
                done(image)
            }
        }
    }

    init(picture: NSImage, from frame: NSRect, level: NSWindow.Level) {
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.level = level
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.contents = picture
        view.layer?.contentsGravity = .resizeAspectFill
        view.layer?.cornerRadius = 12
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFrontRegardless()
    }

    /// Off to where the page is in `browser` — its card, once the window has
    /// laid it out — and gone.
    func land(on browser: NSWindow?, page: Tab?) {
        guard let browser else { return window.close() }
        window.order(.above, relativeTo: browser.windowNumber)
        // A turn later, when the row has taken the page and placed it.
        DispatchQueue.main.async { [self] in
            var target = browser.frame
            if let web = page?.built, let home = web.window, home === browser, web.bounds.width > 0 {
                target = home.convertToScreen(web.convert(web.bounds, to: nil))
            }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.46
                // Out fast, a touch past, and settled: a spring, as a curve.
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1.18, 0.4, 1)
                window.animator().setFrame(target, display: true)
            }, completionHandler: { [self] in
                MainActor.assumeIsolated { window.close() }
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [self] in
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.24
                    context.timingFunction = Motion.outCurve
                    window.animator().alphaValue = 0
                }
            }
        }
    }
}

/// Where a small window's page can go, and how its window is washed: the
/// browser window it would go into, as it was when the link came.
struct LittlePlace {
    /// The space's colour or gradient, as the browser's chrome wears it.
    var wash: SpaceLook?
    var strength: SpaceStrength = .subtle
    var grain: Double = 0
    /// Its spaces, when there's more than one to choose from.
    var spaces: [Space] = []
    var current: UUID?

    @MainActor static func of(_ browser: Browser?) -> LittlePlace {
        guard let browser else { return LittlePlace() }
        return LittlePlace(wash: browser.wash, strength: browser.washStrength, grain: browser.washGrain,
                           spaces: browser.prefs.usesSpaces ? browser.spaces : [], current: browser.spaceID)
    }
}

/// The page, and the line over it, as Arc's Little Arc: the site with its
/// icon and the rest of its address dimmed; Back once a link has been
/// followed, Copy Link, and Open in the space it would go to, with the other
/// spaces a click away. The page is a card on the window's ground, which
/// wears the space's colour as the browser's window does; a thin light runs
/// along the line's foot while the page loads. An extension's popup window
/// and a website's pop-up have the line without the buttons.
struct LittleView: View {
    @ObservedObject var tab: Tab
    /// Its window's line at the foot; an extension's popup has none.
    var note: LittleNote? = nil
    /// Appearance › Size is Roomy: the line taller, its words and button a
    /// size up.
    var roomy = false
    var place = LittlePlace()
    /// Into the browser: into its space on screen, or into the one named.
    let keep: ((UUID?) -> Void)?
    var copy: (() -> Void)? = nil

    static let roomyBar: CGFloat = 44
    static let compactBar: CGFloat = 34
    /// The ground showing round the page's card.
    static let gap: CGFloat = 6

    private var bar: CGFloat { roomy ? LittleView.roomyBar : LittleView.compactBar }

    var body: some View {
        VStack(spacing: 0) {
            line
            ZStack {
                WebStage(page: tab.built ?? tab.web)
                // A page that never came says so, with Try again, as in a tab.
                if let failure = tab.failure {
                    Trouble(message: failure) { tab.reload() }
                        .transition(.opacity)
                }
                Swiping(pulling: tab.pulling)
            }
            .animation(Motion.quick, value: tab.failure)
            .modifier(CardEdge(on: true))
            .padding([.horizontal, .bottom], LittleView.gap)
        }
        .background {
            ZStack {
                Palette.frame
                SpaceWash(look: place.wash)
                    .environment(\.washStrength, place.strength)
                    .environment(\.washGrain, place.grain)
            }
        }
        .overlay(alignment: .bottom) { if let note { LittleToast(note: note) } }
        .ignoresSafeArea()
    }

    private var line: some View {
        HStack(spacing: 6) {
            // Room for the window's own buttons, which sit on this line.
            Spacer().frame(width: roomy ? 70 : 64)
            // The address takes what the buttons leave, and its end is cut:
            // the buttons are never squeezed for it.
            LittleAddress(tab: tab, roomy: roomy, opened: opened)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let keep {
                if tab.canGoBack {
                    LittleBarButton(symbol: "chevron.left", help: "Back", roomy: roomy) { tab.back() }
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                if let copy {
                    LittleBarButton(symbol: "link", help: "Copy Link", roomy: roomy, action: copy)
                }
                LittleOpen(place: place, roomy: roomy, keep: keep)
                    .fixedSize()
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, roomy ? 10 : 8)
        .frame(height: bar)
        .animation(Motion.quick, value: tab.canGoBack)
        .overlay(alignment: .bottom) {
            LittleLoading(loading: tab.loading && tab.failure == nil)
                .padding(.horizontal, LittleView.gap + 10)
                .offset(y: -1)
        }
    }

    /// What the tab that opened this one has on screen.
    private var opened: URL? {
        guard let id = tab.opener else { return nil }
        return Browsers.all.lazy.flatMap { $0.tabs }.first { $0.id == id }?.committed
    }
}

/// The page's address as the line says it: its icon, the site in ink and
/// the rest dimmed, or what it is when it isn't a website. Only what has
/// arrived (`committed`): the address a pop-up was asked to open is not on
/// screen until its page is. A page with nothing of its own yet, about:blank
/// or blob:, is its opener's, and named as that.
private struct LittleAddress: View {
    @ObservedObject var tab: Tab
    let roomy: Bool
    let opened: URL?

    private var size: CGFloat { roomy ? 13 : 12 }

    private var url: URL? {
        let arrived = tab.committed.flatMap { url -> URL? in
            ["about", "blob"].contains(url.scheme?.lowercased() ?? "") ? nil : url
        }
        return arrived ?? opened
    }

    var body: some View {
        HStack(spacing: 7) {
            icon
            text
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(url?.absoluteString ?? "")
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var icon: some View {
        let side: CGFloat = roomy ? 16 : 14
        if let image = tab.icon {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            Image(systemName: url?.scheme == "http" ? "exclamationmark.triangle" : "globe")
                .font(.system(size: side * 0.78, weight: .medium))
                .foregroundStyle(Palette.faint)
                .frame(width: side, height: side)
        }
    }

    private var text: Text {
        guard let url else { return Text("") }
        switch url.scheme?.lowercased() {
        case "https", "http":
            let site = Text(SiteCard.site(url)).foregroundColor(Palette.ink).font(.system(size: size, weight: .medium))
            let rest = Text(AddressBar.after(url)).foregroundColor(Palette.faint).font(.system(size: size))
            if url.scheme?.lowercased() == "http" {
                return Text("Not secure  ").foregroundColor(Palette.muted).font(.system(size: size)) + site + rest
            }
            return site + rest
        case "chrome-extension", "webkit-extension":
            return Text("Extension page").foregroundColor(Palette.muted).font(.system(size: size, weight: .medium))
        default:
            return Text(url.absoluteString == "about:blank" ? "" : "Not a website")
                .foregroundColor(Palette.muted).font(.system(size: size, weight: .medium))
        }
    }
}

/// A plain button on the line: a symbol, a ground on hover.
private struct LittleBarButton: View {
    let symbol: String
    let help: String
    let roomy: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: roomy ? 12.5 : 11.5, weight: .semibold))
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .frame(width: roomy ? 28 : 24, height: roomy ? 28 : 24)
                .background(hovering ? Palette.hover : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .fixedSize()
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Open in the space the browser shows, its icon in its colour; with more
/// than one space, the others on the arrow beside it.
private struct LittleOpen: View {
    let place: LittlePlace
    let roomy: Bool
    let keep: (UUID?) -> Void
    @State private var hovering = false

    private var space: Space? { place.spaces.first { $0.id == place.current } }
    private var size: CGFloat { roomy ? 12.5 : 11.5 }

    var body: some View {
        HStack(spacing: 0) {
            Button { keep(nil) } label: {
                HStack(spacing: 5) {
                    if let space {
                        Image(systemName: space.symbol)
                            .font(.system(size: size - 1, weight: .semibold))
                            .foregroundStyle(space.tint ?? Palette.ground.opacity(0.9))
                    }
                    Text(space.map { "Open in \($0.name)" } ?? "Open in \(Store.name)")
                        .font(.system(size: size, weight: .medium))
                        .lineLimit(1)
                    // Its key, as Arc shows it: quieter than the words.
                    Text("⌘O")
                        .font(.system(size: size - 0.5, weight: .medium))
                        .opacity(0.55)
                        .padding(.leading, 2)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Palette.ground)
                .padding(.leading, roomy ? 13 : 11)
                .padding(.trailing, place.spaces.count > 1 ? 7 : (roomy ? 13 : 11))
                .frame(height: roomy ? 28 : 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .help("Open in \(space?.name ?? Store.name)   ⌘O")
            if place.spaces.count > 1 {
                Rectangle().fill(Palette.ground.opacity(0.25)).frame(width: 1, height: roomy ? 14 : 12)
                Button { LittleOpen.choose(from: place, keep: keep) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: size - 3, weight: .bold))
                        .foregroundStyle(Palette.ground)
                        .frame(width: roomy ? 24 : 21, height: roomy ? 28 : 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .help("Open in another space")
            }
        }
        .background(Palette.ink.opacity(hovering ? 0.86 : 1), in: Capsule())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

extension LittleOpen {
    /// The spaces as a menu under the pointer, each with its icon; the one
    /// on screen ticked.
    @MainActor static func choose(from place: LittlePlace, keep: @escaping (UUID?) -> Void) {
        let menu = NSMenu()
        let target = MenuTarget(keep: keep)
        for space in place.spaces {
            let item = NSMenuItem(title: "Open in \(space.name)", action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = space.id
            item.show(NSImage(systemSymbolName: space.symbol, accessibilityDescription: nil))
            item.state = space.id == place.current ? .on : .off
            menu.addItem(item)
        }
        // The target lives as long as the menu is up.
        objc_setAssociatedObject(menu, &MenuTarget.key, target, .OBJC_ASSOCIATION_RETAIN)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private final class MenuTarget: NSObject {
        nonisolated(unsafe) static var key = 0
        let keep: (UUID?) -> Void
        init(keep: @escaping (UUID?) -> Void) { self.keep = keep }
        @objc func pick(_ item: NSMenuItem) { keep(item.representedObject as? UUID) }
    }
}

/// A light running along the line's foot while the page loads; still, a
/// faint line, with Reduce Motion.
private struct LittleLoading: View {
    let loading: Bool

    var body: some View {
        ZStack {
            if loading {
                if Motion.reduced {
                    Capsule().fill(Palette.ink.opacity(0.18)).frame(height: 2)
                } else {
                    TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        let phase = CGFloat((t / 1.1).truncatingRemainder(dividingBy: 1))
                        GeometryReader { geometry in
                            let width = geometry.size.width * 0.32
                            Capsule()
                                .fill(LinearGradient(colors: [Palette.ink.opacity(0), Palette.ink.opacity(0.45), Palette.ink.opacity(0)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: width, height: 2)
                                .offset(x: -width + phase * (geometry.size.width + width))
                        }
                    }
                    .frame(height: 2)
                    .clipped()
                }
            }
        }
        .frame(height: 2)
        .transition(.opacity)
        .animation(Motion.quick, value: loading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A line said for a moment, as the browser's window says it (see
/// ContentView.announcement): an address copied.
@MainActor
final class LittleNote: ObservableObject {
    @Published private(set) var text: String?
    private var hush: DispatchWorkItem?

    func say(_ text: String) {
        self.text = text
        hush?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.text = nil }
        hush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: work)
    }
}

private struct LittleToast: View {
    @ObservedObject var note: LittleNote

    var body: some View {
        ZStack {
            if let text = note.text {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(Palette.ground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.bottom, 24)
        .animation(Motion.settle, value: note.text)
        .allowsHitTesting(false)
    }
}

/// A website's sized pop-up or an extension's popup window: the
/// browser's tab on screen as the small window shows a page, the site over
/// it. Its tabs, checks and passwords are the browser's, as in any window.
struct PopupWindowView: View {
    @ObservedObject var browser: Browser
    /// Appearance › Size was Roomy when it opened: the taller bar, as the
    /// small window for a link has (the window's buttons are placed to match,
    /// see Browsers.open).
    var roomy = false

    var body: some View {
        if let tab = browser.active {
            LittleView(tab: tab, roomy: roomy, place: .of(browser), keep: nil).id(tab.id)
                .overlay(alignment: .topLeading) {
                    if let asked = browser.suggesting, asked.tab == tab.id {
                        AccountList(browser: browser, asked: asked, top: roomy ? LittleView.roomyBar : LittleView.compactBar)
                    }
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 8) {
                        if let ask = browser.asking {
                            if ask.screen { ScreenQuestion(browser: browser, ask: ask) }
                            else { CaptureQuestion(browser: browser, ask: ask) }
                        }
                        if let offer = browser.offering { PasswordOffer(browser: browser, offer: offer) }
                    }
                    .padding(12)
                }
        } else {
            Palette.ground
        }
    }
}
