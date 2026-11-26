import Foundation

// Open tabs, handed between devices: each Mac's and each iPhone's, in the
// same records as everything else that syncs (SyncRecord.swift), for Quo on
// the Mac and Quo for iPhone alike (iOS/project.yml builds this very file).
//
// Unlike spaces, pins and bookmarks, open tabs are never merged: tabs belong
// to the device they are open on. Each device publishes its own as they are
// now, the whole list at once, and reads the others' to show and open; a
// device's file says only what that device has, and is replaced whole.
//
// Scope "tabs-profile-<id>", one per profile as the profile's own scope is,
// so a profile's tabs never show in another's windows; the iPhone is the
// Personal profile's. The record is "<scope>.<device>", as every record is,
// so each device has one. The file is an ordinary SyncFile of format 1, so a
// Quo from before tabs synced fetches it, decodes it and keeps it like any
// other and then passes it over: a Mac only ever works through the scopes it
// knows ("app", "profile-<id>"), and the first iPhone build only through the
// Personal profile's. A folder's files go in a folder of the scope's name,
// which a Mac from before never reads.
//
// Its items: "tabs", the list of SyncedTab, the one looked at last first;
// "spaces", the names of the spaces they are in; "kind", "mac" or
// "iphone"; and "sent", pages sent to one other device to open there
// (SentTab), only while there are some. Each stamped when the file was
// written, by its device.
//
// Sending a page: the sender puts it in its own file, addressed to the
// other device by id, and writes the file at once. The other device opens
// each one addressed to it once, remembering which it opened, and the
// sender lets it go after a while (SyncTabs.keepSent). A Quo from before
// sending has no "sent" to read and passes it over, as any item it doesn't
// know.
//
// What is never published: private tabs and windows, incognito tabs, tabs a
// script or an agent opened or works in, pins (they sync as pins), and
// anything but a web page (http and https).

/// One open tab, as another device sees it.
struct SyncedTab: Codable, Equatable, Hashable {
    var url: String
    var title: String
    /// The space it's open in, by id; nil on a device without spaces.
    var space: String?
    /// When it was last looked at, seconds since 1970, to the minute.
    var active: Double
}

/// A page sent to one other device, to open there.
struct SentTab: Codable, Equatable, Hashable, Identifiable {
    /// Made once, so the other device opens it only once.
    var id: String
    var url: String
    var title: String
    /// The device it's for, by id.
    var to: String
    /// When it was sent, seconds since 1970.
    var at: Double
}

/// A device a page can be sent to.
struct TabTarget: Equatable, Hashable, Identifiable {
    var device: String
    var name: String
    var phone: Bool
    /// When it was last heard from, seconds since 1970.
    var seen: Double = 0
    /// What a menu calls it: its name, and when it was last heard from
    /// while another one has the same name (an iPhone can't tell an app
    /// its own name, so every iPhone is "iPhone"). See SyncTabs.targets.
    var label: String = ""
    var id: String { device }

    init(device: String, name: String, phone: Bool, seen: Double = 0) {
        self.device = device
        self.name = name
        self.phone = phone
        self.seen = seen
        label = name
    }

    /// The same device, whatever its label says this minute.
    static func == (a: TabTarget, b: TabTarget) -> Bool {
        a.device == b.device && a.name == b.name && a.phone == b.phone
    }
    func hash(into hasher: inout Hasher) { hasher.combine(device) }
}

/// A page another device sent here, and who sent it.
struct ArrivedTab: Equatable {
    var from: String
    var fromName: String
    var tab: SentTab
}

/// A space that has tabs in the list: its name, for a device that doesn't
/// know the space yet.
struct SyncedTabSpace: Codable, Equatable, Hashable {
    var id: String
    var name: String
}

/// Another device's open tabs, as its file says.
struct DeviceTabs: Equatable, Identifiable {
    var device: String
    var name: String
    var phone: Bool
    var written: Double
    var tabs: [SyncedTab]
    var spaces: [SyncedTabSpace]
    var sent: [SentTab] = []
    var id: String { device }

    /// The tabs open in a space, the one looked at last first. `orHome`:
    /// a tab whose space isn't among `known` shows in this one too.
    func tabs(in space: String, known: Set<String> = [], orHome: Bool = false) -> [SyncedTab] {
        tabs.filter { tab in
            guard let id = tab.space else { return orHome }
            return id == space || (orHome && !known.contains(id))
        }
    }

    /// The name of the space a tab is in, as this device's file says.
    func spaceName(_ id: String?) -> String? {
        id.flatMap { id in spaces.first { $0.id == id }?.name }
    }
}

enum SyncTabs {
    static let prefix = "tabs-"

    /// The scope of a profile's tabs, from the profile's own scope
    /// ("profile-<id>").
    static func scope(_ profileScope: String) -> String { prefix + profileScope }

    static func isTabs(_ scope: String) -> Bool { scope.hasPrefix(prefix) }

    /// How many tabs a device publishes at most: the ones looked at last.
    static let most = 150
    /// A device not heard from for this long is left out: its tabs are
    /// likely long closed, and it may be gone.
    static let stale: Double = 30 * 24 * 60 * 60
    /// A device a page can still be sent to: heard from within a week. A
    /// page sent waits three days for it (keepSent); one quiet longer than
    /// that is most likely a test install or a phone put away, and only
    /// made the list longer.
    static let reach: Double = 7 * 24 * 60 * 60
    /// How often a device writes its tabs at most, unless it is going away
    /// (put in the background, or another app comes forward). Under the
    /// Mac's half-minute pass, so the next pass after a change writes it.
    static let every: Double = 20

    static let tabsKey = "tabs"
    static let spacesKey = "spaces"
    static let kindKey = "kind"
    static let sentKey = "sent"

    /// How long a sent page waits in its sender's file for the other
    /// device to come by: one away for longer likely doesn't want it now.
    static let keepSent: Double = 3 * 24 * 60 * 60
    /// How many sent pages a file carries at most, the newest.
    static let mostSent = 30

    /// Whether a page can be handed to another device: a web page, with an
    /// address of reasonable length.
    static func handed(_ url: String) -> Bool {
        guard url.count <= 4096, let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && parsed.host() != nil
    }

    /// The list as it is published: web pages only, each page once (the
    /// one looked at last), the last looked at first, at most `most`, times
    /// to the minute so a glance at a tab doesn't make a new file.
    static func tidy(_ tabs: [SyncedTab]) -> [SyncedTab] {
        var seen = Set<String>()
        let sorted = tabs
            .filter { handed($0.url) && $0.active.isFinite }
            .map { tab -> SyncedTab in
                var tab = tab
                tab.active = (tab.active / 60).rounded(.down) * 60
                if tab.title.count > 300 { tab.title = String(tab.title.prefix(300)) }
                return tab
            }
            // The order is fixed whatever order they came in: newest, then
            // by address, then by space.
            .sorted { a, b in
                if a.active != b.active { return a.active > b.active }
                if a.url != b.url { return a.url < b.url }
                return (a.space ?? "") < (b.space ?? "")
            }
        var out: [SyncedTab] = []
        for tab in sorted where seen.insert((tab.space ?? "") + " " + tab.url).inserted {
            out.append(tab)
            if out.count == most { break }
        }
        return out
    }

    /// A device's tabs as its file for a scope.
    static func file(device: String, name: String, phone: Bool, scope: String,
                     tabs: [SyncedTab], spaces: [SyncedTabSpace], sent: [SentTab] = [], now: Double) -> SyncFile {
        let list = tidy(tabs)
        let used = Set(list.compactMap(\.space))
        let named = spaces.filter { used.contains($0.id) }
        func entry(_ text: String?) -> SyncEntry { SyncEntry(v: text, t: now, d: device) }
        var items: [String: SyncEntry] = [
            tabsKey: entry(SyncMerge.text(list)),
            spacesKey: entry(SyncMerge.text(named)),
            kindKey: entry(SyncMerge.text(phone ? "iphone" : "mac")),
        ]
        let outbox = tidySent(sent, now: now)
        if !outbox.isEmpty { items[sentKey] = entry(SyncMerge.text(outbox)) }
        return SyncFile(format: SyncMerge.format, device: device, name: name, scope: scope, written: now, items: items)
    }

    /// What a device's tabs file says; nil for one that isn't a tabs file
    /// this build can read.
    static func read(_ file: SyncFile) -> DeviceTabs? {
        guard isTabs(file.scope), let text = file.items[tabsKey]?.v,
              let tabs = SyncMerge.value([SyncedTab].self, text) else { return nil }
        let spaces = file.items[spacesKey]?.v.flatMap { SyncMerge.value([SyncedTabSpace].self, $0) } ?? []
        let kind = file.items[kindKey]?.v.flatMap { SyncMerge.value(String.self, $0) }
        let sent = file.items[sentKey]?.v.flatMap { SyncMerge.value([SentTab].self, $0) } ?? []
        return DeviceTabs(device: file.device, name: file.name ?? (kind == "iphone" ? "iPhone" : "Mac"),
                          phone: kind == "iphone", written: file.written,
                          tabs: tabs.filter { handed($0.url) }, spaces: spaces,
                          sent: sent.filter { handed($0.url) })
    }

    /// Whether a file already says these tabs: nothing new to write.
    static func says(_ file: SyncFile?, tabs: [SyncedTab], spaces: [SyncedTabSpace], name: String,
                     sent: [SentTab] = [], now: Double = Date().timeIntervalSince1970) -> Bool {
        guard let file, file.name == name, let read = read(file) else { return false }
        let list = tidy(tabs)
        let used = Set(list.compactMap(\.space))
        return read.tabs == list && read.spaces == spaces.filter { used.contains($0.id) }
            && read.sent == tidySent(sent, now: now)
    }

    /// Whether this device should write its tabs now: they changed, and it
    /// last wrote them long enough ago, or it is going away.
    static func due(_ file: SyncFile?, tabs: [SyncedTab], spaces: [SyncedTabSpace], name: String,
                    sent: [SentTab] = [], now: Double, going: Bool) -> Bool {
        guard !says(file, tabs: tabs, spaces: spaces, name: name, sent: sent, now: now) else { return false }
        guard let written = file?.written, !going else { return true }
        // A page just sent goes at once: someone is waiting for it.
        let wrote = file.flatMap(read)?.sent ?? []
        if tidySent(sent, now: now).contains(where: { !wrote.contains($0) }) { return true }
        return now - written >= every || now < written
    }

    // MARK: - sending a page

    /// Sent pages as a file carries them: web pages, not yet too old, each
    /// once, the newest first, at most `mostSent`.
    static func tidySent(_ sent: [SentTab], now: Double) -> [SentTab] {
        var seen = Set<String>()
        return Array(sent
            .filter { handed($0.url) && $0.at.isFinite && now - $0.at < keepSent && $0.at - now < 60 * 60 }
            .sorted { $0.at != $1.at ? $0.at > $1.at : $0.id < $1.id }
            .filter { seen.insert($0.id).inserted }
            .prefix(mostSent))
    }

    /// A page, ready to send to a device.
    static func send(_ url: String, title: String, to device: String, now: Double) -> SentTab {
        SentTab(id: UUID().uuidString, url: url, title: String(title.prefix(300)), to: device, at: now)
    }

    /// The other devices a page can be sent to in a scope: every one heard
    /// from lately with a tabs file there, open tabs or not, the one heard
    /// from last first.
    static func targets(_ files: [SyncFile], scope: String, device: String, now: Double) -> [TabTarget] {
        var targets = files.filter { $0.scope == scope && $0.device != device && now - $0.written < reach }
            .sorted { a, b in a.written != b.written ? a.written > b.written : a.device < b.device }
            .compactMap(read)
            .map { TabTarget(device: $0.device, name: $0.name, phone: $0.phone, seen: $0.written) }
        // Two called the same: each says when it was last heard from.
        let names = Dictionary(grouping: targets, by: \.name)
        for i in targets.indices where (names[targets[i].name]?.count ?? 0) > 1 {
            targets[i].label = "\(targets[i].name) \u{00B7} \(seen(targets[i].seen, now: now))"
        }
        return targets
    }

    /// Every other device with a tabs file in a scope, however long ago it
    /// was heard from, the one heard from last first: for Settings, to
    /// remove the ones that are gone.
    static func devices(_ files: [SyncFile], scope: String, device: String) -> [TabTarget] {
        files.filter { $0.scope == scope && $0.device != device }
            .sorted { a, b in a.written != b.written ? a.written > b.written : a.device < b.device }
            .compactMap(read)
            .map { TabTarget(device: $0.device, name: $0.name, phone: $0.phone, seen: $0.written) }
    }

    /// When the last sync was, for the line under Sync: "synced just now",
    /// "synced 4 min ago". Both apps sync every half minute, so it is
    /// nearly always just now. A clock a second ahead of the pass made
    /// Apple's relative wording say "in 0 seconds", which read as a
    /// countdown.
    static func synced(_ at: Date, now: Date = Date()) -> String {
        let ago = max(0, now.timeIntervalSince(at))
        if ago < 60 { return "synced just now" }
        if ago < 60 * 60 { return "synced \(Int(ago / 60)) min ago" }
        if ago < 24 * 60 * 60 { return "synced \(Int(ago / 3600)) h ago" }
        let days = Int(ago / 86400)
        return days == 1 ? "synced yesterday" : "synced \(days) days ago"
    }

    /// Names said once each, in order: four iPhones are "iPhone".
    static func once(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    /// When a device was last heard from, in a word or two: "active now",
    /// "seen 20 min ago", "seen 3 h ago", "seen 2 days ago".
    static func seen(_ at: Double, now: Double) -> String {
        let ago = max(0, now - at)
        if ago < 5 * 60 { return "active now" }
        if ago < 60 * 60 { return "seen \(Int(ago / 60)) min ago" }
        if ago < 24 * 60 * 60 { return "seen \(Int(ago / 3600)) h ago" }
        let days = Int(ago / 86400)
        return days == 1 ? "seen yesterday" : "seen \(days) days ago"
    }

    /// Pages the other devices sent to this one that it hasn't opened yet,
    /// the oldest first, so they open in the order they were sent.
    static func arrived(_ files: [SyncFile], scope: String, device: String, opened: Set<String>,
                        now: Double) -> [ArrivedTab] {
        var out: [ArrivedTab] = []
        for file in files where file.scope == scope && file.device != device {
            guard let from = read(file) else { continue }
            for tab in tidySent(from.sent, now: now) where tab.to == device && !opened.contains(tab.id) {
                out.append(ArrivedTab(from: from.device, fromName: from.name, tab: tab))
            }
        }
        return out.sorted { a, b in a.tab.at != b.tab.at ? a.tab.at < b.tab.at : a.tab.id < b.tab.id }
    }

    /// Every other device's tabs in a scope, the one heard from last first:
    /// not this device's, not one gone quiet, not one with nothing open.
    static func others(_ files: [SyncFile], scope: String, device: String, now: Double) -> [DeviceTabs] {
        files.filter { $0.scope == scope && $0.device != device && now - $0.written < stale }
            .compactMap(read)
            .filter { !$0.tabs.isEmpty }
            .sorted { a, b in a.written != b.written ? a.written > b.written : a.device < b.device }
    }

    /// Other devices' tabs that answer to what was typed, by title or
    /// address, the one looked at last first; every one when nothing was.
    static func matching(_ typed: String, in devices: [DeviceTabs]) -> [(device: DeviceTabs, tab: SyncedTab)] {
        let needle = typed.trimmingCharacters(in: .whitespaces).lowercased()
        return devices.flatMap { device in device.tabs.map { (device: device, tab: $0) } }
            .filter { pair in
                needle.isEmpty || pair.tab.title.lowercased().contains(needle) || pair.tab.url.lowercased().contains(needle)
            }
            .sorted { $0.tab.active > $1.tab.active }
    }
}

/// What this device sent and what it opened, kept with its settings: the
/// pages waiting in its own file for another device, by the scope they go
/// out in, and the ids of those that came here and were opened, so each
/// opens once. The same on the Mac and the iPhone.
struct SentBook {
    let defaults: UserDefaults
    static let outboxKey = "sync.sent"
    static let openedKey = "sync.opened"

    /// The pages waiting to be picked up in a scope.
    func outbox(_ scope: String, now: Double) -> [SentTab] {
        SyncTabs.tidySent(all[scope] ?? [], now: now)
    }

    func add(_ tab: SentTab, scope: String, now: Double) {
        var all = self.all
        all[scope] = SyncTabs.tidySent((all[scope] ?? []) + [tab], now: now)
        for (key, list) in all where list.isEmpty { all[key] = nil }
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: SentBook.outboxKey) }
    }

    private var all: [String: [SentTab]] {
        defaults.data(forKey: SentBook.outboxKey).flatMap { try? JSONDecoder().decode([String: [SentTab]].self, from: $0) } ?? [:]
    }

    /// The ids of pages that came here and were opened, with when, kept as
    /// long as their sender keeps them.
    var opened: Set<String> { Set(openedTimes.keys) }

    func markOpened(_ ids: [String], now: Double) {
        var times = openedTimes.filter { now - $0.value < SyncTabs.keepSent + 24 * 60 * 60 }
        for id in ids { times[id] = now }
        defaults.set(times, forKey: SentBook.openedKey)
    }

    private var openedTimes: [String: Double] {
        (defaults.dictionary(forKey: SentBook.openedKey) as? [String: Double]) ?? [:]
    }
}
