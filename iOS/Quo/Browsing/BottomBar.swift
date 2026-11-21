import SwiftUI

/// The slim bar at the page's foot, and the sheets that come up from it:
/// + and ^ bring a sheet up from the bottom in one piece while the bar's
/// buttons give way under it, and the page steps back. Scrolling down slides the bar
/// away; scrolling up brings it back.
struct Chrome: View {
    @ObservedObject var browser: Browser
    @Namespace private var morph
    @ObservedObject private var tabs = Tabs.shared
    @State private var drag: CGFloat = 0

    private enum Mode: Equatable { case bar, search, toolbar }

    private var mode: Mode {
        switch browser.panel {
        case .search: return .search
        case .toolbar: return .toolbar
        default: return .bar
        }
    }

    var body: some View {
        // Scrolling down, the bar slides straight off the bottom and the
        // page has the whole screen; scrolling up brings it straight back.
        // Under the tab switcher it slides away while the switcher's own
        // buttons come in, and back up as a card grows into the page.
        let hidden = browser.chromeHidden || (browser.barCollapsed && mode == .bar && tabs.current != nil)
        ZStack(alignment: .bottom) {
            bar
                .background(alignment: .top) {
                    Rectangle().fill(.bar)
                        .overlay(alignment: .top) { Rectangle().fill(Q.hairline).frame(height: 0.5) }
                        .ignoresSafeArea(edges: .bottom)
                }
                // Its buttons give way as the sheet comes up over it.
                .opacity(mode == .bar ? 1 : 0)
                .animation(.easeOut(duration: mode == .bar ? 0.2 : 0.1), value: mode)
                .offset(y: hidden ? 150 : 0)
                .allowsHitTesting(!hidden && mode == .bar)
                .animation(browser.chromeHidden ? TabSwitcher.move : .easeOut(duration: hidden ? 0.16 : 0.2), value: hidden)

            if mode != .bar {
                sheet
                    // Up from the bottom in one piece, what's in it with it,
                    // and down off the screen the same way: by the screen's
                    // height, as the keyboard leaving moves it too.
                    .transition(.asymmetric(insertion: .move(edge: .bottom),
                                            removal: .offset(y: UIScreen.main.bounds.height)))
            }
        }
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Q.faint)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            switch mode {
            case .bar:
                EmptyView()
            case .search:
                if case let .search(prefill, _) = browser.panel {
                    SearchPanel(browser: browser, prefill: prefill, morph: morph)
                        .transition(.opacity)
                }
            case .toolbar:
                if let tab = tabs.current {
                    ToolbarPanel(browser: browser, tab: tab)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ChromeGround(open: true, dark: mode == .search && browser.searchIncognito)
                .ignoresSafeArea(edges: .bottom)
        }
        .offset(y: max(0, drag))
        .gesture(closing)
    }

    /// Pulled down far enough, the sheet goes back to being the bar.
    private var closing: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in drag = value.translation.height }
            .onEnded { value in
                let far = value.translation.height > 90 || value.predictedEndTranslation.height > 220
                withAnimation(Q.snap) {
                    if far { browser.panel = .none }
                    drag = 0
                }
            }
    }

    private var bar: some View {
        HStack {
            Button { browser.showSwitcher() } label: { TabStack(tab: tabs.current, count: tabs.all.count) }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Tabs")
                .accessibilityIdentifier("bar.tabs")

            Spacer()

            Button { browser.newSearch() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Q.ink)
                    .frame(width: 84, height: 46)
                    .background(Q.tile, in: Capsule())
                    .overlay(Capsule().strokeBorder(Q.hairline))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("New search")
            .accessibilityIdentifier("bar.new")

            Spacer()

            Button { if tabs.current != nil { browser.panel = .toolbar } else { browser.sheet = .settings } } label: {
                Image(systemName: tabs.current != nil ? "chevron.up" : "gearshape")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Q.ink)
                    .frame(width: 46, height: 46)
                    .background(Q.tile, in: Circle())
                    .overlay(Circle().strokeBorder(Q.hairline))
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(tabs.current != nil ? "Toolbar" : "Settings")
            .accessibilityIdentifier("bar.toolbar")
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            // A swipe up on the bar opens the toolbar, as on the ^.
            if value.translation.height < -30, tabs.current != nil { browser.panel = .toolbar }
        })
    }
}

/// What the bar stands on: the bar's own material while it's a bar, and the
/// sheet's ground, its top corners rounding, as it grows into a sheet.
private struct ChromeGround: View {
    let open: Bool
    let dark: Bool

    var body: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: open ? 28 : 0, topTrailingRadius: open ? 28 : 0, style: .continuous)
        ZStack {
            Rectangle().fill(.bar).opacity(open ? 0 : 1)
            Rectangle().fill(dark ? AnyShapeStyle(Color(white: 0.13)) : AnyShapeStyle(Q.sheet)).opacity(open ? 1 : 0)
        }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Q.hairline, lineWidth: open ? 1 : 0.5)
        }
        .shadow(color: .black.opacity(open ? 0.18 : 0), radius: 20, y: -4)
    }
}

/// The tab in front as a small card on a stack, with how many are open.
private struct TabStack: View {
    let tab: Tab?
    let count: Int

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
        }
        .frame(width: 46, height: 46)
    }

    @ViewBuilder private var card: some View {
        if let image = tab?.thumbnail {
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 30, height: 40, alignment: .top)
        } else {
            ZStack {
                Q.ground
                Text(count == 0 ? "" : "\(count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Q.ink)
            }
        }
    }
}
