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
    private var pending: DispatchWorkItem?
    static let most = 3000

    private init() {
        visits = Store.read([Visit].self, "history.json") ?? []
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
