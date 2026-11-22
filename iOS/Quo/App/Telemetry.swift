import CryptoKit
import Foundation
import UIKit

/// How many people use Quo for iPhone, counted by TelemetryDeck, as Quo on
/// the Mac does (Sources/Search/Telemetry.swift).
///
/// What goes, and nothing else: once a day "App.opened", and once per
/// install TelemetryDeck's new-install event, each with the app's version
/// and build, and the iPhone's model and iOS version. Never a page, an
/// address, a search or a tab. The user is a random UUID made here the first
/// time, hashed before it leaves; TelemetryDeck hashes it again and never
/// looks at the IP for these. Off in Settings, and the UUID goes with it. A
/// debug build marks what it sends as a test, kept out of the real numbers.
enum Telemetry {
    static let appID = "AA491615-7111-480E-8F62-9CF27ED5EB91"
    static let namespace = "com.razegrowth"
    #if DEBUG
    static let test = true
    #else
    static let test = false
    #endif

    static let key = "privacy.telemetry"
    private static let userKey = "telemetry.user"
    private static let dayKey = "telemetry.day"
    private static let installKey = "telemetry.installed"
    private static let session = UUID().uuidString
    private static var defaults: UserDefaults { .standard }

    @MainActor private static var watching: NSObjectProtocol?
    @MainActor private static var sending = false

    /// From AppSettings, at launch: settles whether this is a new install,
    /// then checks each time Quo comes to the front, since a day is counted
    /// once and an iPhone app sleeps in between.
    @MainActor static func start(on: Bool) {
        settleInstall()
        set(on: on)
    }

    @MainActor static func set(on: Bool) {
        if let watching { NotificationCenter.default.removeObserver(watching) }
        watching = nil
        guard on else {
            defaults.removeObject(forKey: userKey)
            return
        }
        watching = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { check() }
        }
        // Once launch has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { check() }
    }

    /// New only with nothing from an earlier launch here: an install from
    /// before this build has been through the onboarding.
    @MainActor private static func settleInstall() {
        guard defaults.object(forKey: installKey) == nil else { return }
        defaults.set(defaults.object(forKey: "onboarded") != nil ? "counted" : "due", forKey: installKey)
    }

    @MainActor static func check() {
        guard watching != nil, !sending else { return }
        let today = day(Date())
        var due: [String] = []
        if defaults.string(forKey: installKey) == "due" { due.append("TelemetryDeck.Acquisition.newInstallDetected") }
        if defaults.string(forKey: dayKey) != today { due.append("App.opened") }
        guard !due.isEmpty else { return }
        let body = signals(due, user: user())
        sending = true
        send(body) { ok in
            MainActor.assumeIsolated {
                sending = false
                guard ok else { return }
                defaults.set(today, forKey: dayKey)
                defaults.set("counted", forKey: installKey)
            }
        }
    }

    @MainActor private static func user() -> String {
        if let had = defaults.string(forKey: userKey) { return had }
        let made = UUID().uuidString
        defaults.set(made, forKey: userKey)
        return made
    }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The UUID as it leaves: SHA-256 with a salt, never the UUID itself.
    static func hashed(_ user: String) -> String {
        SHA256.hash(data: Data((user + "search.telemetry").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func signals(_ types: [String], user: String) -> [[String: Any]] {
        types.map { type in
            ["appID": appID, "clientUser": hashed(user), "sessionID": session,
             "type": type, "isTestMode": test, "payload": payload()]
        }
    }

    /// The version, and the iPhone it runs on, in TelemetryDeck's own names
    /// so its dashboards fill in.
    static func payload() -> [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? ""
        let build = info["CFBundleVersion"] as? String ?? ""
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "TelemetryDeck.AppInfo.version": version,
            "TelemetryDeck.AppInfo.buildNumber": build,
            "TelemetryDeck.AppInfo.versionAndBuildNumber": "\(version) \(build)",
            "TelemetryDeck.Device.platform": "iOS",
            "TelemetryDeck.Device.operatingSystem": "iOS",
            "TelemetryDeck.Device.systemVersion": "iOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "TelemetryDeck.Device.systemMajorVersion": "iOS \(os.majorVersion)",
            "TelemetryDeck.Device.systemMajorMinorVersion": "iOS \(os.majorVersion).\(os.minorVersion)",
            "TelemetryDeck.Device.architecture": "arm64",
            "TelemetryDeck.Device.modelName": model(),
        ]
    }

    /// The kind of iPhone, "iPhone17,1": the same for every one of its kind.
    private static func model() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    private static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static func send(_ body: [[String: Any]], done: @escaping @Sendable (Bool) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: "https://nom.telemetrydeck.com/v2/namespace/\(namespace)/") else { return done(false) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        urlSession.dataTask(with: request) { _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }
}
