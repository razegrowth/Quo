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
// "spaces", the names of the spaces they are in; and "kind", "mac" or
// "iphone". Each stamped when the file was written, by its device.
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
    /// How often a device writes its tabs at most, unless it is going away
    /// (put in the background, or another app comes forward). Under the
    /// Mac's half-minute pass, so the next pass after a change writes it.
    static let every: Double = 20

    static let tabsKey = "tabs"
    static let spacesKey = "spaces"
    static let kindKey = "kind"

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
                     tabs: [SyncedTab], spaces: [SyncedTabSpace], now: Double) -> SyncFile {
        let list = tidy(tabs)
        let used = Set(list.compactMap(\.space))
        let named = spaces.filter { used.contains($0.id) }
        func entry(_ text: String?) -> SyncEntry { SyncEntry(v: text, t: now, d: device) }
        let items: [String: SyncEntry] = [
            tabsKey: entry(SyncMerge.text(list)),
            spacesKey: entry(SyncMerge.text(named)),
            kindKey: entry(SyncMerge.text(phone ? "iphone" : "mac")),
        ]
        return SyncFile(format: SyncMerge.format, device: device, name: name, scope: scope, written: now, items: items)
    }

    /// What a device's tabs file says; nil for one that isn't a tabs file
    /// this build can read.
    static func read(_ file: SyncFile) -> DeviceTabs? {
        guard isTabs(file.scope), let text = file.items[tabsKey]?.v,
              let tabs = SyncMerge.value([SyncedTab].self, text) else { return nil }
        let spaces = file.items[spacesKey]?.v.flatMap { SyncMerge.value([SyncedTabSpace].self, $0) } ?? []
        let kind = file.items[kindKey]?.v.flatMap { SyncMerge.value(String.self, $0) }
        return DeviceTabs(device: file.device, name: file.name ?? (kind == "iphone" ? "iPhone" : "Mac"),
                          phone: kind == "iphone", written: file.written,
                          tabs: tabs.filter { handed($0.url) }, spaces: spaces)
    }

    /// Whether a file already says these tabs: nothing new to write.
    static func says(_ file: SyncFile?, tabs: [SyncedTab], spaces: [SyncedTabSpace], name: String) -> Bool {
        guard let file, file.name == name, let read = read(file) else { return false }
        let list = tidy(tabs)
        let used = Set(list.compactMap(\.space))
        return read.tabs == list && read.spaces == spaces.filter { used.contains($0.id) }
    }

    /// Whether this device should write its tabs now: they changed, and it
    /// last wrote them long enough ago, or it is going away.
    static func due(_ file: SyncFile?, tabs: [SyncedTab], spaces: [SyncedTabSpace], name: String,
                    now: Double, going: Bool) -> Bool {
        guard !says(file, tabs: tabs, spaces: spaces, name: name) else { return false }
        guard let written = file?.written, !going else { return true }
        return now - written >= every || now < written
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
