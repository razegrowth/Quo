import UIKit
import SwiftUI
import Translation
import WebKit

/// What's over the page.
enum Panel: Equatable {
    case none, search(prefill: String?, incognito: Bool), toolbar, switcher
}

enum SheetKind: String, Identifiable {
    case site, settings, spaces, reader, downloads, archive
    var id: String { rawValue }
}

extension Panel {
    /// The ones the bottom bar grows into.
    var isSheet: Bool {
        switch self {
        case .search, .toolbar: return true
        default: return false
        }
    }
}

/// The one screen: the page full height, the bar at its foot, and what
/// comes up over it.
@MainActor
final class Browser: ObservableObject {
    static let shared = Browser()

    @Published var panel: Panel = .none {
        didSet {
            // A new search starts in the tab's own mode; switching it is the sheet's.
            if case let .search(_, incognito) = panel, !isSearch(oldValue) { searchIncognito = incognito }
            if panel != .switcher { chromeHidden = false }
            // Leaving search, the keyboard goes down with the sheet, not after it.
            if isSearch(oldValue), !isSearch(panel) {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }
    /// The bar slid away under the tab switcher, its buttons standing in.
    @Published var chromeHidden = false
    private func isSearch(_ panel: Panel) -> Bool { if case .search = panel { return true } else { return false } }
    @Published var sheet: SheetKind?
    @Published var barCollapsed = false
    /// Your Mac's spaces, risen over everything.
    @Published var spacesOpen = false
    /// The search sheet's Incognito switch, which the bar's ground wears too.
    @Published var searchIncognito = false
    @Published var translating: Translator.State = .idle
    @Published var reader: Reader.Article?
    @Published var notice: String?
    @Published var translationConfig: TranslationSession.Configuration?
    var translationTexts: [String] = []
    weak var translationTab: Tab?

    let tabs = Tabs.shared

    /// Typed words or an address, in the tab in front or a new one.
    func go(_ typed: String, incognito: Bool, newTab: Bool) {
        guard let url = AppSettings.shared.destination(for: typed) else { return }
        go(url, incognito: incognito, newTab: newTab)
    }

    func go(_ url: URL, incognito: Bool = false, newTab: Bool = true) {
        if newTab || tabs.current == nil || tabs.current?.incognito != incognito {
            tabs.open(url, incognito: incognito)
        } else {
            tabs.current?.load(url)
        }
        panel = .none
        barCollapsed = false
    }

    /// A pin or bookmark: its tab if one has it open, else a new one.
    func open(_ url: URL) {
        if let open = tabs.tab(showing: url) {
            tabs.select(open)
        } else {
            tabs.open(url)
        }
        panel = .none
        sheet = nil
        spacesOpen = false
        barCollapsed = false
    }

    func newSearch() {
        panel = .search(prefill: nil, incognito: tabs.current?.incognito ?? false)
    }

    func showSwitcher() {
        Task {
            await tabs.current?.snapshot()
            panel = .switcher
        }
    }

    func say(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            MainActor.assumeIsolated { if self?.notice == text { self?.notice = nil } }
        }
    }

    /// The page's scrolling: down far enough folds the bar, up brings it.
    func scrolled(_ delta: CGFloat, dragging: Bool, tab: Tab) {
        guard panel == .none, Sites.shared.settings(for: tab.host).collapseBar else { return }
        // Back at the top: always the whole bar.
        if tab.lastOffset < 24 {
            if barCollapsed { barCollapsed = false }
            travel = 0
            return
        }
        guard dragging, delta != 0 else { return }
        // How far the page has gone one way since it last turned.
        if (delta > 0) != (travel > 0) { travel = 0 }
        travel += delta
        if travel > 40, !barCollapsed {
            barCollapsed = true
        } else if travel < -36, barCollapsed {
            barCollapsed = false
        }
    }
    private var travel: CGFloat = 0
}

struct BrowserView: View {
    @StateObject private var browser = Browser.shared
    @ObservedObject private var tabs = Tabs.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            Q.frame.ignoresSafeArea()

            GeometryReader { geo in
                page(top: geo.safeAreaInsets.top)
                    .clipShape(RoundedRectangle(cornerRadius: pageScale < 1 ? 28 : 0, style: .continuous))
                    .scaleEffect(pageScale, anchor: .center)
                    .quoAnimation(.spring(response: 0.32, dampingFraction: 0.9), value: pageScale)
                    .ignoresSafeArea(edges: [.top, .bottom])
            }

            if browser.panel.isSheet {
                // The page dims where it is, fading, never sliding; a tap on
                // it puts the sheet away.
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .onTapGesture { browser.panel = .none }
                    .transition(.opacity)
                    .zIndex(1)
            }

            if browser.panel == .switcher {
                // It moves its own cards in and out.
                TabSwitcher(browser: browser)
                    .transition(.identity)
                    .zIndex(2)
            }

            // Over the switcher, so the bar slides away and back with it.
            Chrome(browser: browser)
                .zIndex(3)

            if browser.spacesOpen {
                SpacesSheet(browser: browser)
                    .transition(.move(edge: .bottom))
                    .zIndex(5)
            }

            if let notice = browser.notice {
                Text(notice)
                    .font(Q.footnote.weight(.medium))
                    .foregroundStyle(Q.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Q.hairline))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(6)
            }

            TranslateBadge(browser: browser)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
                .zIndex(6)
        }
        .animation(reduceMotion ? .easeOut(duration: 0.18) : Q.snap, value: browser.panel)
        .animation(Q.settle, value: browser.notice)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: browser.spacesOpen)
        .sheet(item: $browser.sheet) { kind in
            switch kind {
            case .site:
                NavigationStack { SiteSettingsView(host: tabs.current?.host, browser: browser) }
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(28)
            case .settings: SettingsView()
            case .spaces: EmptyView()
            case .reader: ReaderSheet(article: browser.reader)
            case .downloads: NavigationStack { DownloadsView() }
            case .archive: NavigationStack { ArchiveView() }
            }
        }
        .translator(browser: browser)
        .onAppear {
            if tabs.current == nil, tabs.all.isEmpty, settings.autoKeyboard { browser.newSearch() }
        }
    }

    /// Behind a sheet the page steps back a little, as under any sheet.
    private var pageScale: CGFloat {
        guard tabs.current != nil else { return 1 }
        return browser.panel.isSheet || browser.spacesOpen ? 0.93 : 1
    }

    @ViewBuilder private func page(top: CGFloat) -> some View {
        if let tab = tabs.current {
            PageView(tab: tab, browser: browser, top: top)
                .id(tab.id)
        } else {
            StartView(browser: browser)
                .padding(.top, top)
                .background(Q.ground)
        }
    }
}

/// The tab's page, with a thin line while it loads.
struct PageView: View {
    @ObservedObject var tab: Tab
    let browser: Browser
    /// The status bar's height: the strip there wears the page's colour.
    let top: CGFloat

    var body: some View {
        WebHost(tab: tab, browser: browser)
            .padding(.top, top)
            .background(Color(tab.topColor))
            .overlay {
                if let failure = tab.failure {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.magnifyingglass")
                            .font(.system(size: 28, weight: .regular))
                            .foregroundStyle(Q.muted)
                        Text("Can\u{2019}t open \(Address.shown(tab.url))")
                            .font(Q.callout)
                            .foregroundStyle(Q.ink)
                            .multilineTextAlignment(.center)
                        Text(failure)
                            .font(Q.footnote)
                            .foregroundStyle(Q.muted)
                            .multilineTextAlignment(.center)
                        Button { tab.retry() } label: {
                            Text("Try Again")
                                .font(Q.bodyEmphasis)
                                .foregroundStyle(Q.ground)
                                .padding(.horizontal, 20)
                                .frame(height: 44)
                                .background(Q.ink, in: Capsule())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.top, 8)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Q.ground)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if tab.loading {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: top)
                        GeometryReader { geo in
                            Rectangle().fill(Q.ink.opacity(0.55))
                                .frame(width: geo.size.width * max(0.06, tab.progress), height: 2)
                                .animation(Q.quick, value: tab.progress)
                        }
                        .frame(height: 2)
                    }
                    .transition(.opacity)
                }
            }
    }
}

/// The tab's WKWebView, made once and kept by the tab.
struct WebHost: UIViewRepresentable {
    let tab: Tab
    let browser: Browser

    func makeUIView(context: Context) -> UIView {
        let holder = UIView()
        holder.backgroundColor = .clear
        attach(to: holder)
        return holder
    }

    func updateUIView(_ holder: UIView, context: Context) {
        if holder.subviews.first !== tab.webViewIfBuilt { attach(to: holder) }
    }

    private func attach(to holder: UIView) {
        holder.subviews.forEach { $0.removeFromSuperview() }
        let web = tab.webView(store: Tabs.shared.store(for: tab))
        web.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(web)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            web.topAnchor.constraint(equalTo: holder.topAnchor),
            web.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        // Room under the page for the bar, so its foot can be scrolled to.
        web.scrollView.contentInset.bottom = 64
        web.scrollView.verticalScrollIndicatorInsets.bottom = 64
        let browser = self.browser
        tab.onScroll = { [weak tab] delta, dragging in
            guard let tab else { return }
            browser.scrolled(delta, dragging: dragging, tab: tab)
        }
    }
}

/// No tab open: the space's pins and a way to search.
struct StartView: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var sync = MacSync.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image("QMark")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .foregroundStyle(Q.ink)
            Text(sync.currentSpace?.name ?? "Quo")
                .font(Q.title)
                .foregroundStyle(Q.ink)
                .padding(.top, 14)
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Q.footnote)
                .foregroundStyle(Q.muted)
                .padding(.top, 4)
            let pins = sync.pins(in: sync.currentSpaceID)
            if !pins.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                    ForEach(pins.prefix(8)) { pin in
                        Button { if let url = URL(string: pin.home) { browser.open(url) } } label: {
                            VStack(spacing: 6) {
                                SiteMark(host: URL(string: pin.home)?.host(), size: 28)
                                    .frame(width: 56, height: 56)
                                    .background(Q.tile, in: RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous))
                                Text(pin.name ?? pin.title)
                                    .font(Q.caption)
                                    .foregroundStyle(Q.muted)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Q.ground)
    }
}
