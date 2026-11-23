import AppKit
import Combine
import SystemConfiguration

// Sync with your other Macs, through a folder you choose.
//
// THE DECISION (17 Nov 2026): a folder, not iCloud's own APIs.
//   - CloudKit and NSUbiquitousKeyValueStore need an iCloud container and
//     the com.apple.developer.icloud-* / ubiquity-kvstore entitlements, tied
//     to a provisioning profile. Search.entitlements has none of them (only
//     camera, microphone, location and contacts); Search.passkeys.entitlements
//     adds only the web-browser passkey entitlement and its identifiers; and
//     build.sh signs a Developer ID build with one or the other. Taking that
//     route means a new Apple container, a new profile in every build and a
//     dependency on Apple's servers for a browser that has none of its own.
//   - The app is not sandboxed (no com.apple.security.app-sandbox), so a
//     folder chosen in an open panel is simply a path: no security-scoped
//     bookmark to keep.
//   So: Search writes small files into a folder the user picks — in iCloud
//   Drive, Dropbox, a shared disk — and whatever moves that folder between
//   Macs does the rest. No account, no server, nothing of ours in between.
//
// Off unless turned on (Settings › General › Sync with your other Macs).
//
// In the folder, "<name> Sync/<scope>/<device>.json" ("Quo Sync" in Quo): one file per Mac per
// scope, written only by that Mac, so two Macs never write the same file.
// The scopes: "app" for the settings below, and "profile-<id>" for each
// profile's spaces, pins and bookmarks — a profile's never mixes with
// another's. Each file is the whole merged view as that Mac last had it,
// item by item with stamps and tombstones (see SyncMerge.swift for the
// rules and the format).
//
// What syncs: spaces (name, colour or gradient, icon, order, and whether a
// space has sign-ins of its own — never the sign-ins themselves, its cookies,
// tabs or downloads folder), pins (each space's and the ones every space shows,
// their letter, name, page and order), bookmarks, and the settings listed in
// SyncSettings. History, with Sync history on, as each device's own record
// beside each profile's (SyncHistory.swift). What never does: passwords,
// cookies and site data,
// tab groups (they hold open tabs), private windows, extensions, the
// downloads folder, window sizes.
//
// Open tabs aren't merged with anyone's: each Mac, and Quo for iPhone, hands
// its own over as they are, in a scope of their own beside each profile's,
// "tabs-profile-<id>", and the other devices' show in ⌘T (SyncTabs.swift).
//
// Profiles: Personal is the same profile on every Mac. Another profile syncs
// with the profile of the same id on another Mac; one made separately on each
// Mac has a different id and stays apart (making them across Macs is still
// to come).
//
// A pass runs a moment after anything synced changes here, when a file in
// the folder changes, every half minute, and when Search comes forward. It
// reads a handful of small files and writes this Mac's only if it changed.

enum SyncSettings {
    struct Setting {
        let key: String
        let read: @MainActor (Preferences) -> String?
        let write: @MainActor (Preferences, String) -> Void
    }

    /// The settings that follow you: how Search looks and behaves, not what
    /// belongs to this Mac (folders, window sizes, passwords, extensions).
    @MainActor static let all: [Setting] = [
        raw("look", \.look),
        raw("glyph", \.glyph),
        raw("search.engine", \.engine),
        coded("search.custom", \.customEngine),
        coded("search.suggest", \.engineSuggests),
        coded("search.keywords", \.keywords),
        coded("spaces", \.usesSpaces),
        coded("pins.list", \.listsPins),
        coded("pins.home", \.pinsGoHome),
        raw("tabs.close.after", \.tabLife),
        raw("tabs.newPlace", \.newTabPlace),
        coded("tabs.shortcuts", \.showsTabShortcuts),
        coded("shield", \.shielded),
        coded("privacy.clickIDs", \.removesClickIDs),
        coded("privacy.gpc", \.sendsPrivacySignal),
        coded("bookmarks.bar", \.bookmarksBar),
        coded("quit.confirm", \.confirmsQuit),
    ]

    /// Their keys, readable anywhere (SyncItems.understood).
    static let known: Set<String> = [
        "look", "glyph", "search.engine", "search.custom", "search.suggest", "search.keywords", "spaces",
        "pins.list", "pins.home", "tabs.close.after", "tabs.newPlace", "tabs.shortcuts", "shield",
        "privacy.clickIDs", "privacy.gpc", "bookmarks.bar", "quit.confirm",
    ]

    private static func coded<T: Codable & Equatable>(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, T>) -> Setting {
        Setting(key: key, read: { SyncMerge.text($0[keyPath: path]) }, write: { prefs, text in
            guard let value = SyncMerge.value(T.self, text), prefs[keyPath: path] != value else { return }
            prefs[keyPath: path] = value
        })
    }

    private static func raw<T: RawRepresentable & Equatable>(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, T>) -> Setting
        where T.RawValue: Codable {
        Setting(key: key, read: { SyncMerge.text($0[keyPath: path].rawValue) }, write: { prefs, text in
            guard let raw = SyncMerge.value(T.RawValue.self, text), let value = T(rawValue: raw),
                  prefs[keyPath: path] != value else { return }
            prefs[keyPath: path] = value
        })
    }

    @MainActor static func items(_ prefs: Preferences) -> [String: String] {
        var out: [String: String] = [:]
        for setting in all { out["set:" + setting.key] = setting.read(prefs) }
        return out
    }

    @MainActor static func apply(_ live: [String: String], to prefs: Preferences) {
        for setting in all {
            if let text = live["set:" + setting.key] { setting.write(prefs, text) }
        }
    }
}

@MainActor
final class Sync: ObservableObject {
    static let shared = Sync()

    /// The folder chosen; nil unless syncing through a folder.
    @Published private(set) var folder: URL?
    /// Syncing through iCloud instead (SyncCloud.swift).
    @Published private(set) var cloud = false
    @Published private(set) var lastSynced: Date?
    /// Why the last pass couldn't run, for Settings.
    @Published private(set) var problem: String?
    /// The other Macs whose files were read, by name.
    @Published private(set) var others: [String] = []
    /// The open tabs of the other devices, an iPhone's among them, by the
    /// scope of the profile they are in ("profile-<id>").
    @Published private(set) var elsewhere: [String: [DeviceTabs]] = [:]
    /// The app went to the back: this Mac's tabs are written in the next
    /// pass even if it wrote them a moment ago, for the iPhone in your hand.
    private var going = false

    var on: Bool { folder != nil || cloud }

    /// Where it syncs, as Settings offers it.
    enum Way: String, CaseIterable { case off, icloud, folder }
    var way: Way { cloud ? .icloud : folder != nil ? .folder : .off }

    nonisolated static let cloudKey = "sync.icloud"
    private lazy var store = SyncCloud()

    nonisolated static let folderKey = "sync.folder"
    nonisolated static let deviceKey = "sync.device"
    /// The folder the app makes inside the one chosen, named for it:
    /// "Search Sync", or "Quo Sync" in Quo.
    nonisolated static let inside = "\(Store.name) Sync"
    /// What a fork's folder was called before it took the app's name.
    nonisolated static let former = "Search Sync"

    /// This Mac's id in the folder: made once, kept with the settings, so
    /// each test world (SEARCH_PROBE=<name>) is a Mac of its own.
    let device: String = {
        if let kept = Store.settings.string(forKey: Sync.deviceKey), !kept.isEmpty { return kept }
        let made = UUID().uuidString
        Store.settings.set(made, forKey: Sync.deviceKey)
        return made
    }()

    private var bag: Set<AnyCancellable> = []
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var watchers: [String: DispatchSourceFileSystemObject] = [:]
    private var running = false

    private init() {}

    // MARK: - on and off

    /// At launch: carries on if it was on.
    func start() {
        guard !on else { return }
        if Store.settings.bool(forKey: Sync.cloudKey), SyncCloud.available {
            cloud = true
            return begin()
        }
        guard let path = Store.settings.string(forKey: Sync.folderKey), !path.isEmpty else { return }
        folder = URL(fileURLWithPath: path, isDirectory: true)
        begin()
    }

    /// iCloud chosen: whatever this Mac did before is put down, and it joins
    /// what is in iCloud as a Mac joining.
    func turnOnCloud() {
        guard SyncCloud.available else { return }
        if on { turnOff() }
        for scope in scopes { try? FileManager.default.removeItem(at: Sync.stateFile(scope)) }
        store.forget()
        Store.settings.set(true, forKey: Sync.cloudKey)
        cloud = true
        begin()
    }

    /// A silent push from the zone's subscription: another Mac wrote.
    func heard() {
        pushes += 1
        schedule(after: 0.5)
    }
    /// How many pushes came, for the bench.
    private(set) var pushes = 0
    /// What registering for pushes came to, for the bench.
    var pushRegistration = ""

    /// Settings › Sync Now.
    func syncNow() {
        guard on else { return }
        pending?.cancel()
        pending = nil
        pass()
    }

    /// The next pass no sooner than iCloud asked for.
    private func retry(after seconds: TimeInterval) {
        let delay = max(2, seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.schedule(after: 0) }
        }
    }

    /// The switch turned on: a folder asked for, then the first pass.
    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Choose a folder your Macs share, in iCloud Drive or Dropbox for example. Turn on sync with the same folder in \(Store.name) on each Mac."
        panel.prompt = "Sync Here"
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: drive.path) { panel.directoryURL = drive }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        turnOn(url)
    }

    func turnOn(_ url: URL) {
        if cloud { turnOff() }
        stop()
        // Always as a Mac joining: what it agreed with another folder, or
        // with this one long ago, says nothing about what is there now.
        for scope in scopes { try? FileManager.default.removeItem(at: Sync.stateFile(scope)) }
        Store.settings.set(url.path, forKey: Sync.folderKey)
        folder = url
        begin()
    }

    /// Off: this Mac's files leave the folder and what it had agreed is
    /// forgotten, so turning it on again starts as a Mac joining. What is in
    /// the browser stays as it is.
    func turnOff() {
        if let root {
            for scope in scopes + tabScopes + historyScopes {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(scope).appendingPathComponent(device + ".json"))
            }
        }
        if cloud {
            let store = self.store, device = self.device
            Task { await store.removeOwn(device: device) }
        }
        for scope in scopes { try? FileManager.default.removeItem(at: Sync.stateFile(scope)) }
        stop()
        Store.settings.removeObject(forKey: Sync.folderKey)
        Store.settings.removeObject(forKey: Sync.cloudKey)
        folder = nil
        cloud = false
        lastSynced = nil
        problem = nil
        others = []
        elsewhere = [:]
        going = false
    }

    private func begin() {
        if Store.testing { SyncHistory.every = 1 }
        let poke: (Notification) -> Void = { [weak self] _ in self?.schedule() }
        for name in [Spaces.changed, Pins.changed, Bookmarks.saved, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.publisher(for: name).sink(receiveValue: poke).store(in: &bag)
        }
        // Leaving the Mac for the iPhone: its tabs go now, not in half a minute.
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification).sink { [weak self] _ in
            self?.going = true
            self?.schedule(after: 0.5)
        }.store(in: &bag)
        Shared.prefs.objectWillChange.sink { [weak self] in self?.schedule() }.store(in: &bag)
        // Something forgotten from the history: your other devices told soon.
        History.forgot.sink { [weak self] in self?.schedule(after: 1) }.store(in: &bag)
        // Signed out of iCloud, or into another Apple ID: looked at again.
        if cloud {
            NotificationCenter.default.publisher(for: .CKAccountChanged)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.schedule(after: 1) }
                .store(in: &bag)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pass() }
        }
        schedule(after: 1)
    }

    private func stop() {
        bag.removeAll()
        timer?.invalidate()
        timer = nil
        pending?.cancel()
        pending = nil
        for watcher in watchers.values { watcher.cancel() }
        watchers = [:]
    }

    /// A pass a moment from now; anything else that changes meanwhile joins it.
    private func schedule(after delay: TimeInterval = 2) {
        guard on, !running else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.pass() } }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - where

    private var root: URL? {
        guard let folder else { return nil }
        let root = folder.appendingPathComponent(Sync.inside, isDirectory: true)
        Sync.carryOver(to: root, in: folder)
        return root
    }

    /// A fork's folder, made as "Search Sync" before it took the app's name,
    /// moved to its own name once, with everything in it: never while one
    /// of the new name is already there, and never in Search itself.
    nonisolated static func carryOver(to root: URL, in folder: URL) {
        guard inside != former else { return }
        let old = folder.appendingPathComponent(former, isDirectory: true)
        let files = FileManager.default
        guard !files.fileExists(atPath: root.path), files.fileExists(atPath: old.path) else { return }
        try? files.moveItem(at: old, to: root)
    }

    private var scopes: [String] { ["app"] + Profiles.shared.list.map { Sync.scope($0.id) } }
    /// Each profile's open tabs' scope (SyncTabs.swift): never merged, so
    /// not among `scopes`, which are.
    private var tabScopes: [String] { Profiles.shared.list.map { SyncTabs.scope(Sync.scope($0.id)) } }

    nonisolated static func scope(_ profile: UUID) -> String { "profile-" + profile.uuidString }
    /// Each profile's history's scope (SyncHistory.swift): never merged
    /// item by item, each device's record its own.
    private var historyScopes: [String] { Profiles.shared.list.map { SyncHistory.scope(Sync.scope($0.id)) } }

    /// Whether this Mac's history goes to the others: Sync history on, and
    /// another device seen, a Mac or Quo for iPhone. Alone, nothing is sent.
    private var historyShared: Bool {
        Shared.prefs.syncsHistory && (!others.isEmpty || elsewhere.values.contains { !$0.isEmpty })
    }

    /// The others' history made here: first everything any of them forgot,
    /// then their pages, none that any of them, or this Mac, forgot since.
    static func takeHistory(_ theirs: [DeviceHistory], into history: History) {
        for other in theirs { history.forget(handed: other.forgets) }
        var forgot = history.forgets
        for other in theirs {
            if let all = other.forgets.all { forgot.all = max(forgot.all ?? 0, all) }
            forgot.pages.merge(other.forgets.pages) { max($0, $1) }
        }
        for other in theirs { history.take(handed: SyncHistory.taken(other.visits, mine: forgot)) }
    }

    /// Each profile's history through the folder: the others' read and
    /// taken in, this Mac's written when due.
    private func runHistory(in root: URL) {
        guard Shared.prefs.syncsHistory else { return }
        let now = Date().timeIntervalSince1970
        for profile in Profiles.shared.list {
            let scope = SyncHistory.scope(Sync.scope(profile.id))
            let folder = root.appendingPathComponent(scope, isDirectory: true)
            guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { continue }
            let own = folder.appendingPathComponent(device + ".json")
            let history = Profiles.history(profile.id)
            guard !history.stillLoading else { continue }
            Sync.takeHistory(SyncHistory.others(theirFiles(in: folder, scope: scope, own: own), scope: scope, device: device), into: history)
            guard historyShared else { continue }
            let mine = history.handed(), forgets = history.forgets
            let written = (try? Data(contentsOf: own)).flatMap { SyncMerge.decode($0, scope: scope) }
            guard !mine.isEmpty || !forgets.isEmpty,
                  SyncHistory.due(written, visits: mine, forgets: forgets, name: Sync.macName, now: now) else { continue }
            let file = SyncHistory.file(device: device, name: Sync.macName, scope: scope, visits: mine, forgets: forgets, now: now)
            if let data = SyncMerge.encode(file) { try? data.write(to: own, options: .atomic) }
        }
    }

    /// What this Mac last agreed with the folder, per scope: in Search's own
    /// folder, never in the shared one.
    nonisolated static func stateFile(_ scope: String) -> URL { Store.file("sync-\(scope).json") }

    // MARK: - a pass

    func pass() {
        if cloud { return cloudPass() }
        guard let folder, let root, !running else { return }
        pending?.cancel()
        pending = nil
        // A folder not there — a disk not plugged in, Dropbox not running —
        // is no reason to think everything was deleted: nothing happens.
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            problem = "The folder isn\u{2019}t there"
            return
        }
        running = true
        defer { running = false }
        var seen = Set<String>()
        let prefs = Shared.prefs
        seen.formUnion(run(scope: "app", in: root, current: { _ in SyncSettings.items(prefs) }, apply: { live in
            SyncSettings.apply(live, to: prefs)
        }))
        for profile in Profiles.shared.list {
            seen.formUnion(run(scope: Sync.scope(profile.id), in: root,
                               current: { Sync.items(of: profile.id, base: $0) },
                               apply: { Sync.apply($0, to: profile) }))
        }
        if problem == nil { runTabs(in: root) }
        if problem == nil { runHistory(in: root) }
        others = seen.sorted()
        if problem == nil { lastSynced = Date() }
    }

    /// One scope: stamped, merged with the other Macs' files, applied, and
    /// written. The names of the other Macs read.
    private func run(scope: String, in root: URL, current: ([String: String]) -> [String: String],
                     apply: ([String: String]) -> Void) -> [String] {
        let files = FileManager.default
        let folder = root.appendingPathComponent(scope, isDirectory: true)
        do {
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            problem = "\(Store.name) can\u{2019}t write in that folder"
            return []
        }
        problem = nil
        watch(folder, scope: scope)
        let now = Date().timeIntervalSince1970
        let own = folder.appendingPathComponent(device + ".json")
        let read = theirFiles(in: folder, scope: scope, own: own)
        let theirs = read.map(\.items)
        let names = read.map { $0.name ?? "Another Mac" }

        let merged = merge(scope: scope, theirs: theirs, now: now, current: current, apply: apply)
        // This Mac's file, only when it says something new.
        let written = (try? Data(contentsOf: own)).flatMap { SyncMerge.decode($0, scope: scope) }
        if written?.items != merged || written?.name != Sync.macName {
            let file = SyncFile(format: SyncMerge.format, device: device, name: Sync.macName, scope: scope, written: now, items: merged)
            if let data = SyncMerge.encode(file) { try? data.write(to: own, options: .atomic) }
        }
        return names
    }

    /// The other devices' files in a scope's folder, those that are there
    /// to be read now.
    private func theirFiles(in folder: URL, scope: String, own: URL) -> [SyncFile] {
        let files = FileManager.default
        var out: [SyncFile] = []
        for url in (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            let name = url.lastPathComponent
            // iCloud Drive keeps a file it has let go of as ".<name>.icloud",
            // or as a file with nothing in it yet: asked for, it is there
            // for a later pass. Read now, the read would wait for it.
            if name.hasPrefix("."), name.hasSuffix(".json.icloud") {
                try? files.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard name.hasSuffix(".json"), url != own else { continue }
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               status != .current {
                try? files.startDownloadingUbiquitousItem(at: url)
                continue
            }
            guard let data = try? Data(contentsOf: url), data.count < 32 << 20,
                  let file = SyncMerge.decode(data, scope: scope), file.device != device
            else { continue }
            out.append(file)
        }
        return out
    }

    /// Each profile's open tabs through the folder: the other devices'
    /// read, and this Mac's written when they changed (SyncTabs.swift).
    private func runTabs(in root: URL) {
        let now = Date().timeIntervalSince1970
        let going = self.going
        self.going = false
        var found: [String: [DeviceTabs]] = [:]
        for profile in Profiles.shared.list {
            let scope = SyncTabs.scope(Sync.scope(profile.id))
            let folder = root.appendingPathComponent(scope, isDirectory: true)
            guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { continue }
            let own = folder.appendingPathComponent(device + ".json")
            found[Sync.scope(profile.id)] = SyncTabs.others(theirFiles(in: folder, scope: scope, own: own),
                                                            scope: scope, device: device, now: now)
            // Before a window is up there is nothing to say yet, not "none".
            guard !Browsers.all.isEmpty else { continue }
            let mine = Sync.openTabs(of: profile.id)
            let written = (try? Data(contentsOf: own)).flatMap { SyncMerge.decode($0, scope: scope) }
            guard SyncTabs.due(written, tabs: mine.tabs, spaces: mine.spaces, name: Sync.macName, now: now, going: going) else { continue }
            let file = SyncTabs.file(device: device, name: Sync.macName, phone: false, scope: scope,
                                     tabs: mine.tabs, spaces: mine.spaces, now: now)
            if let data = SyncMerge.encode(file) { try? data.write(to: own, options: .atomic) }
        }
        if elsewhere != found { elsewhere = found }
    }

    /// One scope's items merged with the other Macs', applied here, and what
    /// this Mac agreed kept: the same for the folder and for iCloud. A Mac
    /// joining takes what the others agreed where both have something; the
    /// first Mac there sets it.
    private func merge(scope: String, theirs: [[String: SyncEntry]], now: Double,
                       current: ([String: String]) -> [String: String],
                       apply: ([String: String]) -> Void) -> [String: SyncEntry] {
        let stateURL = Sync.stateFile(scope)
        let state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode([String: SyncEntry].self, from: $0) }
        let base = state ?? [:]
        let here = current(SyncMerge.live(base))
        let merged = SyncMerge.pass(current: here, base: state, theirs: theirs, device: device, now: now,
                                    understood: SyncItems.understood)
        let live = SyncMerge.live(merged)
        if live != here { apply(live) }
        if merged != base, let data = try? JSONEncoder().encode(merged) {
            try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: stateURL, options: .atomic)
        }
        return merged
    }

    /// A pass through iCloud: what changed fetched, each scope merged as the
    /// folder's are, and this Mac's record saved where it says something new.
    private func cloudPass() {
        guard cloud, !running else { return }
        pending?.cancel()
        pending = nil
        running = true
        let store = self.store
        Task { @MainActor in
            defer { running = false }
            do {
                // Another Apple ID than last time: what this Mac agreed with
                // the old one is forgotten, and it joins the new one's as a
                // Mac joining, never pouring one account into the other.
                if try await store.prepare() {
                    for scope in scopes { try? FileManager.default.removeItem(at: Sync.stateFile(scope)) }
                }
                try await store.fetchChanges()
            } catch {
                problem = SyncCloud.describe(error)
                // iCloud asked for a pause: the next pass waits for it.
                if let wait = SyncCloud.retryAfter(error) { retry(after: wait) }
                return
            }
            problem = nil
            let prefs = Shared.prefs
            var work: [(String, ([String: String]) -> [String: String], ([String: String]) -> Void)] = [
                ("app", { _ in SyncSettings.items(prefs) }, { SyncSettings.apply($0, to: prefs) }),
            ]
            for profile in Profiles.shared.list {
                work.append((Sync.scope(profile.id), { Sync.items(of: profile.id, base: $0) }, { Sync.apply($0, to: profile) }))
            }
            var seen = Set<String>()
            let now = Date().timeIntervalSince1970
            for (scope, current, apply) in work {
                let theirs = store.files(in: scope).filter { $0.device != device }
                seen.formUnion(theirs.map { $0.name ?? "Another Mac" })
                let merged = merge(scope: scope, theirs: theirs.map(\.items), now: now, current: current, apply: apply)
                let own = store.file(scope: scope, device: device)
                guard own?.items != merged || own?.name != Sync.macName else { continue }
                let file = SyncFile(format: SyncMerge.format, device: device, name: Sync.macName, scope: scope, written: now, items: merged)
                do { try await store.save(file) } catch {
                    problem = SyncCloud.describe(error)
                    if let wait = SyncCloud.retryAfter(error) { retry(after: wait) }
                }
            }
            // Each profile's open tabs: the other devices' read, this Mac's
            // saved when they changed (SyncTabs.swift).
            let going = self.going
            self.going = false
            var found: [String: [DeviceTabs]] = [:]
            for profile in Profiles.shared.list {
                let scope = SyncTabs.scope(Sync.scope(profile.id))
                found[Sync.scope(profile.id)] = SyncTabs.others(store.files(in: scope), scope: scope, device: device, now: now)
                guard problem == nil, !Browsers.all.isEmpty else { continue }
                let mine = Sync.openTabs(of: profile.id)
                guard SyncTabs.due(store.file(scope: scope, device: device), tabs: mine.tabs, spaces: mine.spaces,
                                   name: Sync.macName, now: now, going: going) else { continue }
                let file = SyncTabs.file(device: device, name: Sync.macName, phone: false, scope: scope,
                                         tabs: mine.tabs, spaces: mine.spaces, now: now)
                do { try await store.save(file) } catch {
                    problem = SyncCloud.describe(error)
                    if let wait = SyncCloud.retryAfter(error) { retry(after: wait) }
                }
            }
            if elsewhere != found { elsewhere = found }
            others = seen.sorted()
            // Each profile's history: the others' taken in, this Mac's saved
            // when due (SyncHistory.swift).
            if Shared.prefs.syncsHistory {
                for profile in Profiles.shared.list {
                    let scope = SyncHistory.scope(Sync.scope(profile.id))
                    let history = Profiles.history(profile.id)
                    guard !history.stillLoading else { continue }
                    Sync.takeHistory(SyncHistory.others(store.files(in: scope), scope: scope, device: device), into: history)
                    guard problem == nil, historyShared else { continue }
                    let mine = history.handed(), forgets = history.forgets
                    guard !mine.isEmpty || !forgets.isEmpty,
                          SyncHistory.due(store.file(scope: scope, device: device), visits: mine, forgets: forgets,
                                          name: Sync.macName, now: now) else { continue }
                    let file = SyncHistory.file(device: device, name: Sync.macName, scope: scope, visits: mine, forgets: forgets, now: now)
                    do { try await store.save(file) } catch {
                        problem = SyncCloud.describe(error)
                        if let wait = SyncCloud.retryAfter(error) { retry(after: wait) }
                    }
                }
            }
            if problem == nil { lastSynced = Date() }
        }
    }

    /// A file of another Mac arriving or changing: a pass soon.
    private func watch(_ folder: URL, scope: String) {
        guard watchers[scope] == nil else { return }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.schedule() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watchers[scope] = source
    }

    nonisolated static var macName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    // MARK: - a profile's things

    /// A profile's spaces, pins and bookmarks as items.
    static func items(of profile: UUID, base: [String: String]) -> [String: String] {
        let spaces = Spaces.read(profile: profile)
        var bySpace: [UUID: [PinDef]] = [:]
        for space in spaces {
            let defs = Pins.defs(space.id)
            if !defs.isEmpty { bySpace[space.id] = defs }
        }
        var out = SyncItems.spaces(spaces, base: base)
        out.merge(SyncItems.pins(bySpace: bySpace, shared: Pins.shared(profile), base: base)) { a, _ in a }
        out.merge(SyncItems.bookmarks(Profiles.bookmarks(profile).roots)) { a, _ in a }
        return out
    }

    /// The merged items made so: spaces first, so pins have their space.
    static func apply(_ live: [String: String], to profile: Profile) {
        let id = profile.id
        let home = id == Profile.personalID ? Space.firstID : profile.home
        let local = Spaces.read(profile: id)
        let spaces = SyncItems.applySpaces(live, to: local, profile: id, home: home)
        for gone in local where !spaces.contains(where: { $0.id == gone.id }) {
            removeSpace(gone, profile: id)
        }
        if spaces != Spaces.read(profile: id) {
            // The order is the one merged, wherever the home is in it.
            Store.settings.set(true, forKey: "spaces.orderKept")
            Spaces.write(spaces, profile: id)
        }

        var localPins: [UUID: [PinDef]] = [:]
        for space in spaces { localPins[space.id] = Pins.defs(space.id) }
        let pins = SyncItems.applyPins(live, spaces: spaces.map(\.id), local: localPins, localShared: Pins.shared(id))
        Pins.adopt(pins.bySpace, in: spaces.map(\.id), shared: pins.shared, profile: id)

        Profiles.bookmarks(id).adopt(SyncItems.applyBookmarks(live))
    }

    /// A space deleted on another Mac: as Delete Space does here — its tabs,
    /// its pins, and, for one with sign-ins of its own, those too.
    private static func removeSpace(_ space: Space, profile: UUID) {
        if let window = Browsers.all.first(where: { $0.profileID == profile && !$0.isPopup && $0.spaces.contains { $0.id == space.id } }) {
            window.deleteSpace(space.id)
            return
        }
        Spaces.write(Spaces.read(profile: profile).filter { $0.id != space.id }, profile: profile)
        Session.erase(space: space.id)
        Pins.forget(space.id)
        if space.sharesSignIns != true { Spaces.erase(space.id) }
    }

    // MARK: - open tabs

    /// The other devices' open tabs in a profile, the one heard from last
    /// first.
    func elsewhere(_ profile: UUID) -> [DeviceTabs] { elsewhere[Sync.scope(profile)] ?? [] }

    /// A profile's open tabs on this Mac, every window's and every space's,
    /// for the other devices: not private ones, not pins (they sync as
    /// pins), not a script's or an agent's, nor those in a group an agent
    /// made; not a pop-up's or a window closed for good.
    static func openTabs(of profile: UUID) -> (tabs: [SyncedTab], spaces: [SyncedTabSpace]) {
        var tabs: [SyncedTab] = []
        for browser in Browsers.all where browser.profileID == profile && !browser.isPopup && !browser.retired && !browser.shut {
            var rows: [(space: UUID, tabs: [Tab], groups: [TabGroup])] = [(browser.spaceID, browser.tabs, browser.tabGroups)]
            for (space, row) in browser.parked { rows.append((space, row.tabs, row.groups ?? [])) }
            for row in rows {
                let agents = Set(row.groups.filter { $0.agent != nil }.map(\.id))
                for tab in row.tabs where !tab.shy && !tab.bench && !tab.agent && !tab.popup && tab.pin == nil {
                    if let group = tab.groupID, agents.contains(group) { continue }
                    guard let url = tab.address, SyncTabs.handed(url.absoluteString) else { continue }
                    tabs.append(SyncedTab(url: url.absoluteString, title: tab.label, space: row.space.uuidString,
                                          active: tab.touched.timeIntervalSince1970))
                }
            }
        }
        let spaces = Spaces.read(profile: profile).map { SyncedTabSpace(id: $0.id.uuidString, name: $0.name) }
        return (tabs, spaces)
    }

    // MARK: - for Settings

    /// Where, and when last, in a line.
    var summary: String {
        if cloud {
            if let problem { return "iCloud: \(problem.lowercased())" }
            guard let lastSynced else { return "iCloud" }
            let when = RelativeDateTimeFormatter().localizedString(for: lastSynced, relativeTo: Date())
            let with = others.isEmpty ? "no other Mac yet" : others.joined(separator: ", ")
            return "iCloud · \(with) · \(when)"
        }
        guard let folder else { return "" }
        var place = folder.path
        let drive = NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs"
        if place.hasPrefix(drive) { place = "iCloud Drive" + place.dropFirst(drive.count) }
        place = place.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        if let problem { return "\(place): \(problem.lowercased())" }
        guard let lastSynced else { return place }
        let when = RelativeDateTimeFormatter().localizedString(for: lastSynced, relativeTo: Date())
        let with = others.isEmpty ? "no other Mac yet" : others.joined(separator: ", ")
        return "\(place) · \(with) · \(when)"
    }
}
