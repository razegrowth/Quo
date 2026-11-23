import SwiftUI
import UIKit

/// The open tabs as a deck of cards, as Arc Search lays them out (and the
/// iPhone's own app switcher): newest on the right, each card over the one
/// to its left. The card in focus sits a little left of centre with the
/// next one peeking in from the right; the ones before it tuck under, closer
/// together and darker, the further back they are.
///
/// Opening it, the page in front shrinks into its card, peeking in on the
/// right, the tab before it in the middle; the bar slides away as the
/// switcher's own buttons come in. A card tapped grows back into the page while the rest
/// fall into the bar's tab button. A card flicked up closes.
struct TabSwitcher: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var tabs = Tabs.shared
    @ObservedObject private var sync = MacSync.shared

    private enum Phase: Equatable { case arriving, open, leaving(UUID?) }

    @State private var phase: Phase = .arriving
    /// Which card is in focus, as a continuous index, so a drag moves the
    /// whole deck between them.
    @State private var position: CGFloat = 0
    @State private var dragFrom: CGFloat?
    @State private var axis: Axis?
    @State private var lifted: UUID?
    @State private var lift: CGFloat = 0
    /// The tabs in the deck, oldest first: their order is fixed while the
    /// switcher is open, so a card doesn't move under your finger.
    @State private var order: [UUID] = []

    /// How long things take: about a quarter of a second, no bounce.
    static let move = Animation.spring(response: 0.3, dampingFraction: 0.9)
    static let snap = Animation.spring(response: 0.32, dampingFraction: 0.88)

    private var deck: [Tab] { order.compactMap { id in tabs.all.first { $0.id == id } } }

    var body: some View {
        GeometryReader { proxy in
            let g = Deck(size: proxy.size, insets: Screen.insets)
            let cards = deck
            ZStack(alignment: .topLeading) {
                // Dark until the chosen card covers the screen.
                backdrop
                    .opacity(phase == .arriving ? 0 : 1)

                if cards.isEmpty {
                    empty.frame(width: g.W, height: g.H)
                }

                ForEach(Array(cards.enumerated()), id: \.element.id) { index, tab in
                    card(tab, index: index, count: cards.count, g: g)
                }

                foot(g)
                    .opacity(phase == .open ? 1 : 0)
            }
            .frame(width: g.W, height: g.H)
            .contentShape(Rectangle())
            .gesture(drag(g, cards: cards))
            .simultaneousGesture(SpatialTapGesture().onEnded { tap($0.location, g: g, cards: cards) })
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onAppear(perform: arrive)
        .onChange(of: tabs.all.map(\.id)) { _, ids in takeIn(ids) }
    }

    // MARK: - one card

    @ViewBuilder
    private func card(_ tab: Tab, index: Int, count: Int, g: Deck) -> some View {
        let d = CGFloat(index) - position
        let frame = frame(of: tab, d: d, g: g)
        let open = phase == .open
        let liftY = lifted == tab.id ? min(0, lift) : 0
        let shown = cardOpacity(tab, d: d)
        let headerWidth = max(0, min(g.cardW, g.x(d + 1) - g.x(d) - 8))

        DeckHeader(tab: tab, room: headerWidth)
            .frame(width: headerWidth, height: 20, alignment: .leading)
            .position(x: frame.minX + headerWidth / 2, y: frame.minY - 18 + liftY)
            .opacity(open ? shown * g.dimHeader(d) : 0)
            .zIndex(Double(index) * 2 + 1)
            .allowsHitTesting(false)
            .transition(thrown(g))

        DeckCard(tab: tab, width: frame.width, height: frame.height,
                 radius: radius(of: tab), dim: open ? g.dim(d) : 0,
                 top: frame.minY == 0 ? g.top : 0)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY + liftY)
            .opacity(shown * (1 + min(0, liftY) / g.H * 1.6))
            .zIndex(Double(index) * 2)
            .allowsHitTesting(false)
            .transition(thrown(g))
    }

    /// A card closed by a flick carries on up and off the screen on its own
    /// quick curve, from wherever the finger left it.
    private func thrown(_ g: Deck) -> AnyTransition {
        .asymmetric(insertion: .identity,
                    removal: .offset(y: -g.H * 0.9).combined(with: .opacity).animation(.easeOut(duration: 0.24)))
    }

    /// Where a card is in each phase: in the deck, as the page itself, or
    /// small in the bar's tab button.
    private func frame(of tab: Tab, d: CGFloat, g: Deck) -> CGRect {
        switch phase {
        case .open:
            return g.card(d)
        case .arriving:
            return tab.id == tabs.current?.id ? g.screen : g.button
        case .leaving(let chosen):
            return tab.id == chosen ? g.screen : g.button
        }
    }

    private func radius(of tab: Tab) -> CGFloat {
        switch phase {
        case .open: return 26
        case .arriving: return tab.id == tabs.current?.id ? 0 : 7
        case .leaving(let chosen): return tab.id == chosen ? 0 : 7
        }
    }

    private func cardOpacity(_ tab: Tab, d: CGFloat) -> Double {
        switch phase {
        case .open: return d < -4 ? 0 : 1
        case .arriving: return tab.id == tabs.current?.id ? 1 : 0
        case .leaving(let chosen): return tab.id == chosen ? 1 : 0
        }
    }

    // MARK: - coming and going

    private func arrive() {
        let sorted = tabs.all.sorted { $0.lastActive < $1.lastActive }
        order = sorted.map(\.id)
        sorted.forEach { $0.loadThumbnail() }
        // The tab you were on in the middle: the page shrinks into its card.
        // As in Arc Search: the tab before the one you were on in the middle,
        // the page you were on shrinking into its card peeking in on the
        // right, so going back to the last tab is one tap.
        let current = sorted.firstIndex { $0.id == tabs.current?.id } ?? (sorted.count - 1)
        position = CGFloat(max(0, current - 1))
        DispatchQueue.main.async {
            withAnimation(Self.move) {
                phase = .open
                browser.chromeHidden = true
            }
        }
    }

    private func choose(_ tab: Tab) {
        guard phase == .open else { return }
        // Its page goes behind the switcher now, live, so it has drawn by
        // the time the card has grown over the screen.
        browser.screen?.prepare(tab)
        // The card grows back into the page while the bar slides up with it.
        withAnimation(Self.move) {
            phase = .leaving(tab.id)
            browser.chromeHidden = false
        }
        // Once the card covers the screen, the page is in front under it
        // and the switcher goes: the same picture, on the same spot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) {
                tabs.select(tab)
                browser.panel = .none
            }
        }
    }

    private func close(_ tab: Tab) {
        let title = tab.shownTitle
        withAnimation(Self.snap) {
            order.removeAll { $0 == tab.id }
            tabs.close(tab)
            position = min(position, CGFloat(max(0, order.count - 1)))
            lifted = nil
            lift = 0
        }
        // Undo, while the notice is up: the card comes back where it was.
        guard let item = tabs.closed.first(where: { $0.id == tab.id }) else { return }
        browser.say("Closed \(title)", actionTitle: "Undo") { [browser, tabs] in
            browser.notice = nil
            browser.noticeAction = nil
            Haptics.tap()
            tabs.reopen(item, front: browser.panel != .switcher)
        }
    }

    /// A tab brought back while the deck is open: its card goes in by when
    /// it was last looked at, and the deck turns to it.
    private func takeIn(_ ids: [UUID]) {
        guard phase == .open else { return }
        let fresh = ids.filter { !order.contains($0) }
        guard !fresh.isEmpty else { return }
        withAnimation(Self.snap) {
            for id in fresh {
                guard let tab = tabs.all.first(where: { $0.id == id }) else { continue }
                let at = order.firstIndex { other in
                    (tabs.all.first { $0.id == other }?.lastActive ?? .distantPast) > tab.lastActive
                } ?? order.count
                order.insert(id, at: at)
                tab.loadThumbnail()
                position = CGFloat(at)
            }
        }
    }

    // MARK: - touch

    private func drag(_ g: Deck, cards: [Tab]) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard phase == .open, !cards.isEmpty else { return }
                let t = value.translation
                if axis == nil {
                    axis = abs(t.width) > abs(t.height) ? .horizontal : .vertical
                    dragFrom = position
                    if axis == .vertical { lifted = cardAt(value.startLocation, g: g, cards: cards)?.id }
                }
                if axis == .horizontal, let from = dragFrom {
                    let raw = from - t.width / g.step
                    let last = CGFloat(cards.count - 1)
                    // Past either end, the deck gives a little and no more.
                    position = raw < 0 ? Fling.rubberBand(raw * g.step, dimension: g.W) / g.step
                        : raw > last ? last + Fling.rubberBand((raw - last) * g.step, dimension: g.W) / g.step
                        : raw
                } else if axis == .vertical, lifted != nil {
                    lift = t.height < 0 ? t.height : t.height / 4
                }
            }
            .onEnded { value in
                defer { axis = nil; dragFrom = nil }
                guard phase == .open else { return }
                if axis == .horizontal, let from = dragFrom {
                    // Lands on the card the flick's momentum points at, and
                    // the deck carries on from the finger's speed into it.
                    let landing = from - (value.translation.width + Fling.project(value.velocity.width)) / g.step
                    let target = min(max(landing.rounded(), 0), CGFloat(max(0, cards.count - 1)))
                    let speed = -value.velocity.width / g.step
                    withAnimation(Fling.release(from: position, to: target, speed: speed)) { position = target }
                } else if axis == .vertical, let id = lifted, let tab = cards.first(where: { $0.id == id }) {
                    let away = value.translation.height < -110 || value.predictedEndTranslation.height < -320
                    if away {
                        // The rest of the deck closes the gap the moment it's
                        // let go, while the thrown card is still on its way up.
                        Haptics.toss()
                        close(tab)
                    } else {
                        withAnimation(Self.snap) { lift = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if lift == 0 { lifted = nil } }
                    }
                }
            }
    }

    private func tap(_ point: CGPoint, g: Deck, cards: [Tab]) {
        guard phase == .open, axis == nil, let tab = cardAt(point, g: g, cards: cards) else { return }
        // A locked incognito tab: Face ID first, then in.
        if tab.incognito && IncognitoLock.shared.locked {
            Task { if await IncognitoLock.shared.unlock() { choose(tab) } }
            return
        }
        choose(tab)
    }

    /// The topmost card under a point: the deck's right cards lie over its left.
    private func cardAt(_ point: CGPoint, g: Deck, cards: [Tab]) -> Tab? {
        for (index, tab) in cards.enumerated().reversed() {
            let frame = g.card(CGFloat(index) - position).insetBy(dx: 0, dy: -28)
            if frame.contains(point) { return tab }
        }
        return nil
    }

    // MARK: - around the deck

    private var backdrop: some View {
        ZStack {
            Color(white: 0.07)
            if let space = sync.currentSpace {
                RadialGradient(colors: [Q.colour(of: space).opacity(0.30), .clear],
                               center: .topLeading, startRadius: 20, endRadius: 700)
                RadialGradient(colors: [Q.colour(of: space).opacity(0.14), .clear],
                               center: .bottomTrailing, startRadius: 20, endRadius: 600)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Text("No tabs open")
                .font(Q.callout)
                .foregroundStyle(.white)
            Text("Tap + to search or go somewhere.")
                .font(Q.footnote)
                .foregroundStyle(.white.opacity(0.55))
        }
        .opacity(phase == .open ? 1 : 0)
    }

    private func foot(_ g: Deck) -> some View {
        HStack {
            footCircle("desktopcomputer", label: "Your Mac\u{2019}s spaces", id: "switcher.spaces") { browser.spacesOpen = true }
            Spacer()
            Button { browser.newSearch() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 84, height: 46)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("New search")
            .accessibilityIdentifier("switcher.new")
            .contextMenu { ClosedMenu() }
            Spacer()
            footCircle("gearshape", label: "Settings", id: "switcher.settings") { browser.sheet = .settings }
        }
        .padding(.horizontal, 22)
        .frame(width: g.W)
        .position(x: g.W / 2, y: g.H - g.bottom - 29)
    }

    private func footCircle(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.white.opacity(0.12), in: Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

/// The deck's measures, from the screen's.
private struct Deck {
    let W: CGFloat
    let H: CGFloat
    let top: CGFloat
    let bottom: CGFloat

    init(size: CGSize, insets: UIEdgeInsets) {
        W = size.width
        H = size.height
        top = insets.top
        bottom = max(insets.bottom, 12)
    }

    var cardW: CGFloat { W * 0.69 }
    /// Room between the status bar and the foot, less the title above the card.
    var cardH: CGFloat { min(H * 0.64, H - top - bottom - 76 - 80) }
    var cardTop: CGFloat { top + (H - top - bottom - 76 - cardH) / 2 + 14 }

    /// How far a whole card's move is, dragged: the gap to the next on the right.
    var step: CGFloat { W * 0.58 }

    /// A card's left edge, `d` cards from the one in focus: the next ones a
    /// long step to the right, the ones before tucked close under it.
    func x(_ d: CGFloat) -> CGFloat {
        let base = W * 0.19
        if d >= 0 { return base + d * step }
        if d >= -1 { return base + d * W * 0.16 }
        return base - W * 0.16 + (d + 1) * W * 0.05
    }

    /// Cards behind are a little smaller and darker.
    func scale(_ d: CGFloat) -> CGFloat { d < 0 ? 1 - min(0.12, -d * 0.06) : 1 }
    func dim(_ d: CGFloat) -> Double { d < 0 ? Double(min(0.55, -d * 0.32)) : 0 }
    func dimHeader(_ d: CGFloat) -> Double { d < 0 ? Double(max(0, 1 + d * 0.6)) : 1 }

    func card(_ d: CGFloat) -> CGRect {
        let s = scale(d)
        let w = cardW * s, h = cardH * s
        return CGRect(x: x(d), y: cardTop + (cardH - h) / 2, width: w, height: h)
    }

    /// The whole screen, where the page sits with its strip under the
    /// status bar.
    var screen: CGRect { CGRect(x: 0, y: 0, width: W, height: H) }

    /// The bar's tab button, bottom left.
    var button: CGRect { CGRect(x: 30, y: H - bottom - 52, width: 30, height: 40) }
}

private struct DeckCard: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var lock = IncognitoLock.shared
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let dim: Double
    /// As the page itself: the strip under the status bar, in the page's colour.
    var top: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            (tab.incognito ? Color(white: 0.12) : Color(uiColor: tab.topColor))
            if tab.incognito && lock.hiding {
                // Locked: no picture of the page, only that it's there.
                VStack(spacing: 10) {
                    Image(systemName: "lock.fill").font(.system(size: 26, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    Text("Locked").font(Q.footnote).foregroundStyle(.white.opacity(0.55))
                }
                .frame(width: width, height: height)
            } else if let image = tab.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: max(0, height - top), alignment: .top)
                    .clipped()
                    .padding(.top, top)
            } else {
                VStack(spacing: 10) {
                    SiteMark(host: tab.host, size: 36)
                    Text(Address.shown(tab.url))
                        .font(Q.footnote)
                        .foregroundStyle(Q.muted)
                }
                .frame(width: width, height: height)
            }
            if tab.incognito {
                Text("Incognito")
                    .font(Q.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .frame(width: width, height: height, alignment: .bottomLeading)
                    .padding(10)
            }
            Color.black.opacity(dim)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        // The shadow cast by a plain shape behind the card, not by the
        // picture: far cheaper to draw while the deck moves.
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.35), radius: 16, x: -4, y: 6)
        }
    }
}

private struct DeckHeader: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var lock = IncognitoLock.shared
    /// How wide it may be: up to the next card, which covers the rest.
    let room: CGFloat

    var body: some View {
        // The whole title, never cut short with "…": it fades out softly
        // where its room ends, so as the deck slides it shows more or less
        // of itself, as Arc Search's do.
        HStack(spacing: 7) {
            if tab.incognito {
                Image(systemName: "eyeglasses").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
            if !(tab.incognito && lock.hiding) { SiteMark(host: tab.host, size: 18) }
            Text(tab.incognito && lock.hiding ? "Incognito" : tab.deckTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: max(room, 1), alignment: .leading)
        .mask(alignment: .leading) {
            let fade = min(36, room * 0.4)
            HStack(spacing: 0) {
                Rectangle().frame(width: max(0, room - fade))
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: fade)
            }
        }
    }
}

/// The window's safe area, for views laid out across the whole screen.
enum Screen {
    @MainActor static var insets: UIEdgeInsets {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        return scene?.keyWindow?.safeAreaInsets ?? scene?.windows.first?.safeAreaInsets ?? .zero
    }
}
