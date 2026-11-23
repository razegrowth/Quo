import Foundation
import UIKit
import WebKit

/// What's been downloaded, kept in Documents/Downloads, which the Files app
/// shows under On My iPhone › Quo. A file a page can't show downloads on its
/// own; a PDF or anything else shown can be saved from the toolbar, and a
/// link from its long press.
@MainActor
final class Downloads: NSObject, ObservableObject, WKDownloadDelegate {
    static let shared = Downloads()

    struct Item: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var file: URL?
        /// Where it came from, to try again.
        var source: URL?
        var date = Date()
        var done = false
        var failed = false
        var received: Int64 = 0
        /// The size the server gave, or 0 when it didn't.
        var expected: Int64 = 0
        /// A clearer name from the file's own text, offered, never taken
        /// on its own (FileNames).
        var suggested: String?

        var running: Bool { !done && !failed }
        var fraction: Double? { expected > 0 ? min(1, Double(received) / Double(expected)) : nil }
    }

    @Published private(set) var items: [Item] = []

    private struct Running {
        let item: UUID
        let download: WKDownload
        var watch: NSKeyValueObservation?
    }
    private var running: [ObjectIdentifier: Running] = [:]
    /// Cancelled here, so their failure isn't one to report.
    private var cancelling: Set<ObjectIdentifier> = []

    static let folder: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    override init() {
        super.init()
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: Downloads.folder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        items = files.map { file in
            let values = try? file.resourceValues(forKeys: Set(keys))
            let size = Int64(values?.fileSize ?? 0)
            return Item(name: file.lastPathComponent, file: file, date: values?.creationDate ?? .distantPast,
                        done: true, received: size, expected: size)
        }
        .sorted { $0.date > $1.date }
    }

    var active: [Item] { items.filter(\.running) }

    // MARK: - starting

    /// A download WebKit started from a page.
    func take(_ download: WKDownload) {
        Trace.mark("download take \(download.originalRequest?.url?.absoluteString ?? "")")
        download.delegate = self
        running[ObjectIdentifier(download)] = Running(item: UUID(), download: download)
    }

    /// The page in front, or a link on it, downloaded with the tab's own
    /// sign-ins.
    func start(_ url: URL, in tab: Tab) { start(URLRequest(url: url), in: tab) }

    func start(_ request: URLRequest, in tab: Tab) {
        guard let web = tab.webViewIfBuilt else { return }
        Haptics.tap()
        web.startDownload(using: request) { [weak self] download in
            MainActor.assumeIsolated { self?.take(download) }
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        Trace.mark("download destination \(suggestedFilename)")
        let key = ObjectIdentifier(download)
        let url = freeName(suggestedFilename.isEmpty ? "Download" : suggestedFilename)
        var item = Item(name: url.lastPathComponent, file: url,
                        source: download.originalRequest?.url ?? response.url)
        item.expected = max(0, response.expectedContentLength)
        items.insert(item, at: 0)
        running[key] = Running(item: item.id, download: download, watch: watch(download))
        Browser.shared.say("Downloading \(item.name)") { Browser.shared.showDownloads() }
        return url
    }

    /// A name not taken in the folder, nor by one still coming in.
    private func freeName(_ suggested: String) -> URL {
        let base = (suggested as NSString).deletingPathExtension, ext = (suggested as NSString).pathExtension
        let taken = Set(items.compactMap { $0.file?.lastPathComponent })
        var name = suggested, n = 2
        while taken.contains(name) || FileManager.default.fileExists(atPath: Downloads.folder.appendingPathComponent(name).path) {
            name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
        return Downloads.folder.appendingPathComponent(name)
    }

    private func watch(_ download: WKDownload) -> NSKeyValueObservation {
        download.progress.observe(\.completedUnitCount) { [weak self] progress, _ in
            let received = progress.completedUnitCount, total = progress.totalUnitCount
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.moved(download, received: received, total: total) }
            }
        }
    }

    /// Bytes in, shown in steps of a percent, not every packet.
    private func moved(_ download: WKDownload, received: Int64, total: Int64) {
        update(download) { item in
            if total > 0 { item.expected = total }
            let step = max(item.expected / 100, 64 * 1024)
            if received - item.received >= step || received == item.expected { item.received = received }
        }
    }

    // MARK: - ending

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        update(download) { item in
            item.done = true
            if let file = item.file, let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                item.received = Int64(size); item.expected = Int64(size)
            }
        }
        if let id = running[key]?.item, let item = items.first(where: { $0.id == id }), let file = item.file {
            Haptics.done()
            Browser.shared.say("Downloaded \(item.name)") { Browser.shared.preview(file) }
            offerName(for: id, file: file)
        }
        running[key] = nil
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        Trace.mark("download failed \(error)")
        let key = ObjectIdentifier(download)
        defer { running[key] = nil; cancelling.remove(key) }
        guard !cancelling.contains(key) else { return }
        update(download) { $0.failed = true }
        if let id = running[key]?.item, let item = items.first(where: { $0.id == id }) {
            if let file = item.file { try? FileManager.default.removeItem(at: file) }
            Browser.shared.say("\(item.name) didn\u{2019}t download", actionTitle: "Retry") { [weak self] in self?.retry(item) }
        }
    }

    private func update(_ download: WKDownload, _ change: (inout Item) -> Void) {
        guard let id = running[ObjectIdentifier(download)]?.item, let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func download(for item: Item) -> WKDownload? {
        running.values.first { $0.item == item.id }?.download
    }

    // MARK: - from the list

    /// One that didn't finish, from the start, in the tab in front.
    func retry(_ item: Item) {
        guard let source = item.source, let tab = Tabs.shared.current else { return }
        items.removeAll { $0.id == item.id }
        start(source, in: tab)
    }

    func remove(_ item: Item) {
        if item.running, let download = download(for: item) {
            cancelling.insert(ObjectIdentifier(download))
            download.cancel()
        }
        if let file = item.file { try? FileManager.default.removeItem(at: file) }
        items.removeAll { $0.id == item.id }
    }

    /// The finished and failed ones; what's still coming in carries on.
    func clear() {
        for item in items where !item.running { remove(item) }
    }

    var finishedFiles: [URL] { items.filter(\.done).compactMap(\.file) }

    // MARK: - clearer names

    /// A messy name's suggestion, worked out in the background.
    func offerName(for id: UUID, file: URL) {
        Task {
            guard let name = await FileNames.suggest(for: file), name != file.lastPathComponent,
                  let index = items.firstIndex(where: { $0.id == id }) else { return }
            Trace.mark("download name suggested \(name) for \(file.lastPathComponent)")
            items[index].suggested = name
        }
    }

    /// The suggestion taken: the file renamed on disk (another number on
    /// the end if the name's taken), as Files will show it.
    func takeName(_ item: Item) {
        guard let file = item.file, let name = item.suggested,
              let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = freeName(name)
        do {
            try FileManager.default.moveItem(at: file, to: target)
            items[index].file = target
            items[index].name = target.lastPathComponent
            items[index].suggested = nil
            Haptics.tap()
        } catch {
            items[index].suggested = nil
        }
    }

    func ignoreName(_ item: Item) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].suggested = nil
    }
}

extension Downloads.Item {
    /// "2.4 MB of 10 MB", "4.1 MB", or "Didn't finish".
    var detail: String {
        let style = ByteCountFormatStyle(style: .file)
        if failed { return "Didn\u{2019}t finish" }
        if done {
            let size = received.formatted(style)
            return "\(size) \u{00B7} \(date.formatted(.relative(presentation: .named)))"
        }
        if expected > 0 { return "\(received.formatted(style)) of \(expected.formatted(style))" }
        return received > 0 ? received.formatted(style) : "Starting\u{2026}"
    }
}
