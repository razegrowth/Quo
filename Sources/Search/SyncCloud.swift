import AppKit
import CloudKit
import Security

// Sync through iCloud, with CloudKit: the same files the folder sync writes
// (SyncFile, one per Mac per scope, merged by SyncMerge), each kept as one
// record in a zone of the person's own private iCloud database. No account
// of ours and no server: the Apple ID the Mac is signed in with is the
// account. What a record says is in CloudKit's encrypted fields, sealed with
// a key kept in the person's iCloud Keychain: end to end encrypted whether
// or not Advanced Data Protection is on, unreadable to Apple and to us.
//
// Only in a build that carries the iCloud entitlement, which needs a
// container made for the app and a Developer ID provisioning profile that
// lists it (see Quo.entitlements and quo.sh). Without it the choice isn't
// offered and nothing here runs. A test run can stand in a folder for
// iCloud (SEARCH_FAKE_CLOUD), records and all, so two Macs can be tried
// against each other without an Apple ID (Tests/sync_icloud.py).
//
// Another Mac's change arrives as a silent push to this zone's
// subscription, and a pass follows; a pass every half minute stays as the
// fallback. What was fetched is kept, with the zone's change token, so each
// pass asks only for what changed since the last.

/// Where the records are kept: CloudKit, or in a test run a folder standing
/// in for it.
@MainActor
protocol SyncCloudBackend: AnyObject {
    /// Signed in and set up. Says which account, so a different Apple ID
    /// on the same Mac is never merged with the last one's records.
    func prepare() async throws -> String
    /// What changed since `token`. `complete`: `changed` is every record
    /// there is, not only the changed ones.
    func fetch(since token: Data?) async throws -> SyncCloudChanges
    func save(_ file: SyncFile, as name: String) async throws
    func delete(_ names: [String]) async throws
}

struct SyncCloudChanges {
    var changed: [String: SyncFile]
    var deleted: [String]
    var token: Data?
    var more: Bool
    var complete: Bool
}

@MainActor
final class SyncCloud {
    /// The container the build was signed for, or nil when it carries no
    /// iCloud entitlement.
    nonisolated static let containerID: String? = {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil)
        else { return nil }
        return (value as? [String])?.first
    }()

    /// A test run's stand-in for iCloud: a folder two probes share.
    nonisolated static let fakeFolder: URL? = {
        guard Store.testing, let path = ProcessInfo.processInfo.environment["SEARCH_FAKE_CLOUD"], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }()

    /// A test run reaches the real iCloud only when asked to
    /// (SEARCH_REAL_CLOUD=1, with a build signed for the container): a
    /// probe never writes into somebody's iCloud by accident.
    nonisolated static var realInTests: Bool { ProcessInfo.processInfo.environment["SEARCH_REAL_CLOUD"] == "1" }

    nonisolated static var available: Bool { fakeFolder != nil || (containerID != nil && (!Store.testing || realInTests)) }

    nonisolated static let zoneName = SyncRecord.zone
    nonisolated static let recordType = SyncRecord.type

    private let backend: SyncCloudBackend
    /// Every Mac's file, as last fetched, by record name.
    private var files: [String: SyncFile] = [:]
    private var token: Data?

    private static var cacheURL: URL { Store.file("sync-cloud.json") }
    private static var tokenURL: URL { Store.file("sync-cloud-token") }
    nonisolated static let accountKey = "sync.cloud.account"

    init() {
        if let fake = SyncCloud.fakeFolder {
            backend = SyncCloudFolder(folder: fake)
        } else {
            backend = SyncCloudKit(container: SyncCloud.containerID ?? "")
        }
        if let data = try? Data(contentsOf: SyncCloud.cacheURL),
           let kept = try? JSONDecoder().decode([String: SyncFile].self, from: data) { files = kept }
        token = try? Data(contentsOf: SyncCloud.tokenURL)
    }

    static func recordName(scope: String, device: String) -> String { SyncRecord.name(scope: scope, device: device) }

    /// The files of one scope, every Mac's.
    func files(in scope: String) -> [SyncFile] { files.values.filter { $0.scope == scope } }
    func file(scope: String, device: String) -> SyncFile? { files[SyncCloud.recordName(scope: scope, device: device)] }

    // MARK: - a pass's two halves

    /// Signed in and set up. True when the Apple ID isn't the one this Mac
    /// synced with before: everything known of the old one is forgotten,
    /// and this Mac joins the new one's as a Mac joining.
    func prepare() async throws -> Bool {
        let account = try await backend.prepare()
        let before = Store.settings.string(forKey: SyncCloud.accountKey)
        Store.settings.set(account, forKey: SyncCloud.accountKey)
        guard let before, before != account else { return false }
        forget()
        return true
    }

    /// What changed in iCloud since the last fetch.
    func fetchChanges() async throws {
        var more = true
        while more {
            let changes: SyncCloudChanges
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
        keep()
    }

    /// This Mac's file for a scope, in place of the one before.
    func save(_ file: SyncFile) async throws {
        let name = SyncCloud.recordName(scope: file.scope, device: file.device)
        try await backend.save(file, as: name)
        files[name] = file
        keep()
    }

    /// Sync turned off: this Mac's records leave iCloud, and what was
    /// fetched is forgotten.
    func removeOwn(device: String) async {
        let own = files.filter { $0.value.device == device }.map(\.key)
        if !own.isEmpty { try? await backend.delete(own) }
        forget()
    }

    func forget() {
        files = [:]
        token = nil
        try? FileManager.default.removeItem(at: SyncCloud.cacheURL)
        try? FileManager.default.removeItem(at: SyncCloud.tokenURL)
    }

    private func keep() {
        if let data = try? JSONEncoder().encode(files) { try? data.write(to: SyncCloud.cacheURL, options: .atomic) }
        if let token { try? token.write(to: SyncCloud.tokenURL, options: .atomic) } else {
            try? FileManager.default.removeItem(at: SyncCloud.tokenURL)
        }
    }

    // MARK: - in words

    enum Problem: Error { case signedOut, notSetUp }

    /// For Settings.
    static func describe(_ error: Error) -> String {
        switch error {
        case Problem.signedOut: return "Sign in to iCloud in System Settings"
        case Problem.notSetUp: return "iCloud isn\u{2019}t set up for \(Store.name) yet"
        default: break
        }
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in System Settings"
        case .networkUnavailable, .networkFailure: return "Offline, trying again soon"
        case .quotaExceeded: return "iCloud is full"
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: return "iCloud is busy, trying again soon"
        case .permissionFailure, .badContainer, .missingEntitlement: return "This build can\u{2019}t reach its iCloud container"
        case .serverRejectedRequest, .invalidArguments, .unknownItem: return "iCloud isn\u{2019}t set up for \(Store.name) yet"
        case .partialFailure:
            if let first = error.partialErrorsByItemID?.values.first { return describe(first) }
            return error.localizedDescription
        default: return error.localizedDescription
        }
    }

    /// How long iCloud asked to be left alone, if it did.
    static func retryAfter(_ error: Error) -> TimeInterval? {
        (error as? CKError)?.retryAfterSeconds
    }
}

// MARK: - CloudKit

@MainActor
final class SyncCloudKit: SyncCloudBackend {
    private let container: CKContainer
    private var database: CKDatabase { container.privateCloudDatabase }
    private let zone = CKRecordZone.ID(zoneName: SyncCloud.zoneName, ownerName: CKCurrentUserDefaultName)
    private static let subscriptionID = "sync-zone"
    private var ready: String?

    init(container identifier: String) {
        container = CKContainer(identifier: identifier)
    }

    func prepare() async throws -> String {
        let status = try await container.accountStatus()
        guard status == .available else { throw SyncCloud.Problem.signedOut }
        let account = try await container.userRecordID().recordName
        if ready == account { return account }
        // Made once per account: a flag per account, so another Apple ID on
        // this Mac gets its own zone and subscription.
        let settings = Store.settings
        let zoneKey = "sync.cloud.zone." + account, subscriptionKey = "sync.cloud.subscription." + account
        if !settings.bool(forKey: zoneKey) {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zone)], deleting: [])
            settings.set(true, forKey: zoneKey)
        }
        if !settings.bool(forKey: subscriptionKey) {
            let subscription = CKRecordZoneSubscription(zoneID: zone, subscriptionID: SyncCloudKit.subscriptionID)
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info
            // Without push (no aps-environment) the half-minute pass still
            // runs: a subscription that can't be made is no reason to stop.
            if (try? await database.modifySubscriptions(saving: [subscription], deleting: [])) != nil {
                settings.set(true, forKey: subscriptionKey)
            }
        }
        NSApp.registerForRemoteNotifications()
        ready = account
        return account
    }

    func fetch(since token: Data?) async throws -> SyncCloudChanges {
        let since = token.flatMap { try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: $0) }
        let changes: (modificationResultsByID: [CKRecord.ID: Result<CKDatabase.RecordZoneChange.Modification, Error>],
                      deletions: [CKDatabase.RecordZoneChange.Deletion], changeToken: CKServerChangeToken, moreComing: Bool)
        do {
            changes = try await database.recordZoneChanges(inZoneWith: zone, since: since)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .userDeletedZone {
            // Deleted from another Mac or in System Settings › iCloud: made
            // again on the next pass, and everything written afresh.
            if let account = ready {
                Store.settings.removeObject(forKey: "sync.cloud.zone." + account)
                Store.settings.removeObject(forKey: "sync.cloud.subscription." + account)
            }
            ready = nil
            throw error
        }
        var changed: [String: SyncFile] = [:]
        for (id, result) in changes.modificationResultsByID {
            guard case .success(let modification) = result, let file = SyncCloudKit.file(from: modification.record) else { continue }
            changed[id.recordName] = file
        }
        let token = try? NSKeyedArchiver.archivedData(withRootObject: changes.changeToken, requiringSecureCoding: true)
        return SyncCloudChanges(changed: changed, deleted: changes.deletions.map(\.recordID.recordName),
                                token: token, more: changes.moreComing, complete: since == nil)
    }

    /// What a record holds, and the record for a file: the same on the
    /// iPhone (SyncRecord.swift).
    static func file(from record: CKRecord) -> SyncFile? { SyncRecord.file(from: record) }

    static func record(for file: SyncFile, name: String, zone: CKRecordZone.ID, spare: inout URL?) throws -> CKRecord {
        try SyncRecord.record(for: file, name: name, zone: zone, tag: Store.name.lowercased(), spare: &spare)
    }

    func save(_ file: SyncFile, as name: String) async throws {
        var spare: URL?
        defer { if let spare { try? FileManager.default.removeItem(at: spare) } }
        let record = try SyncCloudKit.record(for: file, name: name, zone: zone, spare: &spare)
        // Only this Mac writes this record, so whatever is there is its own
        // last word: saved over, whatever its tag.
        let (saved, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        if case .failure(let error)? = saved[record.recordID] { throw error }
    }

    func delete(_ names: [String]) async throws {
        let ids = names.map { CKRecord.ID(recordName: $0, zoneID: zone) }
        let (_, deleted) = try await database.modifyRecords(saving: [], deleting: ids)
        for case .failure(let error) in deleted.values {
            if (error as? CKError)?.code != .unknownItem { throw error }
        }
    }
}

// MARK: - a folder standing in, for tests

/// A test run's iCloud: each record a file in a shared folder, and the
/// account a name the test gives (SEARCH_FAKE_CLOUD_ACCOUNT). A fetch reads
/// every record, so it says it is complete.
@MainActor
final class SyncCloudFolder: SyncCloudBackend {
    private let folder: URL
    init(folder: URL) { self.folder = folder }

    func prepare() async throws -> String {
        let account = ProcessInfo.processInfo.environment["SEARCH_FAKE_CLOUD_ACCOUNT"] ?? "test-account"
        if account == "signed-out" { throw SyncCloud.Problem.signedOut }
        try FileManager.default.createDirectory(at: zoneFolder(account), withIntermediateDirectories: true)
        if self.account != account || watcher == nil { watch(zoneFolder(account)) }
        self.account = account
        return account
    }

    private var account = "test-account"
    private var watcher: DispatchSourceFileSystemObject?

    /// Another Mac writing, as iCloud's silent push says so.
    private func watch(_ folder: URL) {
        watcher?.cancel()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { Sync.shared.heard() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }
    private func zoneFolder(_ account: String) -> URL { folder.appendingPathComponent(account, isDirectory: true) }

    func fetch(since token: Data?) async throws -> SyncCloudChanges {
        var changed: [String: SyncFile] = [:]
        for url in (try? FileManager.default.contentsOfDirectory(at: zoneFolder(account), includingPropertiesForKeys: nil)) ?? []
        where url.pathExtension == "record" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  let file = SyncMerge.decode(record.data, scope: record.scope) else { continue }
            changed[url.deletingPathExtension().lastPathComponent] = file
        }
        return SyncCloudChanges(changed: changed, deleted: [], token: nil, more: false, complete: true)
    }

    private struct Record: Codable { let scope: String; let data: Data }

    func save(_ file: SyncFile, as name: String) async throws {
        guard let data = SyncMerge.encode(file) else { return }
        let record = try JSONEncoder().encode(Record(scope: file.scope, data: data))
        try record.write(to: zoneFolder(account).appendingPathComponent(name + ".record"), options: .atomic)
    }

    func delete(_ names: [String]) async throws {
        for name in names { try? FileManager.default.removeItem(at: zoneFolder(account).appendingPathComponent(name + ".record")) }
    }
}
