import SwiftUI

/// What's in the bar at the page's foot and in the sheets it grows into.
/// As in Arc Search there is no sheet of its own: the bar is one surface
/// that grows taller into the search or the toolbar, its buttons giving way
/// to what's in them. The screen (BrowserController) sizes and moves the
/// surface; this only says what's on it, and how tall each face is.
struct ChromeContent: View {
    @ObservedObject var browser: Browser
    @ObservedObject var state: ChromeState
    @ObservedObject private var tabs = Tabs.shared
    @Namespace private var morph
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Mode: Equatable { case bar, search, toolbar }

    private var mode: Mode {
        switch browser.panel {
        case .search: return .search
        case .toolbar: return .toolbar
        default: return .bar
        }
    }

    /// What the surface holds: a search while a finger draws it up.
    private var shown: Mode { state.drawing ? .search : mode }

    var body: some View {
        ZStack(alignment: .top) { current }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(reduceMotion ? .easeOut(duration: 0.18) : Q.snap, value: browser.panel)
            .animation(reduceMotion ? .easeOut(duration: 0.18) : Q.snap, value: state.drawing)
    }

    @ViewBuilder private var current: some View {
        switch shown {
        case .bar:
            bar.transition(ChromeContent.swap)
        case .search:
            Group {
                if case let .search(prefill, _) = browser.panel {
                    SearchPanel(browser: browser, prefill: prefill, morph: morph)
                        .transition(ChromeContent.swap)
                } else {
                    SearchPanel(browser: browser, prefill: nil, morph: morph, drawnRow: AnyView(drawnBar))
                        .transition(ChromeContent.swap)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measure(\.searchHeight, $0) }
        case .toolbar:
            if let tab = tabs.current {
                ToolbarPanel(browser: browser, tab: tab)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measure(\.toolbarHeight, $0) }
                    .transition(ChromeContent.swap)
            }
        }
    }

    private func measure(_ key: ReferenceWritableKeyPath<ChromeState, CGFloat>, _ height: CGFloat) {
        guard height > 1, abs(state[keyPath: key] - height) > 0.5 else { return }
        state[keyPath: key] = height
        state.measured?()
    }

    /// What's in the surface gives way quickly as the surface changes size.
    /// What's coming in a touch slower than what's going, so the surface
    /// never shows two things at once for long.
    static let swap = AnyTransition.asymmetric(
        insertion: .opacity.animation(.easeOut(duration: 0.18)),
        removal: .opacity.animation(.easeOut(duration: 0.1))
    )

    /// The bar's row as it stands in a search being drawn out of it: its +
    /// in place, the tabs and ^ fading as the surface grows.
    private var drawnBar: some View {
        row(sides: Double(max(0, 1 - state.drawn * 2.5)))
    }

    private var bar: some View {
        row(sides: 1, measured: true)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measure(\.barHeight, $0) }
    }

    private func row(sides: Double, measured: Bool = false) -> some View {
        HStack {
            // The tab you were on before, ready to hop back to. Easy to catch:
            // its touch reaches well past the card on either side.
            Button { browser.showSwitcher() } label: {
                TabStack(tab: tabs.previous ?? tabs.current, count: tabs.all.count, hidingFront: browser.hopping)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Tabs")
                .accessibilityIdentifier("bar.tabs")
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { if measured { state.tabButton = $0 } }
                .opacity(sides)

            Spacer()

            Button { browser.newSearch() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Q.ink)
                    .frame(width: 84, height: 46)
                    .background {
                        // The capsule that stretches into the search field.
                        Capsule().fill(Q.tile)
                            .overlay(Capsule().strokeBorder(Q.hairline))
                            .matchedGeometryEffect(id: "plus", in: morph)
                    }
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("New search")
            .accessibilityIdentifier("bar.new")
            .contextMenu { ClosedMenu() }

            Spacer()

            Button { if tabs.current != nil { browser.panel = .toolbar } else { browser.sheet = .settings } } label: {
                Image(systemName: tabs.current != nil ? "chevron.up" : "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Q.ink)
                    .frame(width: 46, height: 46)
                    .background(Q.tile, in: Circle())
                    .overlay(Circle().strokeBorder(Q.hairline))
                    // As easy to hit as the tab button, and the + stays centred.
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(tabs.current != nil ? "Toolbar" : "Settings")
            .accessibilityIdentifier("bar.toolbar")
            .opacity(sides)
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

/// The tab in front as a small card on a stack, with how many are open.
private struct TabStack: View {
    let tab: Tab?
    let count: Int
    /// Its card is out under a finger: the stack under it stays.
    var hidingFront = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Q.tile)
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Q.hairline))
                .frame(width: 30, height: 40)
                .rotationEffect(.degrees(-10))
                .offset(x: -5, y: 2)
                .opacity(count > 1 ? 1 : 0)
            card
                .frame(width: 30, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Q.hairline))
                .rotationEffect(.degrees(6))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                .opacity(hidingFront ? 0 : 1)
        }
        .frame(width: 46, height: 46)
    }

    @ViewBuilder private var card: some View {
        if let tab {
            StackCard(tab: tab)
        } else {
            Q.ground
        }
    }
}

/// The tab's picture on the stack, kept up as it changes; read from disk
/// for a tab not looked at since Quo opened.
private struct StackCard: View {
    @ObservedObject var tab: Tab
    @ObservedObject private var lock = IncognitoLock.shared

    var body: some View {
        Group {
            if tab.incognito && lock.hiding {
                ZStack {
                    Color(white: 0.12)
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                }
            } else if let image = tab.thumbnail {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 40, alignment: .top)
            } else {
                ZStack {
                    Color(tab.topColor)
                    SiteMark(host: tab.host, size: 16)
                }
            }
        }
        .onAppear { tab.loadThumbnail() }
        .onChange(of: tab.id) { _, _ in tab.loadThumbnail() }
    }
}
