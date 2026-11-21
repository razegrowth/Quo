import Foundation
import SwiftUI

/// Where Quo keeps its things on the iPhone: Application Support/Quo.
enum Store {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Quo", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func file(_ name: String) -> URL { folder.appendingPathComponent(name) }

    static func read<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: file(name)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func write<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(name), options: .atomic)
    }

    static func remove(_ name: String) { try? FileManager.default.removeItem(at: file(name)) }

    static let version: String = {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }()
}

/// How long a tab may go unvisited before it's archived.
enum ArchiveAfter: String, CaseIterable, Identifiable, Codable {
    case day, week, month, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "After 1 day"
        case .week: return "After 7 days"
        case .month: return "After 30 days"
        case .never: return "Never"
        }
    }
    var seconds: TimeInterval? {
        switch self {
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .never: return nil
        }
    }
}

enum AppLinks: String, CaseIterable, Identifiable {
    case app, quo
    var id: String { rawValue }
    var title: String { self == .app ? "Native App" : "Quo" }
}

enum SwipeNav: String, CaseIterable, Identifiable, Codable {
    case edges, off
    var id: String { rawValue }
    var title: String { self == .edges ? "From Screen Edges" : "Off" }
}

/// The app's settings, kept in UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    @Published var autoKeyboard: Bool { didSet { defaults.set(autoKeyboard, forKey: "keyboard.auto") } }
    @Published var archiveAfter: ArchiveAfter { didSet { defaults.set(archiveAfter.rawValue, forKey: "tabs.archive") } }
    @Published var appLinks: AppLinks { didSet { defaults.set(appLinks.rawValue, forKey: "links.app") } }
    /// The engine chosen here; nil follows the Mac's, when synced.
    @Published var engineChoice: Engine? { didSet { defaults.set(engineChoice?.rawValue, forKey: "search.engine") } }
    @Published var engineSuggests: Bool { didSet { defaults.set(engineSuggests, forKey: "search.suggest") } }
    /// The language pages are translated into.
    @Published var translateTo: String { didSet { defaults.set(translateTo, forKey: "translate.to") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    /// The custom engine's template, as the Mac's, when one is synced.
    @Published var customTemplate: String = ""
    /// The engine the Mac uses, as synced.
    @Published var macEngine: Engine?

    var engine: Engine { engineChoice ?? macEngine ?? .standard }

    private init() {
        defaults.register(defaults: ["keyboard.auto": true, "search.suggest": true])
        autoKeyboard = defaults.bool(forKey: "keyboard.auto")
        archiveAfter = ArchiveAfter(rawValue: defaults.string(forKey: "tabs.archive") ?? "") ?? .week
        appLinks = AppLinks(rawValue: defaults.string(forKey: "links.app") ?? "") ?? .app
        engineChoice = defaults.string(forKey: "search.engine").flatMap(Engine.init(rawValue:))
        engineSuggests = defaults.bool(forKey: "search.suggest")
        translateTo = defaults.string(forKey: "translate.to") ?? (Locale.current.language.languageCode?.identifier ?? "en")
        onboarded = defaults.bool(forKey: "onboarded")
        customTemplate = defaults.string(forKey: "search.custom") ?? ""
    }

    /// The address for typed words: a URL as it is, else a search.
    func destination(for typed: String) -> URL? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = Address.url(text) { return url }
        return Engine.url(for: text, template: engine.template(custom: customTemplate))
    }
}

/// Per site, and the defaults every site starts from (Global Site Settings).
struct SiteSettings: Codable, Equatable {
    var blockAds = true
    var blockCookieBanners = true
    var blockTrackers = true
    var collapseBar = true
    var swipe: SwipeNav = .edges
}

@MainActor
final class Sites: ObservableObject {
    static let shared = Sites()

    @Published private(set) var global: SiteSettings
    @Published private(set) var bySite: [String: SiteSettings]

    private init() {
        global = Store.read(SiteSettings.self, "sites-global.json") ?? SiteSettings()
        bySite = Store.read([String: SiteSettings].self, "sites.json") ?? [:]
    }

    static func key(_ host: String?) -> String? {
        guard let host = host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func settings(for host: String?) -> SiteSettings {
        Sites.key(host).flatMap { bySite[$0] } ?? global
    }

    func set(_ settings: SiteSettings, for host: String?) {
        guard let key = Sites.key(host) else { return }
        bySite[key] = settings == global ? nil : settings
        Store.write(bySite, "sites.json")
    }

    func setGlobal(_ settings: SiteSettings) {
        global = settings
        Store.write(global, "sites-global.json")
    }

    func forgetAll() {
        bySite = [:]
        Store.remove("sites.json")
    }
}

/// What's typed, as an address when it is one.
enum Address {
    static func url(_ text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(" ") else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("about:") {
            return URL(string: text)
        }
        if lower.hasPrefix("localhost") || isIP(lower) {
            return URL(string: "http://" + text)
        }
        // Something.tld, with a tld of letters.
        let host = lower.split(separator: "/", maxSplits: 1).first.map(String.init) ?? lower
        let parts = host.split(separator: ".")
        guard parts.count >= 2, let tld = parts.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return URL(string: "https://" + text)
    }

    private static func isIP(_ text: String) -> Bool {
        let host = text.split(separator: "/").first.map { $0.split(separator: ":").first.map(String.init) ?? "" } ?? ""
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }

    /// A host without www., for showing.
    static func shown(_ url: URL?) -> String {
        guard let url else { return "" }
        guard let host = url.host() else { return url.absoluteString }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
