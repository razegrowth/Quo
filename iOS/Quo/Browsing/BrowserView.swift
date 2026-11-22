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
            Trace.mark("panel \(panel)")
            if panel != .switcher { chromeHidden = false }
            // Leaving search, the keyboard goes down, and the sheet with it.
            if isSearch(oldValue), !isSearch(panel) {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            if panel != oldValue { screen?.panelChanged(from: oldValue) }
        }
    }
    /// The screen, which moves everything to match.
    weak var screen: BrowserController?
    /// The bar slid away under the tab switcher, its buttons standing in.
    @Published var chromeHidden = false {
        didSet { if chromeHidden != oldValue { screen?.chromeHiddenChanged() } }
    }
    private func isSearch(_ panel: Panel) -> Bool { if case .search = panel { return true } else { return false } }
    @Published var sheet: SheetKind?
    @Published var barCollapsed = false {
        didSet { if barCollapsed != oldValue { screen?.barCollapsedChanged() } }
    }
    /// Your Mac's spaces, risen over everything.
    @Published var spacesOpen = false {
        didSet { if spacesOpen != oldValue { screen?.spacesChanged() } }
    }
    /// The search sheet's Incognito switch, which the bar's ground wears too.
    @Published var searchIncognito = false {
        didSet { if searchIncognito != oldValue { screen?.groundChanged() } }
    }
    /// A tab coming out of the tab button under a finger: the button's own
    /// card is out, so it's hidden.
    @Published var hopping = false
    /// The first launch, before the onboarding is up: the browser stays
    /// dark under it, so it doesn't show for a moment first.
    @Published var awaitingOnboarding = !AppSettings.shared.onboarded
        && ProcessInfo.processInfo.environment["QUO_SKIP_ONBOARDING"] == nil
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

    /// Nothing open: straight to a search, keyboard up, if Settings says so.
    func searchIfEmpty() {
        if tabs.current == nil, tabs.all.isEmpty, AppSettings.shared.autoKeyboard { newSearch() }
    }

    /// A new search, the keyboard starting on this very tap: the sheet
    /// stands where the bar is and the keyboard brings it up.
    func newSearch() {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            panel = .search(prefill: nil, incognito: tabs.current?.incognito ?? false)
        }
        if AppSettings.shared.autoKeyboard { Keyboard.shared.raise() }
    }

    /// A search put away: it goes back down with the keyboard, as one piece,
    /// and is the bar again once it's there.
    func closeSearch() {
        guard case .search = panel else { return }
        if Keyboard.shared.up {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } else {
            panel = .none
        }
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

    var body: some View {
        ZStack {
            // The pages, the bar and its sheets, the switcher and your
            // spaces: one UIKit screen that moves them itself.
            BrowserScreen()
                .ignoresSafeArea()

            if let notice = browser.notice {
                Text(notice)
                    .font(Q.footnote.weight(.medium))
                    .foregroundStyle(Q.ink)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Q.hairline))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    // In from the top and back out the same way, leaving
                    // quicker than it came.
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity).animation(.easeOut(duration: 0.18))))
                    .zIndex(6)
            }

            TranslateBadge(browser: browser)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 8)
                .zIndex(6)

            if browser.awaitingOnboarding {
                Color.black.ignoresSafeArea().zIndex(7)
            }
        }
        .animation(Q.settle, value: browser.notice)
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
            // Not under the onboarding: the keyboard would come up behind it.
            if settings.onboarded { browser.searchIfEmpty() }
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
                .titleTracking()
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
