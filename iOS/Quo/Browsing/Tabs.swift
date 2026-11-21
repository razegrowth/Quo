import SwiftUI
import WebKit

/// The open tabs, the one in front, and the archive of those left alone.
@MainActor
final class Tabs: ObservableObject {
    static let shared = Tabs()

    @Published private(set) var all: [Tab] = []
    @Published var current: Tab?
    @Published private(set) var archived: [Archived] = []

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
        let front = UserDefaults.standard.string(forKey: "tabs.front").flatMap(UUID.init(uuidString:))
        current = all.first { $0.id == front }
        all.forEach(wire)
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

    func select(_ tab: Tab) {
        if let current, current.id != tab.id { Task { await current.snapshot() } }
        tab.lastActive = Date()
        current = tab
        UserDefaults.standard.set(tab.id.uuidString, forKey: "tabs.front")
        save()
    }

    func close(_ tab: Tab) {
        guard let index = all.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.close()
        all.remove(at: index)
        if current?.id == tab.id {
            current = nil
            UserDefaults.standard.removeObject(forKey: "tabs.front")
        }
        if incognito.isEmpty { incognitoStore = nil }
        save()
    }

    func closeAll(incognito: Bool) {
        for tab in all where tab.incognito == incognito { close(tab) }
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

/// What's been downloaded, kept in Documents/Downloads where Files shows it.
@MainActor
final class Downloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = Downloads()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var file: URL?
        var done = false
        var failed = false
        var progress: Double = 0
    }

    @Published private(set) var items: [Item] = []
    private var running: [ObjectIdentifier: UUID] = [:]

    static let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    override init() {
        super.init()
        let files = (try? FileManager.default.contentsOfDirectory(at: Downloads.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        items = files.sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
            .map { Item(name: $0.lastPathComponent, file: $0, done: true, progress: 1) }
    }

    func take(_ download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        var url = Downloads.folder.appendingPathComponent(suggestedFilename)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = (suggestedFilename as NSString).deletingPathExtension, ext = (suggestedFilename as NSString).pathExtension
            url = Downloads.folder.appendingPathComponent(ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)")
            n += 1
        }
        let item = Item(name: url.lastPathComponent, file: url)
        items.insert(item, at: 0)
        running[ObjectIdentifier(download)] = item.id
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        update(download) { $0.done = true; $0.progress = 1 }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        update(download) { $0.failed = true }
    }

    private func update(_ download: WKDownload, _ change: (inout Item) -> Void) {
        guard let id = running[ObjectIdentifier(download)], let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    func remove(_ item: Item) {
        if let file = item.file { try? FileManager.default.removeItem(at: file) }
        items.removeAll { $0.id == item.id }
    }
}

private extension URL {
    var creationDate: Date? { (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate }
}
