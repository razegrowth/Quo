import CloudKit
import Foundation
import UIKit

// Sync with Quo on the Mac, through the person's own iCloud: the same
// CloudKit records the Mac writes (SyncRecord.swift, built here from the
// Mac's sources), merged by the same rules (SyncMerge.swift, likewise). The
// iPhone is one more device: it reads every Mac's file in each scope, merges
// them as a Mac would, and writes its own, so a pin made here reaches the
// Mac and the Mac's spaces, pins and bookmarks are here.
//
// What the iPhone takes: the spaces, pins and bookmarks of the Personal
// profile, the Mac's search engine, and each Mac's open tabs. What it gives:
// its own pins, and its own open tabs (never incognito ones). Open tabs are
// never merged: each device hands over its own (SyncTabs.swift, built here
// from the Mac's sources too). It never writes the Mac's settings.
//
// Where the build carries no iCloud entitlement (a simulator build), or
// QUO_STANDIN names a folder, a folder stands in for iCloud, as the Mac's
// tests do: each record a "<name>.record" file ({scope, data}), or a copy
// of the Mac's own cache of what it fetched (sync-cloud.json).

@MainActor
protocol SyncBackend: AnyObject {
    var label: String { get }
    func prepare() async throws -> String
    /// What changed since `token`; `complete` when it is everything.
    func fetch(since token: Data?) async throws -> (changed: [String: SyncFile], deleted: [String], token: Data?, more: Bool, complete: Bool)
    func save(_ file: SyncFile, as name: String) async throws
    func delete(_ name: String) async throws
}

@MainActor
final class MacSync: ObservableObject {
    static let shared = MacSync()

    // What the Mac's records say, for the Personal profile.
    @Published private(set) var spaces: [Space] = []
    @Published private(set) var pinsBySpace: [UUID: [PinDef]] = [:]
    @Published private(set) var sharedPins: [PinDef] = []
    @Published private(set) var bookmarks: [Bookmark] = []
    /// Each Mac's open tabs (and any other device's), the one heard from
    /// last first.
    @Published private(set) var elsewhere: [DeviceTabs] = []
    @Published var currentSpaceID: UUID {
        didSet { UserDefaults.standard.set(currentSpaceID.uuidString, forKey: "sync.space") }
    }

    // How it's going, for Settings.
    @Published private(set) var lastSynced: Date?
    @Published private(set) var problem: String?
    @Published private(set) var macs: [String] = []
    @Published private(set) var running = false
    @Published var on: Bool {
        didSet {
            UserDefaults.standard.set(on, forKey: "sync.on")
            if on { pass() } else { withdrawTabs() }
        }
    }

    let device: String = {
        if let kept = UserDefaults.standard.string(forKey: "sync.device"), !kept.isEmpty { return kept }
        let made = UUID().uuidString
        UserDefaults.standard.set(made, forKey: "sync.device")
        return made
    }()

    static let personal = "profile-" + Profile.personalID.uuidString
    /// The Personal profile's open tabs, every device's.
    static let tabsScope = SyncTabs.scope(personal)

    /// Every device's file, as last fetched, by record name: the Mac's
    /// own cache format.
    private var files: [String: SyncFile] = [:]
    private var token: Data?
    /// Changes made here since the last pass, by scope: an item's new
    /// text, or nil for one removed.
    private var edits: [String: [String: String?]] = [:]
    private var backend: SyncBackend?
    private var timer: Timer?
    /// Going to the background: this iPhone's tabs are written in the next
    /// pass even if they were a moment ago, for the Mac you turn to.
    private var going = false
    private var tabsSoon: DispatchWorkItem?

    private init() {
        UserDefaults.standard.register(defaults: ["sync.on": true])
        on = UserDefaults.standard.bool(forKey: "sync.on")
        currentSpaceID = UserDefaults.standard.string(forKey: "sync.space").flatMap(UUID.init(uuidString:)) ?? Space.firstID
        files = Store.read([String: SyncFile].self, "sync-cloud.json") ?? [:]
        token = try? Data(contentsOf: Store.file("sync-cloud-token"))
        edits = Store.read([String: [String: String?]].self, "sync-edits.json") ?? [:]
        rebuild()
    }

    // MARK: - where

    static var cloudKitBuilt: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "QuoCloudKit") as? String)?.uppercased() == "YES"
    }

    /// A stand-in folder: QUO_STANDIN, or StandIn in Quo's own folder when
    /// it exists (the simulator's way of being given the Mac's records).
    static var standIn: URL? {
        if let path = ProcessInfo.processInfo.environment["QUO_STANDIN"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let local = Store.folder.appendingPathComponent("StandIn", isDirectory: true)
        return FileManager.default.fileExists(atPath: local.path) ? local : nil
    }

    var way: String {
        if MacSync.standIn != nil { return "A stand-in folder" }
        return MacSync.cloudKitBuilt ? "iCloud" : "Not available in this build"
    }

    var available: Bool { MacSync.standIn != nil || MacSync.cloudKitBuilt }

    private func makeBackend() -> SyncBackend? {
        if let folder = MacSync.standIn { return FolderBackend(folder: folder) }
        if MacSync.cloudKitBuilt { return CloudBackend() }
        return nil
    }

    // MARK: - a pass

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { MacSync.shared.pass() }
        }
        pass()
    }

    /// Fetch what changed, merge each scope as a Mac would, keep and show
    /// it, and write this iPhone's file where it says something new.
    func pass() {
        guard !running else { return }
        guard on, available else {
            // Off: what's here is still merged with what was made here.
            settleLocally()
            return
        }
        if backend == nil { backend = makeBackend() }
        guard let backend else { return }
        running = true
        Task { @MainActor in
            defer { running = false }
            do {
                let account = try await backend.prepare()
                let before = UserDefaults.standard.string(forKey: "sync.account")
                if before != nil, before != account { forgetFetched() }
                UserDefaults.standard.set(account, forKey: "sync.account")
                var more = true
                while more {
                    let changes: (changed: [String: SyncFile], deleted: [String], token: Data?, more: Bool, complete: Bool)
                    do {
                        changes = try await backend.fetch(since: token)
                    } catch let error as CKError where error.code == .changeTokenExpired {
                        token = nil
                        files = [:]
                        continue
                    }
                    if changes.complete { files = [:] }
                    files.merge(changes.changed) { $1 }
                    for name in changes.deleted { files[name] = nil }
                    token = changes.token
                    more = changes.more
                }
                keepFetched()
            } catch {
                problem = MacSync.describe(error)
                return
            }
            problem = nil
            let now = Date().timeIntervalSince1970
            // Only the Personal profile's: the one the iPhone shows.
            for scope in [MacSync.personal] {
                let merged = merge(scope: scope, now: now)
                let own = files[SyncRecord.name(scope: scope, device: device)]
                guard own?.items != merged || own?.name != MacSync.deviceName else { continue }
                // Only once there is something of the Mac's to join, or
                // something of the iPhone's to give.
                guard !merged.isEmpty else { continue }
                let file = SyncFile(format: SyncMerge.format, device: device, name: MacSync.deviceName, scope: scope, written: now, items: merged)
                do {
                    try await backend.save(file, as: SyncRecord.name(scope: scope, device: device))
                    files[SyncRecord.name(scope: scope, device: device)] = file
                    keepFetched()
                } catch {
                    problem = MacSync.describe(error)
                }
            }
            await publishTabs(with: backend, now: now)
            macs = Array(Set(files.values.filter { $0.device != device }.map { $0.name ?? "A Mac" })).sorted()
            readSettings()
            rebuild()
            if problem == nil { lastSynced = Date() }
        }
    }

    // MARK: - open tabs

    /// This iPhone's open tabs, written when they changed and it last wrote
    /// them long enough ago (SyncTabs.every), or it is going to the
    /// background. Only once a Mac is there to read them.
    private func publishTabs(with backend: SyncBackend, now: Double) async {
        let going = self.going
        self.going = false
        guard problem == nil, files.values.contains(where: { $0.device != device }) else { return }
        let scope = MacSync.tabsScope, name = SyncRecord.name(scope: scope, device: device)
        let mine = MacSync.ownTabs()
        guard SyncTabs.due(files[name], tabs: mine, spaces: [], name: MacSync.deviceName, now: now, going: going) else { return }
        let file = SyncTabs.file(device: device, name: MacSync.deviceName, phone: true, scope: scope, tabs: mine, spaces: [], now: now)
        do {
            try await backend.save(file, as: name)
            files[name] = file
            keepFetched()
        } catch {
            problem = MacSync.describe(error)
        }
    }

    /// The regular tabs, never an incognito one.
    static func ownTabs() -> [SyncedTab] {
        Tabs.shared.regular.compactMap { tab in
            guard let url = tab.url, SyncTabs.handed(url.absoluteString) else { return nil }
            return SyncedTab(url: url.absoluteString, title: tab.shownTitle, space: nil, active: tab.lastActive.timeIntervalSince1970)
        }
    }

    /// The tabs changed here: a pass a little later, once for many changes.
    func tabsChanged() {
        guard on, available else { return }
        tabsSoon?.cancel()
        let work = DispatchWorkItem { MainActor.assumeIsolated { MacSync.shared.pass() } }
        tabsSoon = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    /// Put in the background: the tabs as they are, now, with the time iOS
    /// gives to finish.
    func handOff() {
        guard on, available else { return }
        going = true
        tabsSoon?.cancel()
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Quo tabs") {
            UIApplication.shared.endBackgroundTask(task)
        }
        pass()
        Task { @MainActor in
            while running { try? await Task.sleep(for: .milliseconds(200)) }
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    /// Sync turned off: this iPhone's tabs leave iCloud, so a Mac doesn't
    /// go on showing them. Its pins stay, as they were given.
    private func withdrawTabs() {
        let name = SyncRecord.name(scope: MacSync.tabsScope, device: device)
        guard files[name] != nil, let backend = backend ?? makeBackend() else { backend = nil; return }
        files[name] = nil
        keepFetched()
        rebuild()
        Task { @MainActor in
            try? await backend.delete(name)
            self.backend = nil
        }
    }

    /// One scope merged: this iPhone's items (what it agreed last, with
    /// what changed here since) over the other devices' files.
    private func merge(scope: String, now: Double) -> [String: SyncEntry] {
        let stateName = "sync-\(scope).json"
        let state = Store.read([String: SyncEntry].self, stateName)
        var current = SyncMerge.live(state ?? [:])
        for (key, value) in edits[scope] ?? [:] { current[key] = value }
        let theirs = files.values.filter { $0.scope == scope && $0.device != device }.map(\.items)
        let merged = SyncMerge.pass(current: current, base: state, theirs: theirs, device: device, now: now,
                                    understood: SyncItems.understood)
        Store.write(merged, stateName)
        edits[scope] = nil
        Store.write(edits, "sync-edits.json")
        return merged
    }

    /// Sync off or unavailable: the iPhone's own changes still land.
    private func settleLocally() {
        guard !edits.isEmpty else { return rebuild() }
        let now = Date().timeIntervalSince1970
        for scope in edits.keys { _ = merge(scope: scope, now: now) }
        rebuild()
    }

    // MARK: - what it says

    private var personalLive: [String: String] {
        var live = SyncMerge.live(Store.read([String: SyncEntry].self, "sync-\(MacSync.personal).json") ?? [:])
        for (key, value) in edits[MacSync.personal] ?? [:] { live[key] = value }
        return live
    }

    /// The model rebuilt from the merged items, by the Mac's own rules.
    private func rebuild() {
        let live = personalLive
        let local = [Space(id: Space.firstID, name: "Personal", colour: 0)]
        let made = SyncItems.applySpaces(live, to: local, profile: Profile.personalID, home: Space.firstID)
        spaces = made
        let pins = SyncItems.applyPins(live, spaces: made.map(\.id), local: [:], localShared: [])
        pinsBySpace = pins.bySpace
        sharedPins = pins.shared
        bookmarks = SyncItems.applyBookmarks(live)
        let devices = SyncTabs.others(Array(files.values), scope: MacSync.tabsScope, device: device, now: Date().timeIntervalSince1970)
        if elsewhere != devices { elsewhere = devices }
        if !made.contains(where: { $0.id == currentSpaceID }) { currentSpaceID = made.first?.id ?? Space.firstID }
    }

    /// The Mac's search engine, from its settings' records.
    private func readSettings() {
        let app = SyncMerge.live(SyncMerge.merge(files.values.filter { $0.scope == "app" }.map(\.items)))
        let settings = AppSettings.shared
        settings.macEngine = app["set:search.engine"].flatMap { SyncMerge.value(String.self, $0) }.flatMap(Engine.init(rawValue:))
        if let custom = app["set:search.custom"].flatMap({ SyncMerge.value(String.self, $0) }), !custom.isEmpty {
            settings.customTemplate = custom
            UserDefaults.standard.set(custom, forKey: "search.custom")
        }
    }

    var currentSpace: Space? { spaces.first { $0.id == currentSpaceID } }

    /// The pins shown in a space: its own, then those every space shows.
    func pins(in space: UUID) -> [PinDef] { (pinsBySpace[space] ?? []) + sharedPins }

    func pin(for url: URL) -> PinDef? {
        let wanted = MacSync.bare(url.absoluteString)
        return pins(in: currentSpaceID).first { MacSync.bare($0.home) == wanted }
    }

    static func bare(_ text: String) -> String {
        var text = text.lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    // MARK: - made here

    /// The page pinned in the space shown, at the end of its pins.
    func pin(_ url: URL, title: String) {
        let space = currentSpaceID.uuidString
        let id = UUID()
        let host = Address.shown(url)
        let pin = SyncedPin(letter: host.first.map { String($0).uppercased() } ?? "\u{2022}", home: url.absoluteString, name: nil, listed: nil)
        var change: [String: String?] = [:]
        change[SyncItems.pinKey(space, id)] = SyncMerge.text(pin)
        change[SyncItems.pinTitle(id)] = SyncMerge.text(title.isEmpty ? host : title)
        let order = (pinsBySpace[currentSpaceID] ?? []).map(\.id.uuidString) + [id.uuidString]
        change[SyncItems.pinOrder(space)] = SyncMerge.text(order)
        edit(change)
    }

    func unpin(_ pin: PinDef) {
        let shared = sharedPins.contains { $0.id == pin.id }
        let space = shared ? SyncItems.sharedSpace : (pinsBySpace.first { $0.value.contains { $0.id == pin.id } }?.key.uuidString ?? currentSpaceID.uuidString)
        let list = shared ? sharedPins : (UUID(uuidString: space).flatMap { pinsBySpace[$0] } ?? [])
        var change: [String: String?] = [:]
        change[SyncItems.pinKey(space, pin.id)] = .some(nil)
        change[SyncItems.pinTitle(pin.id)] = .some(nil)
        let order = list.map(\.id.uuidString).filter { $0 != pin.id.uuidString }
        change[SyncItems.pinOrder(space)] = order.isEmpty ? .some(nil) : SyncMerge.text(order)
        edit(change)
    }

    private func edit(_ change: [String: String?]) {
        var scope = edits[MacSync.personal] ?? [:]
        for (key, value) in change { scope[key] = value }
        edits[MacSync.personal] = scope
        Store.write(edits, "sync-edits.json")
        rebuild()
        pass()
    }

    // MARK: - keeping

    private func keepFetched() {
        Store.write(files, "sync-cloud.json")
        if let token { try? token.write(to: Store.file("sync-cloud-token"), options: .atomic) } else { Store.remove("sync-cloud-token") }
    }

    private func forgetFetched() {
        files = [:]
        token = nil
        Store.remove("sync-cloud.json")
        Store.remove("sync-cloud-token")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: Store.folder.path)) ?? []
        where name.hasPrefix("sync-profile-") || name == "sync-app.json" {
            Store.remove(name)
        }
    }

    static var deviceName: String {
        let name = UIDevice.current.name
        return name.isEmpty ? "iPhone" : name
    }

    static func describe(_ error: Error) -> String {
        if let problem = error as? SyncProblem { return problem.text }
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in Settings"
        case .networkUnavailable, .networkFailure: return "Offline, trying again soon"
        case .quotaExceeded: return "iCloud is full"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy, trying again soon"
        case .permissionFailure, .badContainer, .missingEntitlement: return "This build can\u{2019}t reach Quo\u{2019}s iCloud"
        case .zoneNotFound, .userDeletedZone: return "Nothing from your Mac yet"
        default: return error.localizedDescription
        }
    }
}

enum SyncProblem: Error {
    case signedOut
    var text: String { "Sign in to iCloud in Settings" }
}

// MARK: - CloudKit

@MainActor
final class CloudBackend: SyncBackend {
    static let container = "iCloud.com.edinabazi.quo"
    private let container = CKContainer(identifier: CloudBackend.container)
    private var database: CKDatabase { container.privateCloudDatabase }
    private let zone = CKRecordZone.ID(zoneName: SyncRecord.zone, ownerName: CKCurrentUserDefaultName)
    private var ready: String?
    let label = "iCloud"

    func prepare() async throws -> String {
        guard try await container.accountStatus() == .available else { throw SyncProblem.signedOut }
        let account = try await container.userRecordID().recordName
        if ready == account { return account }
        let defaults = UserDefaults.standard
        let zoneKey = "sync.zone." + account, subscriptionKey = "sync.subscription." + account
        if !defaults.bool(forKey: zoneKey) {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
            defaults.set(true, forKey: zoneKey)
        }
        if !defaults.bool(forKey: subscriptionKey) {
            let subscription = CKRecordZoneSubscription(zoneID: zone, subscriptionID: "sync-zone")
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            if (try? await database.modifySubscriptions(saving: [subscription], deleting: [])) != nil {
                defaults.set(true, forKey: subscriptionKey)
            }
        }
        UIApplication.shared.registerForRemoteNotifications()
        ready = account
        return account
    }

    func fetch(since token: Data?) async throws -> (changed: [String: SyncFile], deleted: [String], token: Data?, more: Bool, complete: Bool) {
        let since = token.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        let changes = try await database.recordZoneChanges(inZoneWith: zone, since: since)
        var changed: [String: SyncFile] = [:]
        for (id, result) in changes.modificationResultsByID {
            guard case .success(let modification) = result, let file = SyncRecord.file(from: modification.record) else { continue }
            changed[id.recordName] = file
        }
        let next = try? NSKeyedArchiver.archivedData(withRootObject: changes.changeToken, requiringSecureCoding: true)
        return (changed, changes.deletions.map(\.recordID.recordName), next, changes.moreComing, since == nil)
    }

    func save(_ file: SyncFile, as name: String) async throws {
        var spare: URL?
        defer { if let spare { try? FileManager.default.removeItem(at: spare) } }
        let record = try SyncRecord.record(for: file, name: name, zone: zone, tag: "quo-ios", spare: &spare)
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if case .failure(let error)? = saved[record.recordID] { throw error }
    }

    func delete(_ name: String) async throws {
        let id = CKRecord.ID(recordName: name, zoneID: zone)
        let (_, deleted) = try await database.modifyRecords(saving: [], deleting: [id])
        if case .failure(let error)? = deleted[id], (error as? CKError)?.code != .unknownItem { throw error }
    }
}

// MARK: - a folder standing in

/// Records as the Mac's test folder keeps them ("<name>.record", each
/// {scope, data}), or the Mac's own sync-cloud.json copied in. The
/// iPhone's own are written beside them as records.
@MainActor
final class FolderBackend: SyncBackend {
    let folder: URL
    let label = "Stand-in folder"
    init(folder: URL) { self.folder = folder }

    private struct Record: Codable { let scope: String; let data: Data }

    func prepare() async throws -> String {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return "stand-in"
    }

    func fetch(since token: Data?) async throws -> (changed: [String: SyncFile], deleted: [String], token: Data?, more: Bool, complete: Bool) {
        var changed: [String: SyncFile] = [:]
        let cache = folder.appendingPathComponent("sync-cloud.json")
        if let data = try? Data(contentsOf: cache), let kept = try? JSONDecoder().decode([String: SyncFile].self, from: data) {
            for (name, file) in kept {
                guard let encoded = SyncMerge.encode(file), let checked = SyncMerge.decode(encoded, scope: file.scope) else { continue }
                changed[name] = checked
            }
        }
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "record" {
            guard let data = try? Data(contentsOf: url), let record = try? JSONDecoder().decode(Record.self, from: data),
                  let file = SyncMerge.decode(record.data, scope: record.scope) else { continue }
            changed[url.deletingPathExtension().lastPathComponent] = file
        }
        return (changed, [], nil, false, true)
    }

    func save(_ file: SyncFile, as name: String) async throws {
        guard let data = SyncMerge.encode(file) else { return }
        let record = try JSONEncoder().encode(Record(scope: file.scope, data: data))
        try record.write(to: folder.appendingPathComponent(name + ".record"), options: .atomic)
    }

    func delete(_ name: String) async throws {
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name + ".record"))
    }
}
