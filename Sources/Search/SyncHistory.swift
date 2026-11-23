import Foundation

// History, handed between your devices as open tabs are (SyncTabs.swift): in
// a scope of its own beside each profile's, "history-profile-<id>", each
// device writing its own record only. Quo on the Mac builds this file, and
// Quo for iPhone builds it too (iOS/project.yml), so the two read each other.
//
// A record holds two things:
//   - "visits": the device's history as it is, the last 60 days, the newest
//     2,000 pages at most: each page's address, title, how many visits and
//     when the last was. Every device takes the others' in as it takes a
//     browser's history brought over: the larger count, the later visit, so
//     taking the same page again changes nothing, and two devices agree on
//     the union of what they've seen;
//   - "forgets": what it forgot, so the others forget it too rather than
//     handing it back: the whole history up to a moment (Clear History), and
//     single pages each up to a moment. A device forgets a page of its own
//     only if its last visit was no later than that moment: a page visited
//     again after it was forgotten elsewhere stays. Kept 60 days.
//
// Never a private tab's pages (those aren't kept anywhere), nor a signed-out
// space's own history, which stays on its device with that space's cookies.
// Off with Settings' Sync history, and with sync itself.

/// One page of a device's history as it hands it over.
struct SyncedVisit: Codable, Equatable, Hashable {
    /// The address.
    var u: String
    /// The title, maybe empty.
    var t: String
    /// How many visits.
    var c: Int
    /// The last one, seconds since 1970.
    var l: Double
}

/// What a device forgot: everything up to `all`, and each page (by address)
/// up to its moment, seconds since 1970.
struct HistoryForgets: Codable, Equatable {
    var all: Double?
    var pages: [String: Double] = [:]

    var isEmpty: Bool { all == nil && pages.isEmpty }

    /// Older than `SyncHistory.keep` let go.
    func tidied(now: Double) -> HistoryForgets {
        let since = now - SyncHistory.keep
        return HistoryForgets(all: all.flatMap { $0 >= since ? $0 : nil }, pages: pages.filter { $0.value >= since })
    }
}

/// Another device's history, as its record says it.
struct DeviceHistory: Equatable {
    let device: String
    let name: String
    let written: Double
    let visits: [SyncedVisit]
    let forgets: HistoryForgets
}

enum SyncHistory {
    static let prefix = "history-"
    static func scope(_ profileScope: String) -> String { prefix + profileScope }
    static func isHistory(_ scope: String) -> Bool { scope.hasPrefix(prefix) }

    static let visitsKey = "visits"
    static let forgetsKey = "forgets"
    /// How far back a record goes, and how long a forget is kept: 60 days.
    static let keep: Double = 60 * 24 * 60 * 60
    /// The newest this many pages at most.
    static let most = 2_000
    /// A record is written again for new visits at most this often; one with
    /// a new forget, at once. A Mac's test run makes it a second.
    nonisolated(unsafe) static var every: Double = 120

    /// What a device hands over: web pages, the last 60 days, the newest
    /// first, each address once, at most `most`.
    static func tidy(_ visits: [SyncedVisit], now: Double) -> [SyncedVisit] {
        var seen = Set<String>()
        return visits
            .filter { $0.l >= now - keep && handed($0.u) }
            .sorted { $0.l > $1.l }
            .filter { seen.insert($0.u).inserted }
            .prefix(most)
            .map { SyncedVisit(u: $0.u, t: String($0.t.prefix(300)), c: max(1, $0.c), l: $0.l) }
    }

    /// Only http and https pages, and nothing too long to be an address.
    static func handed(_ address: String) -> Bool {
        guard address.count <= 2_048, let scheme = URL(string: address)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    static func file(device: String, name: String, scope: String, visits: [SyncedVisit],
                     forgets: HistoryForgets, now: Double) -> SyncFile {
        func entry(_ text: String?) -> SyncEntry { SyncEntry(v: text, t: now, d: device) }
        let items: [String: SyncEntry] = [
            visitsKey: entry(SyncMerge.text(tidy(visits, now: now))),
            forgetsKey: entry(SyncMerge.text(forgets.tidied(now: now))),
        ]
        return SyncFile(format: SyncMerge.format, device: device, name: name, scope: scope, written: now, items: items)
    }

    static func read(_ file: SyncFile) -> DeviceHistory? {
        guard isHistory(file.scope), let text = file.items[visitsKey]?.v,
              let visits = SyncMerge.value([SyncedVisit].self, text) else { return nil }
        let forgets = file.items[forgetsKey]?.v.flatMap { SyncMerge.value(HistoryForgets.self, $0) } ?? HistoryForgets()
        return DeviceHistory(device: file.device, name: file.name ?? "Another device", written: file.written,
                             visits: visits.filter { handed($0.u) }, forgets: forgets)
    }

    /// Whether this device's record needs writing: a forget it doesn't say
    /// yet, at once; new visits, at most every two minutes; nothing new, never.
    static func due(_ file: SyncFile?, visits: [SyncedVisit], forgets: HistoryForgets, name: String, now: Double) -> Bool {
        guard let file, let read = read(file), file.name == name else { return true }
        if read.forgets != forgets.tidied(now: now) { return true }
        guard read.visits != tidy(visits, now: now) else { return false }
        return now - file.written >= every
    }

    /// The others' records in a scope, this device's left out.
    static func others(_ files: [SyncFile], scope: String, device: String) -> [DeviceHistory] {
        files.filter { $0.scope == scope && $0.device != device }.compactMap(read)
    }

    /// What of another device's pages this one takes: not one it forgot
    /// itself since, nor one older than its own last Clear History.
    static func taken(_ theirs: [SyncedVisit], mine forgets: HistoryForgets) -> [SyncedVisit] {
        theirs.filter { visit in
            if let all = forgets.all, visit.l <= all { return false }
            if let page = forgets.pages[visit.u], visit.l <= page { return false }
            return true
        }
    }
}
