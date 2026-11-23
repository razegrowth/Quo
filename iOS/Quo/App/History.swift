import Foundation
import UIKit

/// The pages visited, for suggestions. Never an incognito tab's.
@MainActor
final class History: ObservableObject {
    static let shared = History()

    struct Visit: Codable, Identifiable, Equatable {
        var url: String
        var title: String
        var last: Date
        var count: Int
        var id: String { url }
    }

    @Published private(set) var visits: [Visit]
    /// What this iPhone forgot, for your other devices to forget too
    /// (SyncHistory.swift): everything up to a Clear History, and pages
    /// cleared one by one or with the last hour or day.
    private(set) var forgets: HistoryForgets
    private var pending: DispatchWorkItem?
    static let most = 3000

    private init() {
        visits = Store.read([Visit].self, "history.json") ?? []
        forgets = Store.read(HistoryForgets.self, "history-forgets.json") ?? HistoryForgets()
    }

    func record(_ url: URL, title: String?) {
        guard let scheme = url.scheme, scheme == "http" || scheme == "https" else { return }
        let key = url.absoluteString
        if let index = visits.firstIndex(where: { $0.url == key }) {
            visits[index].last = Date()
            visits[index].count += 1
            if let title, !title.isEmpty { visits[index].title = title }
        } else {
            visits.append(Visit(url: key, title: title ?? "", last: Date(), count: 1))
            if visits.count > History.most {
                visits.sort { $0.last > $1.last }
                visits.removeLast(visits.count - History.most)
            }
        }
        save()
    }

    func retitle(_ url: URL, _ title: String) {
        guard !title.isEmpty, let index = visits.firstIndex(where: { $0.url == url.absoluteString }) else { return }
        visits[index].title = title
        save()
    }

    /// The best matches for typed words: by title and address, the
    /// often-visited and recent first.
    func matches(_ typed: String, limit: Int = 4) -> [Visit] {
        let words = typed.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let now = Date()
        return visits
            .filter { visit in
                let hay = (visit.title + " " + visit.url).lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
            .map { visit -> (Visit, Double) in
                let bare = visit.url.lowercased().replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "www.", with: "")
                let prefix = bare.hasPrefix(words[0]) ? 4.0 : 0
                let age = now.timeIntervalSince(visit.last) / 86_400
                return (visit, prefix + log(Double(visit.count) + 1) * 2 - min(age, 30) / 10)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    func clear() {
        visits = []
        Store.remove("history.json")
        forget(HistoryForgets(all: Date().timeIntervalSince1970))
    }

    /// The pages visited since a time. One visited before and again since
    /// goes too: its last visit is in the span. Each is forgotten by
    /// address, as "everything up to now" would say too much.
    func clear(since: Date) {
        guard since > .distantPast else { return clear() }
        let now = Date().timeIntervalSince1970
        var next = forgets
        for visit in visits where visit.last >= since { next.pages[visit.url] = now }
        visits.removeAll { $0.last >= since }
        forget(next)
        save()
    }

    private func forget(_ next: HistoryForgets) {
        forgets = next.tidied(now: Date().timeIntervalSince1970)
        Store.write(forgets, "history-forgets.json")
        MacSync.shared.historyChanged()
    }

    // MARK: - between devices

    /// This iPhone's history as it's handed to your other devices.
    func handed() -> [SyncedVisit] {
        visits.map { SyncedVisit(u: $0.url, t: $0.title, c: $0.count, l: $0.last.timeIntervalSince1970) }
    }

    /// What another device forgot, forgotten here too: pages last visited
    /// no later than it forgot them. Not this iPhone's own forget, so not
    /// handed on as one.
    func forget(handed other: HistoryForgets) {
        guard !other.isEmpty else { return }
        let before = visits.count
        visits.removeAll { visit in
            let last = visit.last.timeIntervalSince1970
            if let all = other.all, last <= all { return true }
            if let page = other.pages[visit.url], last <= page { return true }
            return false
        }
        if visits.count != before { save() }
    }

    /// Another device's pages taken in: the larger count, the later visit,
    /// a title where there was none. Only what would change is touched.
    func take(handed theirs: [SyncedVisit]) {
        guard !theirs.isEmpty else { return }
        var index = Dictionary(visits.enumerated().map { ($1.url, $0) }, uniquingKeysWith: { first, _ in first })
        var next = visits, changed = false
        for page in theirs where SyncHistory.handed(page.u) {
            let last = Date(timeIntervalSince1970: page.l)
            if let at = index[page.u] {
                var visit = next[at]
                if page.c > visit.count { visit.count = page.c }
                if last > visit.last { visit.last = last }
                if visit.title.isEmpty, !page.t.isEmpty { visit.title = page.t }
                if visit != next[at] { next[at] = visit; changed = true }
            } else {
                index[page.u] = next.count
                next.append(Visit(url: page.u, title: page.t, last: last, count: max(1, page.c)))
                changed = true
            }
        }
        guard changed else { return }
        if next.count > History.most {
            next.sort { $0.last > $1.last }
            next.removeLast(next.count - History.most)
        }
        visits = next
        save()
    }

    private func save() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { if let self { Store.write(self.visits, "history.json") } }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }
}

/// Sites' icons, asked of the site itself: the icon a page names, else its
/// apple-touch-icon, else /favicon.ico. Kept on disk by host.
@MainActor
final class Favicons: ObservableObject {
    static let shared = Favicons()

    @Published private var images: [String: UIImage] = [:]
    private var asked: Set<String> = []
    private let folder: URL = {
        let url = Store.folder.appendingPathComponent("icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func key(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }

    func image(for host: String) -> UIImage? { images[Favicons.key(host)] }

    func want(_ host: String) {
        let key = Favicons.key(host)
        guard images[key] == nil, !asked.contains(key) else { return }
        asked.insert(key)
        let file = folder.appendingPathComponent(key + ".png")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            images[key] = image
            return
        }
        Task { await fetch(key, candidates: [
            URL(string: "https://\(host)/apple-touch-icon.png"),
            URL(string: "https://\(host)/favicon.ico"),
        ].compactMap { $0 }) }
    }

    /// The icon a loaded page names, in place of guessing.
    func offer(_ url: URL, for host: String) {
        let key = Favicons.key(host)
        guard images[key] == nil else { return }
        asked.insert(key)
        Task { await fetch(key, candidates: [url, URL(string: "https://\(host)/favicon.ico")].compactMap { $0 }) }
    }

    func forget() {
        images = [:]
        asked = []
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    private func fetch(_ key: String, candidates: [URL]) async {
        for url in candidates {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data), image.size.width >= 8 else { continue }
            let small = image.preparingThumbnail(of: CGSize(width: 64, height: 64)) ?? image
            images[key] = small
            if let png = small.pngData() { try? png.write(to: folder.appendingPathComponent(key + ".png")) }
            return
        }
    }
}
