import SwiftUI
import WebKit

/// The open tabs, the one in front, and the archive of those left alone.
@MainActor
final class Tabs: ObservableObject {
    static let shared = Tabs()

    @Published private(set) var all: [Tab] = [] { didSet { changed?() } }
    @Published var current: Tab? { didSet { if current !== oldValue { changed?() } } }
    /// Told the moment the tabs or the one in front change, for the screen
    /// to put the right page in front in the same frame.
    var changed: (() -> Void)?
    @Published private(set) var archived: [Archived] = []
    /// Tabs closed lately, the last first: a flick undone, or one brought
    /// back from the list. Incognito ones only until Quo is closed, and
    /// never in the list.
    @Published private(set) var closed: [Closed] = []
    /// Their pictures, while Quo is open, so one brought back has its card.
    private var closedPictures: [UUID: UIImage] = [:]
    static let mostClosed = 30

    struct Closed: Codable, Identifiable, Equatable {
        var id: UUID
        var url: String
        var title: String
        var incognito = false
        var lastActive: Date
        var closedAt: Date
        /// Back and forward, as WebKit kept them.
        var state: Data?
        var index: Int
    }

    /// The closed tabs the list shows: never an incognito one.
    var recentlyClosed: [Closed] { closed.filter { !$0.incognito } }

    struct Saved: Codable {
        var id: UUID
        var url: String?
        var title: String
        var lastActive: Date
        var state: Data?
    }

    struct Archived: Codable, Identifiable, Equatable {
        var id: UUID
        var url: String
        var title: String
        var archived: Date
    }

    /// Incognito's own store: in memory, gone with the last incognito tab.
    private var incognitoStore: WKWebsiteDataStore?

    func store(for tab: Tab) -> WKWebsiteDataStore {
        guard tab.incognito else { return .default() }
        if let incognitoStore { return incognitoStore }
        let made = WKWebsiteDataStore.nonPersistent()
        incognitoStore = made
        return made
    }

    private init() {
        let saved = Store.read([Saved].self, "tabs.json") ?? []
        all = saved.map { item in
            let tab = Tab(id: item.id, url: item.url.flatMap(URL.init(string:)), title: item.title, lastActive: item.lastActive)
            tab.interactionState = item.state
            return tab
        }
        archived = Store.read([Archived].self, "archive.json") ?? []
        closed = Store.read([Closed].self, "closed.json") ?? []
        let front = UserDefaults.standard.string(forKey: "tabs.front").flatMap(UUID.init(uuidString:))
        current = all.first { $0.id == front }
        all.forEach(wire)
        // Every card's picture ready before the switcher is opened.
        all.forEach { $0.loadThumbnail() }
    }

    var regular: [Tab] { all.filter { !$0.incognito } }
    var incognito: [Tab] { all.filter(\.incognito) }

    private func wire(_ tab: Tab) {
        tab.openTab = { [weak self, weak tab] url, front in
            guard let self else { return nil }
            self.open(url, incognito: tab?.incognito ?? false, front: front)
            return nil
        }
        tab.onDownload = { download in Downloads.shared.take(download) }
        tab.onStartDownload = { [weak self, weak tab] request in
            guard let self, let tab else { return }
            Downloads.shared.start(request, in: tab)
            // A tab opened only for the file (a link to it in a new window)
            // goes once the download's under way, back to the page before.
            if tab.webViewIfBuilt?.backForwardList.currentItem == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak tab] in
                    guard let tab, tab.webViewIfBuilt?.backForwardList.currentItem == nil else { return }
                    if self.current?.id == tab.id, let back = self.previous { self.select(back) }
                    self.close(tab, remember: false)
                }
            }
        }
        tab.openLink = { [weak self] url, front, incognito in
            guard let self else { return }
            self.open(url, incognito: incognito, front: front)
        }
    }

    // MARK: - opening and closing

    @discardableResult
    func open(_ url: URL?, incognito: Bool = false, front: Bool = true) -> Tab {
        Trace.mark("open \(url?.host() ?? "")")
        let tab = Tab(url: url, incognito: incognito)
        wire(tab)
        if let current, let index = all.firstIndex(where: { $0.id == current.id }) {
            all.insert(tab, at: index + 1)
        } else {
            all.append(tab)
        }
        if front { select(tab) }
        save()
        return tab
    }

    /// The tab you were on before this one: what the tab button shows, and
    /// where a hop from it lands.
    var previous: Tab? {
        all.filter { $0.id != current?.id }.max { $0.lastActive < $1.lastActive }
    }

    func select(_ tab: Tab) {
        if let current, current.id != tab.id { Task { await current.snapshot() } }
        tab.lastActive = Date()
        current = tab
        UserDefaults.standard.set(tab.id.uuidString, forKey: "tabs.front")
        save()
    }

    func close(_ tab: Tab, remember: Bool = true) {
        guard let index = all.firstIndex(where: { $0.id == tab.id }) else { return }
        if remember, let url = tab.url {
            closed.insert(Closed(id: tab.id, url: url.absoluteString, title: tab.shownTitle, incognito: tab.incognito,
                                 lastActive: tab.lastActive, closedAt: Date(),
                                 state: tab.liveState ?? tab.interactionState, index: index), at: 0)
            if let picture = tab.thumbnail { closedPictures[tab.id] = picture }
            if closed.count > Tabs.mostClosed {
                for gone in closed[Tabs.mostClosed...] { closedPictures[gone.id] = nil }
                closed.removeLast(closed.count - Tabs.mostClosed)
            }
            saveClosed()
        }
        tab.close()
        all.remove(at: index)
        if current?.id == tab.id {
            current = nil
            UserDefaults.standard.removeObject(forKey: "tabs.front")
        }
        if incognito.isEmpty { incognitoStore = nil }
        IncognitoLock.shared.tabsChanged()
        save()
    }

    func closeAll(incognito: Bool, remember: Bool = true) {
        for tab in all where tab.incognito == incognito { close(tab, remember: remember) }
    }

    // MARK: - closed lately

    /// A closed tab back where it was, its history with it. Behind the one
    /// in front when the tab switcher's open, which puts its card back.
    @discardableResult
    func reopen(_ item: Closed, front: Bool = true) -> Tab? {
        closed.removeAll { $0.id == item.id }
        saveClosed()
        guard all.first(where: { $0.id == item.id }) == nil else { return nil }
        let tab = Tab(id: item.id, url: URL(string: item.url), title: item.title, incognito: item.incognito,
                      lastActive: item.lastActive)
        tab.interactionState = item.state
        tab.thumbnail = closedPictures.removeValue(forKey: item.id)
        wire(tab)
        all.insert(tab, at: min(max(0, item.index), all.count))
        if front { select(tab) } else { save() }
        return tab
    }

    func forgetClosed(_ item: Closed) {
        closed.removeAll { $0.id == item.id }
        closedPictures[item.id] = nil
        saveClosed()
    }

    /// Those closed since a time, as Clear Browsing Data asks.
    func forgetClosed(since: Date) {
        for item in closed where item.closedAt >= since { closedPictures[item.id] = nil }
        closed.removeAll { $0.closedAt >= since }
        saveClosed()
    }

    /// The incognito ones, kept only in memory, never written down.
    private func saveClosed() {
        Store.write(closed.filter { !$0.incognito }, "closed.json")
    }

    func move(from source: Int, to destination: Int) {
        guard all.indices.contains(source), all.indices.contains(destination) else { return }
        let tab = all.remove(at: source)
        all.insert(tab, at: destination)
        save()
    }

    /// The tab already showing a page, so a pin isn't opened twice.
    func tab(showing url: URL) -> Tab? {
        let wanted = Tabs.bare(url)
        return all.first { !$0.incognito && $0.url.map(Tabs.bare) == wanted }
    }

    private static func bare(_ url: URL) -> String {
        var text = url.absoluteString.lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    // MARK: - the archive

    /// Tabs left alone longer than Settings says, put in the archive.
    func archiveInactive(now: Date = Date()) {
        guard let limit = AppSettings.shared.archiveAfter.seconds else { return }
        let stale = all.filter { !$0.incognito && $0.id != current?.id && now.timeIntervalSince($0.lastActive) > limit }
        guard !stale.isEmpty else { return }
        for tab in stale {
            if let url = tab.url {
                archived.insert(Archived(id: tab.id, url: url.absoluteString, title: tab.shownTitle, archived: now), at: 0)
            }
            tab.close()
        }
        all.removeAll { tab in stale.contains { $0.id == tab.id } }
        archived = Array(archived.prefix(500))
        Store.write(archived, "archive.json")
        save()
    }

    func restore(_ item: Archived) {
        archived.removeAll { $0.id == item.id }
        Store.write(archived, "archive.json")
        open(URL(string: item.url))
    }

    func forgetArchived(_ item: Archived) {
        archived.removeAll { $0.id == item.id }
        Store.write(archived, "archive.json")
    }

    func clearArchive() {
        archived = []
        Store.remove("archive.json")
    }

    // MARK: - keeping

    func save() {
        let saved = regular.map { tab in
            Saved(id: tab.id, url: tab.url?.absoluteString, title: tab.title, lastActive: tab.lastActive,
                  state: (tab.isBuilt ? nil : tab.interactionState))
        }
        Store.write(saved, "tabs.json")
        MacSync.shared.tabsChanged()
    }

    /// A tab's address or title changed: kept a moment later, once.
    private var pendingSave: DispatchWorkItem?
    func saveSoon() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.save() } }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// Before the app goes away: each page's back and forward kept too.
    func saveDeep() {
        let saved = regular.map { tab -> Saved in
            Saved(id: tab.id, url: tab.url?.absoluteString, title: tab.title, lastActive: tab.lastActive,
                  state: tab.liveState ?? tab.interactionState)
        }
        Store.write(saved, "tabs.json")
    }

    /// The open URLs, one a line, for Export Data.
    var exported: String {
        regular.compactMap { $0.url?.absoluteString }.joined(separator: "\n")
    }
}

extension Tab {
    var liveState: Data? { isBuilt ? (webViewIfBuilt?.interactionState as? Data) : nil }
}
