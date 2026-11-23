import Combine
import SwiftUI
import UIKit

/// What the bar's SwiftUI content and the screen share: how tall each of
/// the bar's faces is, where its tab button is, and whether a finger is
/// drawing a search up out of it.
@MainActor
final class ChromeState: ObservableObject {
    static let shared = ChromeState()
    /// A finger drawing the bar up into a search: the bar's row stands
    /// where the field will be, its + in place.
    @Published var drawing = false
    /// How far it's drawn, 0 to 1: the bar's other buttons fade as it goes.
    @Published var drawn: CGFloat = 0
    var barHeight: CGFloat = 62
    var searchHeight: CGFloat = 318
    var toolbarHeight: CGFloat = 430
    /// The tab button, in the window: a drag that starts on it hops tabs.
    var tabButton: CGRect = .zero
    /// The bar stands as a rail down one side, as the system's own bars do
    /// on an iPhone Duo's outer screen and its inner one held sideways.
    @Published var rail = false
    /// The rail's buttons, top to bottom, as tall as they come out.
    var railHeight: CGFloat = 190
    /// Told when one of the faces changes height.
    var measured: (() -> Void)?
}

/// How things move here: Core Animation springs, which run in the system's
/// render server, so nothing the app does on its main thread can stall
/// them, and which carry a finger's speed when let go.
@MainActor
enum Motion {
    static var reduced: Bool { UIAccessibility.isReduceMotionEnabled }

    static func spring(_ duration: TimeInterval = 0.3, bounce: CGFloat = 0, velocity: CGFloat = 0,
                       _ changes: @escaping () -> Void, done: ((Bool) -> Void)? = nil) {
        if reduced {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut],
                           animations: changes, completion: done)
        } else {
            UIView.animate(springDuration: duration, bounce: bounce, initialSpringVelocity: velocity, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction], animations: changes, completion: done)
        }
    }

    /// Set at once, nothing animating.
    static func still(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        UIView.performWithoutAnimation(changes)
        CATransaction.commit()
    }
}

/// The one screen, in UIKit: the pages, live, one view per recent tab;
/// the bar and the sheets it grows into; the tab switcher and your spaces
/// over them. It moves them all itself, so a page, a card and the bar are
/// never swapped for pictures of themselves partway through a motion.
@MainActor
final class BrowserController: UIViewController, UIGestureRecognizerDelegate {
    private let browser = Browser.shared
    private let tabs = Tabs.shared
    private let state = ChromeState.shared

    // MARK: layers, bottom to top

    /// Dark behind a page stepped back for a hop, as Arc's.
    private let backdrop = UIView()
    private var slots: [UUID: PageSlot] = [:]
    private weak var front: PageSlot?
    private var start: UIHostingController<StartView>?
    /// The page dims behind the toolbar; a tap on it puts a sheet away.
    private let dim = UIView()
    private var switcher: UIHostingController<TabSwitcher>?
    /// The bar, and the sheets it grows into.
    private let chrome = UIView()
    private let ground = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let tint = UIView()
    private var content: UIHostingController<ChromeContent>!
    private var spaces: UIHostingController<SpacesSheet>?
    /// The hop's card casts this, a plain shape rather than the page.
    private let hopShadow = UIView()

    private var watching: Set<AnyCancellable> = []

    override func loadView() {
        view = UIView()
        view.backgroundColor = UIColor(Q.frame)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        browser.screen = self

        backdrop.backgroundColor = .black
        backdrop.alpha = 0
        view.addSubview(backdrop)

        // Its colour fades rather than the view: a view at no opacity
        // can't be touched, and over a search it has to catch the tap that
        // puts the search away (not let it through to a link on the page).
        dim.backgroundColor = .clear
        dim.isUserInteractionEnabled = false
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        view.addSubview(dim)

        chrome.clipsToBounds = true
        ground.clipsToBounds = true
        ground.layer.cornerCurve = .continuous
        ground.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        ground.layer.borderWidth = 0.5
        ground.contentView.addSubview(tint)
        chrome.addSubview(ground)
        let content = UIHostingController(rootView: ChromeContent(browser: browser, state: state))
        content.view.backgroundColor = .clear
        content.safeAreaRegions = []
        content.sizingOptions = []
        addChild(content)
        chrome.addSubview(content.view)
        content.didMove(toParent: self)
        self.content = content
        view.addSubview(chrome)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        pan.maximumNumberOfTouches = 1
        chrome.addGestureRecognizer(pan)

        hopShadow.backgroundColor = .clear
        hopShadow.layer.shadowColor = UIColor.black.cgColor
        hopShadow.layer.shadowOpacity = 0
        hopShadow.isUserInteractionEnabled = false

        registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { (self: Self, _: UITraitCollection) in
            self.paintGround()
        }
        // Whether the bar is a rail follows the size classes (the Duo
        // opening and closing, Split View); the layout reads it afresh.
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.view.setNeedsLayout()
        }
        paintGround()

        state.measured = { [weak self] in self?.measured() }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardChanges(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardChanges(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)

        tabs.changed = { [weak self] in self?.syncPages() }
        syncPages()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backdrop.frame = view.bounds
        dim.frame = view.bounds
        start?.view.frame = view.bounds
        switcher?.view.frame = view.bounds
        let rail = railSide != nil
        if state.rail != rail { state.rail = rail }
        for slot in slots.values where slot.transform == .identity {
            slot.frame = view.bounds
            slot.strip = view.safeAreaInsets.top
            slot.sides = pageSides
            slot.barRoom = rail ? 0 : 64
        }
        if spaces?.view.transform == .identity { spaces?.view.frame = view.bounds }
        if pull == nil, hop == nil { layoutChrome() }
    }

    private var W: CGFloat { view.bounds.width }
    /// The window's side insets, which the pages and the bar's contents
    /// stay inside (an iPhone Duo's outer screen has a column down one side).
    private var sides: (left: CGFloat, right: CGFloat) { (view.safeAreaInsets.left, view.safeAreaInsets.right) }
    private var H: CGFloat { view.bounds.height }

    // MARK: - the rail

    private enum Side { case left, right }

    /// Where the bar stands as a rail, if it does: wherever the system would
    /// put its own vertical bar (an iPhone Duo's outer screen, its inner one
    /// held sideways, the outer side in Split View). The bar keeps to the
    /// hardware, so the side is the one with the column, the larger inset.
    private var railSide: Side? {
        if #available(iOS 27.1, *) {
            guard traitCollection.verticalBarEdge != .unspecified else { return nil }
        } else {
            return nil
        }
        return sides.left > sides.right ? .left : .right
    }

    /// The rail's width: the column the system leaves on its side, at least
    /// as wide as its buttons need.
    private var railWidth: CGFloat {
        guard let side = railSide else { return 0 }
        return max(side == .right ? sides.right : sides.left, 64)
    }

    /// The sides the pages keep: the window's, and the rail's on its side.
    private var pageSides: (left: CGFloat, right: CGFloat) {
        switch railSide {
        case .left?: return (max(sides.left, railWidth), sides.right)
        case .right?: return (sides.left, max(sides.right, railWidth))
        case nil: return sides
        }
    }

    /// The top of the rail's buttons: down at the foot, under the thumb, and
    /// clear of the clock and camera at the top of the column.
    private var railTop: CGFloat { H - safeBottom - 8 - state.railHeight }

    /// The menu and search as a card beside the rail, rather than across a
    /// wide screen.
    private var cardWidth: CGFloat {
        let other = railSide == .left ? sides.right : sides.left
        return max(0, min(440, W - railWidth - 16 - other))
    }

    /// How far a finger has gone in from the rail, towards the page.
    private func inward(_ t: CGPoint) -> CGFloat {
        switch railSide {
        case .right?: return -t.x
        case .left?: return t.x
        case nil: return -t.y
        }
    }

    // MARK: - the pages

    /// The front page and the ones kept live behind it, as the tabs are now.
    func syncPages() {
        guard hop == nil, isViewLoaded else { return }
        let current = tabs.current
        // Tabs closed: their places go.
        let open = Set(tabs.all.map(\.id))
        for (id, slot) in slots where !open.contains(id) {
            slot.removeFromSuperview()
            slots[id] = nil
        }
        if let current {
            let slot = place(current)
            if front !== slot {
                reveal(slot)
                slot.transform = .identity
                slot.layer.cornerRadius = 0
                slot.frame = view.bounds
                view.insertSubview(slot, belowSubview: dim)
                front = slot
            }
            start?.view.isHidden = true
        } else {
            front = nil
            showStart()
        }
        arrange()
    }

    /// A tab's place, made and put on screen (behind the front) if it wasn't.
    @discardableResult
    private func place(_ tab: Tab) -> PageSlot {
        let slot: PageSlot
        if let made = slots[tab.id] {
            slot = made
        } else {
            slot = PageSlot(tab: tab)
            slots[tab.id] = slot
        }
        if slot.superview == nil {
            slot.frame = view.bounds
            slot.strip = view.safeAreaInsets.top
            slot.sides = pageSides
            slot.barRoom = railSide == nil ? 64 : 0
            if let front { view.insertSubview(slot, belowSubview: front) } else { view.insertSubview(slot, belowSubview: dim) }
            let fresh = slot.web == nil
            slot.wake { [weak self] delta, dragging, tab in self?.browser.scrolled(delta, dragging: dragging, tab: tab) }
            if !fresh { slot.returned() }
        }
        return slot
    }

    /// The front page, the one the tab button hops to just behind it (so
    /// a hop shows it live from the first frame), and two more held ready
    /// but hidden. Any further back are put away; their tabs keep them.
    private func arrange() {
        let current = tabs.current
        let previous = tabs.previous
        let recent = tabs.all.filter { $0.id != current?.id && $0.id != previous?.id }
            .sorted { $0.lastActive > $1.lastActive }
            .prefix(2)
            .map(\.id)
        for (id, slot) in slots {
            if id == current?.id { continue }
            if id == previous?.id {
                reveal(slot)
                if let front, slot.superview != nil, slot !== front { view.insertSubview(slot, belowSubview: front) }
            } else if recent.contains(id), slot.superview != nil {
                slot.isHidden = true
            } else {
                slot.removeFromSuperview()
            }
        }
        // The tab to hop back to, its page made a moment after things settle.
        if let previous, slots[previous.id]?.superview == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.hop == nil, self.tabs.previous?.id == previous.id, self.tabs.all.contains(where: { $0.id == previous.id }) else { return }
                self.place(previous).isHidden = false
            }
        }
    }

    /// The switcher's chosen tab, its page put behind the front while the
    /// card grows, so it has drawn by the time the card covers the screen.
    func prepare(_ tab: Tab) {
        reveal(place(tab))
    }

    /// A page kept hidden, shown again: WebKit may take a moment to draw it,
    /// so its picture covers it for that moment.
    private func reveal(_ slot: PageSlot) {
        guard slot.isHidden else { return }
        slot.isHidden = false
        slot.returned()
    }

    private func showStart() {
        if start == nil {
            let host = UIHostingController(rootView: StartView(browser: browser))
            host.view.backgroundColor = UIColor(Q.ground)
            addChild(host)
            view.insertSubview(host.view, belowSubview: dim)
            host.didMove(toParent: self)
            host.view.frame = view.bounds
            start = host
        }
        start?.view.isHidden = false
        view.insertSubview(start!.view, belowSubview: dim)
    }

    // MARK: - the bar and its sheets

    private enum Mode { case bar, search, toolbar }

    private var mode: Mode {
        switch browser.panel {
        case .search: return .search
        case .toolbar: return .toolbar
        default: return .bar
        }
    }

    /// Where a finger has the bar's top, while it's down.
    private var pull: CGFloat?
    /// Where a search was let go, held there until the keyboard comes to
    /// take it up, or goes to take it down.
    private var held: CGFloat?
    /// The keyboard's top, the screen's foot while it's down.
    private var keyboardTop: CGFloat = .greatestFiniteMagnitude
    private var keyboardUp: Bool { keyboardTop < H - 1 }
    /// A search opened and its keyboard on the way: it stands where the
    /// bar is until the keyboard brings it up.
    private var awaitingKeyboard = false
    private var safeBottom: CGFloat { view.window?.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom }
    private var barTop: CGFloat { H - safeBottom - state.barHeight }

    private func openTop(_ mode: Mode) -> CGFloat {
        switch mode {
        case .bar: return barTop
        case .toolbar: return H - safeBottom - state.toolbarHeight
        case .search:
            if keyboardUp { return keyboardTop - state.searchHeight }
            if awaitingKeyboard { return barTop }
            return H - safeBottom - state.searchHeight
        }
    }

    private var chromeTop: CGFloat { pull ?? held ?? openTop(mode) }

    /// How grown the bar is, 0 as the bar, 1 as a sheet.
    private var grown: CGFloat {
        if let pull, state.drawing { return min(1, max(0, (barTop - pull) / max(1, state.searchHeight - state.barHeight))) }
        return mode == .bar ? 0 : 1
    }

    /// How far open the toolbar is, for the page's dimming.
    private var toolbarOpen: CGFloat {
        guard mode == .toolbar else { return 0 }
        let travel = max(1, barTop - openTop(.toolbar))
        return min(1, max(0, (barTop - chromeTop) / travel))
    }

    private func layoutChrome() {
        if let side = railSide { return layoutRail(side) }
        let top = chromeTop
        let height = H - top + 200
        chrome.bounds = CGRect(x: 0, y: 0, width: W, height: height)
        chrome.center = CGPoint(x: W / 2, y: top + height / 2)
        ground.alpha = 1
        ground.frame = chrome.bounds
        tint.frame = ground.bounds
        let inside = CGRect(x: sides.left, y: 0, width: max(0, W - sides.left - sides.right), height: H)
        if content.view.frame != inside {
            content.view.frame = inside
        }
        let g = grown
        ground.layer.cornerRadius = 28 * g
        tint.alpha = browser.searchIncognito && (mode == .search || state.drawing) ? 1 : 0.55 * g
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.14 * toolbarOpen)
        dim.isUserInteractionEnabled = browser.panel.isSheet
        let hidden = browser.chromeHidden || (browser.barCollapsed && mode == .bar && tabs.current != nil && pull == nil)
        chrome.transform = hidden ? CGAffineTransform(translationX: 0, y: 150) : .identity
        chrome.isUserInteractionEnabled = !hidden
    }

    /// The bar as a rail: its buttons stand clear in the column, no surface
    /// behind them, as the system's vertical bars do; the menu and search
    /// rise as a card beside it.
    private func layoutRail(_ side: Side) {
        let top: CGFloat, width: CGFloat, x: CGFloat
        if mode == .bar {
            top = railTop
            width = railWidth
            x = side == .right ? W - width : 0
            ground.alpha = 0
        } else {
            top = chromeTop
            width = cardWidth
            x = side == .right ? W - railWidth - 8 - width : railWidth + 8
            ground.alpha = 1
        }
        let height = H - top + 200
        chrome.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        chrome.center = CGPoint(x: x + width / 2, y: top + height / 2)
        ground.frame = chrome.bounds
        tint.frame = ground.bounds
        let inside = CGRect(x: 0, y: 0, width: width, height: H)
        if content.view.frame != inside { content.view.frame = inside }
        let g = grown
        ground.layer.cornerRadius = 28 * g
        tint.alpha = browser.searchIncognito && mode == .search ? 1 : 0.55 * g
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.14 * toolbarOpen)
        dim.isUserInteractionEnabled = browser.panel.isSheet
        // Out of the way sideways while the switcher has the screen; a page
        // scrolling doesn't put it away, as it's not over the page.
        let away: CGFloat = side == .right ? railWidth + 40 : -(railWidth + 40)
        chrome.transform = browser.chromeHidden ? CGAffineTransform(translationX: away, y: 0) : .identity
        chrome.isUserInteractionEnabled = !browser.chromeHidden
    }

    private func paintGround() {
        let traits = traitCollection
        let contrast = traits.accessibilityContrast == .high
        ground.layer.borderColor = (contrast ? UIColor(Q.muted) : UIColor(Q.hairline)).resolvedColor(with: traits).cgColor
        ground.layer.borderWidth = contrast ? 1 : 0.5
        let dark = browser.searchIncognito && (mode == .search || state.drawing)
        tint.backgroundColor = dark ? UIColor.black.withAlphaComponent(0.55) : UIColor(Q.sheet)
    }

    /// The bar's look follows a change without moving: the incognito
    /// switch flipped, say.
    func groundChanged() {
        paintGround()
        UIView.animate(withDuration: 0.2) { self.layoutChrome() }
    }

    private func measured() {
        guard pull == nil, hop == nil else { return }
        Motion.spring(0.3) { self.layoutChrome() }
    }

    /// What's over the page changed. The bar grows into the sheet, or
    /// back, on a spring; a search waits for its keyboard to bring it up.
    func panelChanged(from old: Panel) {
        if browser.panel == .switcher { showSwitcher() } else if old == .switcher { hideSwitcher() }
        let was: Mode = {
            switch old { case .search: return .search; case .toolbar: return .toolbar; default: return .bar }
        }()
        guard !inKeyboardMotion else { return }
        if mode == .search, was != .search {
            if case let .search(prefill, _) = browser.panel {
                awaitingKeyboard = !keyboardUp && (AppSettings.shared.autoKeyboard || prefill != nil)
            }
            if awaitingKeyboard {
                // No keyboard after all (one on a stand, say): up on its own.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, self.awaitingKeyboard, !self.keyboardUp, self.mode == .search else { return }
                    self.awaitingKeyboard = false
                    self.held = nil
                    Motion.spring(0.32) { self.layoutChrome() }
                }
            }
        }
        if mode == .search, was == .toolbar, awaitingKeyboard {
            // From the toolbar's address: it waits where the toolbar is for
            // the keyboard to take it up.
            held = openTop(.toolbar)
        }
        if mode != .search {
            awaitingKeyboard = false
            if was == .search {
                // The keyboard taking it down sets the pace, if it's up.
                if keyboardUp { return }
                held = nil
            }
        }
        paintGround()
        Motion.spring(0.3) { self.layoutChrome() }
    }

    /// The switcher took the bar away, or gave it back.
    func chromeHiddenChanged() {
        Motion.spring(0.3, bounce: 0.1) { self.layoutChrome() }
    }

    /// The page scrolled the bar away, or back.
    func barCollapsedChanged() {
        guard hop == nil, pull == nil else { return }
        UIView.animate(withDuration: browser.barCollapsed ? 0.16 : 0.2, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseOut]) { self.layoutChrome() }
    }

    // MARK: - the keyboard

    /// Set while the keyboard's own animation is laying the bar out, so a
    /// panel change made in it isn't animated a second time.
    private var inKeyboardMotion = false

    /// The keyboard moving. The search moves in the same animation, on the
    /// keyboard's own curve and timing, so the two are one piece: up with
    /// it, and down with it into the bar.
    @objc private func keyboardChanges(_ note: Notification) {
        guard let info = note.userInfo,
              let end = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let local = view.convert(end, from: nil)
        let hiding = note.name == UIResponder.keyboardWillHideNotification || local.minY >= H - 1 || local.height < 1
        keyboardTop = hiding ? .greatestFiniteMagnitude : local.minY
        Keyboard.shared.up = !hiding
        let duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let curve = (info[UIResponder.keyboardAnimationCurveUserInfoKey] as? Int) ?? 7

        inKeyboardMotion = true
        if hiding {
            awaitingKeyboard = false
            held = nil
            if case .search = browser.panel { browser.panel = .none }
            Trace.mark("search down")
        } else if mode == .search {
            awaitingKeyboard = false
            held = nil
        }
        inKeyboardMotion = false
        guard pull == nil, hop == nil else { return }
        paintGround()
        if duration <= 0 {
            layoutChrome()
            return
        }
        UIView.animate(withDuration: duration, delay: 0,
                       options: [UIView.AnimationOptions(rawValue: UInt(curve) << 16), .beginFromCurrentState, .allowUserInteraction]) {
            self.layoutChrome()
        }
    }

    @objc private func dimTapped() {
        if case .search = browser.panel { browser.closeSearch() } else { browser.panel = .none }
    }

    // MARK: - a finger on the bar

    private enum Hold { case drawing, closing, hopping, railing }
    private var hold: Hold?

    /// Where the finger on the bar came down.
    private var touchDown: CGPoint = .zero

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touchDown = touch.location(in: view)
        return true
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let pan = g as? UIPanGestureRecognizer, hop == nil else { return false }
        let v = pan.velocity(in: view)
        // Where the finger came down, not where it's got to.
        let started = touchDown
        switch mode {
        case .bar:
            // On the rail, the drags that go up from the bar go in from the
            // side instead.
            if let side = railSide {
                let inward = side == .right ? -v.x : v.x
                return inward > abs(v.y)
            }
            if canHop, grabArea.contains(started), v.y < 80 { return true }
            return -v.y > abs(v.x)
        case .search, .toolbar:
            return v.y > abs(v.x)
        }
    }

    /// Where a drag takes hold of the tab button's card, ahead of drawing
    /// a search: the whole left of the bar, from the screen's edge to just
    /// short of the +, and from a little above the bar to the screen's foot,
    /// so a thumb can't miss it.
    private var grabArea: CGRect {
        let button = state.tabButton
        guard button.width > 0 else { return .zero }
        let top = button.minY - 28
        return CGRect(x: 0, y: top, width: max(button.maxX + 28, W / 2 - 44), height: H - top)
    }

    private var canHop: Bool {
        guard let current = tabs.current, let previous = tabs.previous else { return false }
        return previous.id != current.id && browser.panel == .none
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: view)
        let v = g.velocity(in: view)
        switch g.state {
        case .began:
            if mode == .bar, railSide != nil {
                if canHop, state.tabButton.insetBy(dx: -14, dy: -20).contains(touchDown) {
                    hold = .hopping
                    hopBegan()
                    hopFollow(t)
                } else {
                    // A swipe in off the rail opens a search, as one up off
                    // the bar draws one.
                    hold = .railing
                }
            } else if mode == .bar, canHop, grabArea.contains(touchDown) {
                hold = .hopping
                hopBegan()
                hopFollow(t)
            } else if mode == .bar {
                hold = .drawing
                browser.searchIncognito = tabs.current?.incognito ?? false
                state.drawing = true
                paintGround()
                drag(t)
            } else {
                hold = .closing
                drag(t)
            }
        case .changed:
            if hold == .hopping { hopFollow(t) } else if hold != .railing { drag(t) }
        case .ended:
            let was = hold
            hold = nil
            switch was {
            case .hopping: hopEnded(t, velocity: v)
            case .drawing: drawEnded(t, velocity: v)
            case .closing: closeEnded(t, velocity: v)
            case .railing:
                let landing = inward(CGPoint(x: t.x + Fling.project(v.x), y: t.y + Fling.project(v.y)))
                if inward(t) > 40 || (inward(t) > 12 && landing > 120) {
                    Haptics.settle()
                    browser.newSearch()
                }
            case nil: break
            }
        default:
            let was = hold
            hold = nil
            if was == .hopping { hopBack() } else if was != nil, was != .railing { settleBack() }
        }
    }

    private func drag(_ t: CGPoint) {
        switch hold {
        case .drawing:
            let up = max(0, -t.y), room = max(0, state.searchHeight - state.barHeight)
            pull = barTop - (up <= room ? up : room + Fling.rubberBand(up - room, dimension: 300))
            state.drawn = grown
        case .closing:
            let top = held ?? openTop(mode)
            pull = t.y >= 0 ? min(barTop, top + t.y) : top - Fling.rubberBand(-t.y, dimension: 300)
        default: return
        }
        Motion.still { layoutChrome() }
    }

    private func drawEnded(_ t: CGPoint, velocity v: CGPoint) {
        let landing = t.y + Fling.project(v.y)
        let open = -t.y > 70 || (-t.y > 12 && -landing > 110)
        let from = chromeTop
        if open {
            Haptics.settle()
            var still = Transaction()
            still.disablesAnimations = true
            if AppSettings.shared.autoKeyboard {
                // From where the finger left it, the keyboard takes it the
                // rest of the way up, as one piece.
                held = from
                pull = nil
                withTransaction(still) {
                    state.drawing = false
                    browser.panel = .search(prefill: nil, incognito: browser.searchIncognito)
                }
                Keyboard.shared.raise()
                return
            }
            pull = nil
            withTransaction(still) {
                state.drawing = false
                browser.panel = .search(prefill: nil, incognito: browser.searchIncognito)
            }
            let to = openTop(.search)
            Motion.spring(0.32, velocity: relative(v.y, from: from, to: to)) { self.layoutChrome() }
        } else {
            pull = nil
            state.drawing = false
            paintGround()
            Motion.spring(0.3, velocity: relative(v.y, from: from, to: barTop)) { self.layoutChrome() }
        }
    }

    private func closeEnded(_ t: CGPoint, velocity v: CGPoint) {
        let landing = t.y + Fling.project(v.y)
        let close = t.y > 110 || (t.y > 12 && landing > 160)
        let from = chromeTop
        guard close else {
            settleBack(velocity: v.y)
            return
        }
        Haptics.settle()
        if case .search = browser.panel, keyboardUp {
            // From where the finger left it, down with the keyboard.
            held = from
            pull = nil
            browser.closeSearch()
            return
        }
        pull = nil
        held = nil
        browser.panel = .none
        Motion.spring(0.3, velocity: relative(v.y, from: from, to: barTop)) { self.layoutChrome() }
    }

    private func settleBack(velocity: CGFloat = 0) {
        let from = chromeTop
        pull = nil
        state.drawing = false
        paintGround()
        Motion.spring(0.3, velocity: relative(velocity, from: from, to: openTop(mode))) { self.layoutChrome() }
    }

    /// A finger's speed as a spring's starting velocity, in distances to go a second.
    private func relative(_ speed: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let distance = to - from
        guard abs(distance) > 1 else { return 0 }
        return max(-12, min(12, speed / distance))
    }

    // MARK: - the hop

    /// The tab you were on before, coming out of the tab button under a
    /// finger: its own page, live, as a card.
    private struct Hop {
        let tab: Tab
        let slot: PageSlot
        let from: CGRect
    }
    private var hop: Hop?
    static let reach: CGFloat = 340

    private func hopBegan() {
        guard let current = tabs.current, let target = tabs.previous else { return }
        let slot = place(target)
        reveal(slot)
        // Its picture brought up to date while it's still as it is, so if it
        // goes back into the button, the button shows what the card did.
        Task { await target.snapshot() }
        slot.isUserInteractionEnabled = false
        // Over the bar it comes out of.
        view.insertSubview(hopShadow, aboveSubview: chrome)
        view.insertSubview(slot, aboveSubview: hopShadow)
        let button = state.tabButton
        hop = Hop(tab: target, slot: slot, from: CGRect(x: button.midX - 15, y: button.midY - 20, width: 30, height: 40))
        browser.hopping = true
        Trace.mark("hop out")
        Haptics.pick()
        // A fresh picture of the page being left, for the tab button.
        Task { await current.snapshot() }
    }

    /// The card as it is at a stage of its growth, `p` from 0 (the tab
    /// button's own card, 3 by 4) to 1 (two fifths of the screen, in the
    /// screen's proportions), with the middle of what shows at `center`.
    /// What shows is a window on the page (the mask), so the card changes
    /// shape as it grows without the page laying itself out again.
    private struct Pose {
        var transform: CGAffineTransform
        var window: CGRect
        var radius: CGFloat
        var scale: CGFloat
    }

    private func pose(_ p: CGFloat, center: CGPoint, tilt: CGFloat) -> Pose {
        let strip = view.safeAreaInsets.top
        let s = (30 + (W * 0.4 - 30) * p) / W
        // The button's card shows the page under the status bar, 3 by 4;
        // grown, the whole page and its strip.
        let tall = W * 4 / 3
        let window = CGRect(x: 0, y: strip * (1 - p), width: W, height: tall + (H - tall) * p)
        let angle = tilt * .pi / 180
        let off = CGPoint(x: window.midX - W / 2, y: window.midY - H / 2)
        let turned = CGPoint(x: s * (off.x * cos(angle) - off.y * sin(angle)),
                             y: s * (off.x * sin(angle) + off.y * cos(angle)))
        let transform = CGAffineTransform(translationX: center.x - W / 2 - turned.x, y: center.y - H / 2 - turned.y)
            .rotated(by: angle)
            .scaledBy(x: s, y: s)
        return Pose(transform: transform, window: window, radius: (7 + 9 * p) / s, scale: s)
    }

    /// The card's look at a pose, set at once.
    private func apply(_ pose: Pose, to slot: PageSlot, shadow: CGFloat) {
        slot.transform = pose.transform
        hopMask.frame = pose.window
        hopMask.layer.cornerRadius = pose.radius
        hopShadow.bounds = view.bounds
        hopShadow.center = CGPoint(x: W / 2, y: H / 2)
        hopShadow.transform = pose.transform
        hopShadow.layer.shadowPath = UIBezierPath(roundedRect: pose.window, cornerRadius: pose.radius).cgPath
        hopShadow.layer.shadowOpacity = Float(0.14 + 0.14 * shadow)
        hopShadow.layer.shadowRadius = (4 + 14 * shadow) / pose.scale
        hopShadow.layer.shadowOffset = CGSize(width: 0, height: (2 + 8 * shadow) / pose.scale)
    }

    /// The card's shadow carried to a pose on the same spring as the card:
    /// a layer's shadow isn't moved by a view animation.
    private func springShadow(to pose: Pose, opacity: Float, radius: CGFloat, offset: CGFloat, duration: TimeInterval, bounce: CGFloat) {
        let layer = hopShadow.layer
        let path = UIBezierPath(roundedRect: pose.window, cornerRadius: pose.radius).cgPath
        let changes: [(String, Any?, Any)] = [
            ("shadowPath", layer.presentation()?.shadowPath ?? layer.shadowPath, path),
            ("shadowOpacity", layer.presentation()?.shadowOpacity ?? layer.shadowOpacity, opacity),
            ("shadowRadius", layer.presentation()?.shadowRadius ?? layer.shadowRadius, radius),
            ("shadowOffset", NSValue(cgSize: layer.presentation()?.shadowOffset ?? layer.shadowOffset), NSValue(cgSize: CGSize(width: 0, height: offset))),
        ]
        for (key, from, to) in changes {
            let spring = CASpringAnimation(perceptualDuration: Motion.reduced ? 0.2 : duration, bounce: Motion.reduced ? 0 : bounce)
            spring.keyPath = key
            spring.fromValue = from
            spring.toValue = to
            layer.add(spring, forKey: key)
        }
        layer.shadowPath = path
        layer.shadowOpacity = opacity
        layer.shadowRadius = radius
        layer.shadowOffset = CGSize(width: 0, height: offset)
    }

    private let hopMask: UIView = {
        let mask = UIView()
        mask.backgroundColor = .black
        mask.layer.cornerCurve = .continuous
        return mask
    }()

    private func hopFollow(_ t: CGPoint) {
        guard let hop else { return }
        let p = min(1, max(0, inward(t)) / Self.reach)
        // Grows from the button's card to two fifths of the screen as it
        // rises, exactly under the finger and held near its foot, so it
        // rises above the thumb. Out of the rail, it comes in from the side,
        // held ahead of the thumb and lifted off the screen's foot.
        let tall = (W * 4 / 3 + (H - W * 4 / 3) * p) * (30 + (W * 0.4 - 30) * p) / W
        let center: CGPoint
        if let side = railSide {
            let wide = 30 + (W * 0.4 - 30) * p
            let ahead: CGFloat = side == .right ? -1 : 1
            center = CGPoint(x: hop.from.midX + t.x + ahead * wide * 0.35 * p, y: hop.from.midY + t.y - tall * 0.4 * p)
        } else {
            center = CGPoint(x: hop.from.midX + t.x, y: hop.from.midY + t.y - tall * 0.3 * p)
        }
        let card = pose(p, center: center, tilt: 6 * (1 - p))
        let back = 1 - 0.08 * p
        Motion.still {
            hop.slot.layer.cornerRadius = 0
            hop.slot.mask = hopMask
            apply(card, to: hop.slot, shadow: p)
            front?.transform = CGAffineTransform(scaleX: back, y: back)
            front?.layer.cornerRadius = min(28, 28 * (1 - back) / 0.07) / back
            backdrop.alpha = 0.85 * p
        }
    }

    private func hopEnded(_ t: CGPoint, velocity v: CGPoint) {
        let up = inward(t), landing = inward(CGPoint(x: t.x + Fling.project(v.x), y: t.y + Fling.project(v.y)))
        if up > 150 || (up > 30 && landing > 280) { hopLand(velocity: railSide == nil ? v.y : 0) } else { hopBack(velocity: v) }
    }

    /// Let go high, or flung: the card is the page.
    private func hopLand(velocity: CGFloat) {
        guard let hop else { return }
        Trace.mark("hop land")
        Haptics.settle()
        // Under the bar from here, which is over the page it becomes.
        view.insertSubview(hop.slot, belowSubview: dim)
        view.insertSubview(hopShadow, belowSubview: hop.slot)
        // Carrying the finger's speed, if it's still below where it's going.
        let below = hop.slot.transform.ty
        let speed = below > 20 ? max(0, min(8, -velocity / below)) : 0
        let full = Pose(transform: .identity, window: view.bounds, radius: 0, scale: 1)
        springShadow(to: full, opacity: 0, radius: 0, offset: 0, duration: 0.34, bounce: 0)
        Motion.spring(0.34, velocity: speed) {
            hop.slot.transform = .identity
            self.hopMask.frame = self.view.bounds
            self.hopMask.layer.cornerRadius = 0
            self.hopShadow.transform = .identity
        } done: { _ in
            self.hopShadow.removeFromSuperview()
            hop.slot.mask = nil
            Motion.still {
                self.front?.transform = .identity
                self.front?.layer.cornerRadius = 0
                self.backdrop.alpha = 0
            }
            hop.slot.isUserInteractionEnabled = true
            self.front = hop.slot
            self.hop = nil
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                self.tabs.select(hop.tab)
                self.browser.barCollapsed = false
                self.browser.hopping = false
            }
            self.layoutChrome()
            self.syncPages()
        }
    }

    /// Let go low: back into the button, the card turning back into the
    /// button's own (its shape, its tilt, its corners and its shadow), so
    /// where it lands is exactly what was there.
    private func hopBack(velocity: CGPoint = .zero) {
        guard let hop else { return }
        let home = pose(0, center: CGPoint(x: hop.from.midX, y: hop.from.midY), tilt: 6)
        // The button card's own small shadow.
        springShadow(to: home, opacity: 0.12, radius: 3 / home.scale, offset: 1 / home.scale, duration: 0.36, bounce: 0.12)
        Motion.spring(0.36, bounce: 0.12) {
            hop.slot.transform = home.transform
            self.hopMask.frame = home.window
            self.hopMask.layer.cornerRadius = home.radius
            self.hopShadow.transform = home.transform
            self.front?.transform = .identity
            self.front?.layer.cornerRadius = 0
            self.backdrop.alpha = 0
        } done: { _ in
            self.hopShadow.removeFromSuperview()
            if let front = self.front { self.view.insertSubview(hop.slot, belowSubview: front) }
            hop.slot.mask = nil
            Motion.still {
                hop.slot.transform = .identity
                hop.slot.layer.cornerRadius = 0
            }
            hop.slot.isUserInteractionEnabled = true
            self.hop = nil
            self.browser.hopping = false
            self.syncPages()
        }
    }

    // MARK: - the switcher and your spaces

    private func showSwitcher() {
        guard switcher == nil else { return }
        let host = UIHostingController(rootView: TabSwitcher(browser: browser))
        host.view.backgroundColor = .clear
        addChild(host)
        view.insertSubview(host.view, belowSubview: chrome)
        host.view.frame = view.bounds
        host.didMove(toParent: self)
        switcher = host
    }

    private func hideSwitcher() {
        guard let host = switcher else { return }
        // The chosen tab's page in front before the switcher goes from over it.
        syncPages()
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        switcher = nil
    }

    /// Your Mac's spaces rising over everything, the page stepping back
    /// behind them; and going.
    func spacesChanged() {
        if browser.spacesOpen {
            if spaces == nil {
                let host = UIHostingController(rootView: SpacesSheet(browser: browser))
                host.view.backgroundColor = .clear
                addChild(host)
                view.addSubview(host.view)
                host.view.frame = view.bounds
                host.didMove(toParent: self)
                host.view.transform = CGAffineTransform(translationX: 0, y: H)
                spaces = host
            }
            Motion.spring(0.32) {
                self.spaces?.view.transform = .identity
                self.stepBack(0.93)
            }
        } else if let host = spaces {
            Motion.spring(0.26) {
                host.view.transform = CGAffineTransform(translationX: 0, y: self.H)
                self.stepBack(1)
            } done: { _ in
                guard !self.browser.spacesOpen else { return }
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
                if self.spaces === host { self.spaces = nil }
            }
        }
    }

    private func stepBack(_ scale: CGFloat) {
        let target: UIView? = front ?? start?.view
        target?.transform = scale < 1 ? CGAffineTransform(scaleX: scale, y: scale) : .identity
        target?.layer.cornerRadius = scale < 1 ? 28 / scale : 0
        target?.layer.cornerCurve = .continuous
        target?.clipsToBounds = true
    }
}

/// The controller, in SwiftUI's tree.
struct BrowserScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> BrowserController { BrowserController() }
    func updateUIViewController(_ controller: BrowserController, context: Context) {}
}
