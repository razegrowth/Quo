import SwiftUI
import UIKit

/// The open tabs as a deck of cards, as Arc Search lays them out (and the
/// iPhone's own app switcher): newest on the right, each card over the one
/// to its left. The card in focus sits a little left of centre with the
/// next one peeking in from the right; the ones before it tuck under, closer
/// together and darker, the further back they are.
///
/// Opening it, the page in front shrinks into its card in the middle, and
/// the bar slides away as the switcher's own buttons come in. A card tapped grows back into the page while the rest
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
                backdrop
                    .opacity(phase == .open ? 1 : 0)

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

        DeckHeader(tab: tab, roomy: headerWidth > 96)
            .frame(width: headerWidth, height: 20, alignment: .leading)
            .position(x: frame.minX + headerWidth / 2, y: frame.minY - 18 + liftY)
            .opacity(open ? shown * g.dimHeader(d) : 0)
            .zIndex(Double(index) * 2 + 1)
            .allowsHitTesting(false)

        DeckCard(tab: tab, width: frame.width, height: frame.height,
                 radius: radius(of: tab), dim: open ? g.dim(d) : 0)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY + liftY)
            .opacity(shown * (1 + min(0, liftY) / g.H * 1.6))
            .zIndex(Double(index) * 2)
            .allowsHitTesting(false)
    }

    /// Where a card is in each phase: in the deck, as the page itself, or
    /// small in the bar's tab button.
    private func frame(of tab: Tab, d: CGFloat, g: Deck) -> CGRect {
        switch phase {
        case .open:
            return g.card(d)
        case .arriving:
            return tab.id == tabs.current?.id ? g.page : g.button
        case .leaving(let chosen):
            return tab.id == chosen ? g.page : g.button
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
        let current = sorted.firstIndex { $0.id == tabs.current?.id } ?? (sorted.count - 1)
        position = CGFloat(max(0, current))
        DispatchQueue.main.async {
            withAnimation(Self.move) {
                phase = .open
                browser.chromeHidden = true
            }
        }
    }

    private func choose(_ tab: Tab) {
        guard phase == .open else { return }
        tabs.select(tab)
        // The card grows back into the page while the bar slides up with it.
        withAnimation(Self.move) {
            phase = .leaving(tab.id)
            browser.chromeHidden = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            var quiet = Transaction()
            quiet.disablesAnimations = true
            withTransaction(quiet) { browser.panel = .none }
        }
    }

    private func close(_ tab: Tab) {
        withAnimation(Self.snap) {
            order.removeAll { $0 == tab.id }
            tabs.close(tab)
            position = min(position, CGFloat(max(0, order.count - 1)))
            lifted = nil
            lift = 0
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
                    position = raw < 0 ? raw / 3 : raw > last ? last + (raw - last) / 3 : raw
                } else if axis == .vertical, lifted != nil {
                    lift = t.height < 0 ? t.height : t.height / 4
                }
            }
            .onEnded { value in
                defer { axis = nil; dragFrom = nil }
                guard phase == .open else { return }
                if axis == .horizontal, let from = dragFrom {
                    let thrown = from - value.predictedEndTranslation.width / g.step
                    let target = min(max(thrown.rounded(), 0), CGFloat(max(0, cards.count - 1)))
                    withAnimation(Self.snap) { position = target }
                } else if axis == .vertical, let id = lifted, let tab = cards.first(where: { $0.id == id }) {
                    let away = value.translation.height < -110 || value.predictedEndTranslation.height < -320
                    if away {
                        withAnimation(.easeOut(duration: 0.18)) { lift = -g.H }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { close(tab) }
                    } else {
                        withAnimation(Self.snap) { lift = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if lift == 0 { lifted = nil } }
                    }
                }
            }
    }

    private func tap(_ point: CGPoint, g: Deck, cards: [Tab]) {
        guard phase == .open, axis == nil, let tab = cardAt(point, g: g, cards: cards) else { return }
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

    /// The page, where it sits under the status bar.
    var page: CGRect { CGRect(x: 0, y: top, width: W, height: H - top) }

    /// The bar's tab button, bottom left.
    var button: CGRect { CGRect(x: 30, y: H - bottom - 52, width: 30, height: 40) }
}

private struct DeckCard: View {
    @ObservedObject var tab: Tab
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    let dim: Double

    var body: some View {
        ZStack(alignment: .top) {
            (tab.incognito ? Color(white: 0.12) : Color(uiColor: tab.topColor))
            if let image = tab.thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()
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
        .shadow(color: .black.opacity(0.35), radius: 16, x: -4, y: 6)
    }
}

private struct DeckHeader: View {
    @ObservedObject var tab: Tab
    let roomy: Bool

    var body: some View {
        HStack(spacing: 7) {
            if tab.incognito {
                Image(systemName: "eyeglasses").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
            }
            SiteMark(host: tab.host, size: 18)
            if roomy {
                Text(tab.shownTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
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
