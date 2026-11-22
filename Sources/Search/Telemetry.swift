import AppKit
import CryptoKit
import Foundation

/// How many people use a fork, counted by TelemetryDeck: only in a build
/// handed an app id (build.sh's SEARCH_TELEMETRY_APP, which quo.sh sets).
/// Search itself has none, and sends nothing.
///
/// What goes, and nothing else: once a day "App.opened", and once per
/// install TelemetryDeck's new-install event, each with the app's version
/// and build, and the Mac's model, chip and macOS version. Never a page, an
/// address, a search or a tab. The user is a random UUID made here the first
/// time, hashed before it leaves; TelemetryDeck hashes it again and never
/// looks at the IP for these. Off in Settings › Privacy, and the UUID goes
/// with it. A test run (Store.testing) sends nothing; a build that isn't a
/// release (SEARCH_TELEMETRY_TEST) marks what it sends as a test, which
/// TelemetryDeck keeps out of the real numbers.
enum Telemetry {
    nonisolated static let appID = Bundle.main.object(forInfoDictionaryKey: "SearchTelemetryApp") as? String ?? ""
    nonisolated static let namespace = Bundle.main.object(forInfoDictionaryKey: "SearchTelemetryNamespace") as? String ?? ""
    nonisolated static let test = (Bundle.main.object(forInfoDictionaryKey: "SearchTelemetryTest") as? String) == "1"

    /// Whether this build counts at all, so Settings has a row for it.
    nonisolated static var configured: Bool { !appID.isEmpty }

    static let key = "privacy.telemetry"
    private static let userKey = "telemetry.user"
    private static let dayKey = "telemetry.day"
    private static let installKey = "telemetry.installed"

    @MainActor private static var timer: Timer?
    @MainActor private static var sending = false
    private static let session = UUID().uuidString

    /// On or off, from Preferences: on checks now and then hourly (a Mac
    /// stays open for days, and a day is counted only once); off forgets
    /// the UUID, so turning it back on is a stranger.
    @MainActor static func set(on: Bool) {
        timer?.invalidate()
        timer = nil
        guard configured, !Store.testing else { return }
        guard on else {
            Store.settings.removeObject(forKey: userKey)
            return
        }
        check()
        let every = Timer(timeInterval: 3600, repeats: true) { _ in MainActor.assumeIsolated { check() } }
        RunLoop.main.add(every, forMode: .common)
        timer = every
    }

    /// The signals due: the install, once, and today's.
    @MainActor static func check() {
        guard !sending else { return }
        let store = Store.settings
        let today = day(Date())
        var due: [String] = []
        if store.string(forKey: installKey) == "due" {
            due.append("TelemetryDeck.Acquisition.newInstallDetected")
        }
        if store.string(forKey: dayKey) != today { due.append("App.opened") }
        guard !due.isEmpty else { return }
        let body = signals(due, user: user())
        sending = true
        send(body) { ok in
            MainActor.assumeIsolated {
                sending = false
                guard ok else { return }
                store.set(today, forKey: dayKey)
                store.set("counted", forKey: installKey)
            }
        }
    }

    /// Whether this is a new install, settled once, from Preferences' init
    /// before it writes its first line: an install from before this build
    /// has the lines every earlier launch left (Preferences.settleLittleLinks),
    /// and isn't new. "due" until TelemetryDeck has it, then "counted".
    nonisolated static func settleInstall(in store: UserDefaults) {
        guard store.object(forKey: installKey) == nil else { return }
        let before = ["welcomed", "glyph", "passkeys.for", "passkeys.entitled"].contains { store.object(forKey: $0) != nil }
        store.set(before ? "counted" : "due", forKey: installKey)
    }

    /// The random UUID that stands for this Mac, made the first time.
    @MainActor private static func user() -> String {
        if let had = Store.settings.string(forKey: userKey) { return had }
        let made = UUID().uuidString
        Store.settings.set(made, forKey: userKey)
        return made
    }

    nonisolated static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The UUID as it leaves: SHA-256 with a salt, never the UUID itself.
    nonisolated static func hashed(_ user: String) -> String {
        SHA256.hash(data: Data((user + "search.telemetry").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The body TelemetryDeck's ingest API takes: an array of signals.
    nonisolated static func signals(_ types: [String], user: String) -> [[String: Any]] {
        types.map { type in
            ["appID": appID, "clientUser": hashed(user), "sessionID": session,
             "type": type, "isTestMode": test, "payload": payload()]
        }
    }

    /// The version, and the Mac it runs on, in TelemetryDeck's own names so
    /// its dashboards fill in.
    nonisolated static func payload() -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return [
            "TelemetryDeck.AppInfo.version": version,
            "TelemetryDeck.AppInfo.buildNumber": build,
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "\(version) \(build)",
            "TelemetryDeck.Device.platform": "macOS",
            "TelemetryDeck.Device.operatingSystem": "macOS",
            "TelemetryDeck.Device.systemVersion": "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "TelemetryDeck.Device.systemMajorVersion": "macOS \(os.majorVersion)",
            "TelemetryDeck.Device.systemMajorMinorVersion": "macOS \(os.majorVersion).\(os.minorVersion)",
            "TelemetryDeck.Device.architecture": architecture,
            "TelemetryDeck.Device.modelName": model(),
        ]
    }

    /// The kind of Mac, "Mac15,3": the same for every one of its kind.
    nonisolated private static func model() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        return String(cString: bytes)
    }

    nonisolated static var endpoint: URL {
        namespace.isEmpty
            ? URL(string: "https://nom.telemetrydeck.com/v2/")!
            : URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(namespace)/")!
    }

    /// No cookies, no cache, nothing kept: a session of its own.
    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    nonisolated private static func send(_ body: [[String: Any]], done: @escaping @Sendable (Bool) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return done(false) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        urlSession.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }
}
