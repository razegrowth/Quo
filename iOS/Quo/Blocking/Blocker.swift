import CryptoKit
import Foundation
import WebKit

// Ads, trackers and cookie banners, blocked as the Mac's Shield blocks them:
// WebKit content rule lists, enforced inside WebKit's networking before a
// request is made, so they cost nothing while a page runs.
//
// Each kind has a short list of its own, ready the moment Quo opens (the
// Mac's domains and ad slots, and the consent boxes every big site uses),
// and a public filter list fetched in the background and turned into
// WebKit's rules by the Mac's own converter (FilterList.swift): EasyList,
// EasyPrivacy and Fanboy's Cookie Monster. A site's own settings say which
// kinds go on for it, decided before each page as the Mac decides it.

enum BlockKind: String, CaseIterable, Codable {
    case ads, trackers, cookies

    var listURL: URL? {
        switch self {
        case .ads: return URL(string: "https://easylist.to/easylist/easylist.txt")
        case .trackers: return URL(string: "https://easylist.to/easylist/easyprivacy.txt")
        case .cookies: return URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")
        }
    }

    var listName: String {
        switch self {
        case .ads: return "EasyList"
        case .trackers: return "EasyPrivacy"
        case .cookies: return "Fanboy\u{2019}s Cookie Monster"
        }
    }
}

@MainActor
final class Blocker: ObservableObject {
    static let shared = Blocker()

    private let store = WKContentRuleListStore.default()
    private var builtIn: [BlockKind: WKContentRuleList] = [:]
    private var fetched: [BlockKind: WKContentRuleList] = [:]
    @Published private(set) var listRules: [BlockKind: Int] = [:]
    @Published private(set) var trouble: String?

    /// Whether each page's controller has which lists, so a page heading to
    /// the next one with the same settings is left alone.
    private let holding = NSMapTable<WKUserContentController, NSString>.weakToStrongObjects()

    // MARK: - the built-in lists

    /// Third parties whose only job is to sell. From the Mac's Shield.
    static let adDomains = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "googletagservices.com",
        "adservice.google.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net",
        "taboola.com", "outbrain.com", "rubiconproject.com", "pubmatic.com", "openx.net", "casalemedia.com",
        "smartadserver.com", "sharethrough.com", "indexww.com", "bidswitch.net", "33across.com", "teads.tv",
        "moatads.com", "adroll.com",
    ]

    /// Third parties whose only job is to watch. From the Mac's Shield.
    static let trackerDomains = [
        "google-analytics.com", "googletagmanager.com", "scorecardresearch.com", "quantserve.com",
        "chartbeat.com", "hotjar.com", "mouseflow.com", "fullstory.com", "clarity.ms", "mixpanel.com",
        "amplitude.com", "segment.com", "segment.io", "branch.io", "appsflyer.com", "adjust.com",
        "analytics.tiktok.com", "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
    ]

    /// The slots that are reliably an advertisement. From the Mac's Shield.
    static let adSlots = [
        ".adsbygoogle", "ins.adsbygoogle", "[id^=\"google_ads_\"]", "[id^=\"div-gpt-ad\"]", "[id^=\"taboola-\"]",
        "#taboola-below-article", "iframe[src*=\"doubleclick.net\"]", "iframe[src*=\"googlesyndication\"]",
        "iframe[src*=\"amazon-adsystem\"]", ".ad-slot", ".ad-slot-container", ".top-banner-ad-container",
        ".ad-leaderboard", ".ad-billboard", ".ad-giga", ".ad-mpu", ".ad-mrec", ".ad-unit", ".adunit", ".adslot",
        ".dfp-ad", ".gpt-ad", ".w_ad",
    ]

    /// The consent boxes of the consent platforms most sites use.
    static let cookieBoxes = [
        "#onetrust-banner-sdk", "#onetrust-consent-sdk", "#CybotCookiebotDialog", "#CybotCookiebotDialogBodyUnderlay",
        ".qc-cmp2-container", "#qc-cmp2-container", "#didomi-host", ".fc-consent-root", "#usercentrics-root",
        "#truste-consent-track", "#truste-consent-content", ".truste_overlay", ".cc-window", ".cc-banner",
        "#cookie-notice", "#cookie-law-info-bar", ".cookie-notice-container", "#cmplz-cookiebanner-container",
        ".cmplz-cookiebanner", "#sp_message_container_", "[id^=\"sp_message_container_\"]", "#gdpr-cookie-message",
        ".osano-cm-window", "#iubenda-cs-banner", ".evidon-banner", "#consent_blackbar", ".cookiebanner",
        "#CookieBanner", "#cookieConsent", ".js-consent-banner",
    ]

    static func networkFilter(for domain: String) -> String {
        let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
        return "^https?://([^/]+\\.)?\(escaped)[:/]"
    }

    private static func rules(_ kind: BlockKind) -> [[String: Any]] {
        func block(_ domains: [String]) -> [[String: Any]] {
            domains.map { ["trigger": ["url-filter": networkFilter(for: $0), "load-type": ["third-party"]], "action": ["type": "block"]] }
        }
        func hide(_ selectors: [String]) -> [String: Any] {
            ["trigger": ["url-filter": ".*"], "action": ["type": "css-display-none", "selector": selectors.joined(separator: ", ")]]
        }
        switch kind {
        case .ads: return block(adDomains) + [hide(adSlots)]
        case .trackers: return block(trackerDomains)
        case .cookies: return [hide(cookieBoxes)]
        }
    }

    // MARK: - preparing

    func start() {
        for kind in BlockKind.allCases {
            let rules = Blocker.rules(kind)
            guard let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else { continue }
            let id = "quo-\(kind.rawValue)-" + Blocker.hash(data)
            compile(id, json: json) { [weak self] list in
                self?.builtIn[kind] = list
                self?.retune()
            }
            restoreFetched(kind)
        }
        // Out of the first page's way: its loads come first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            MainActor.assumeIsolated { self?.refreshLists() }
        }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Blocker.shared.refreshLists() }
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func compile(_ id: String, json: String, done: @escaping @MainActor (WKContentRuleList) -> Void) {
        guard let store else { return }
        store.lookUpContentRuleList(forIdentifier: id) { found, _ in
            MainActor.assumeIsolated {
                if let found { return done(found) }
                store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) { compiled, error in
                    MainActor.assumeIsolated {
                        if let compiled { done(compiled) } else {
                            self.trouble = error?.localizedDescription ?? "A block list didn\u{2019}t compile"
                        }
                    }
                }
            }
        }
    }

    private func listID(_ kind: BlockKind) -> String { "quo-list-\(kind.rawValue)" }
    private var fetchedKey: String { "blocker.fetched" }

    private func restoreFetched(_ kind: BlockKind) {
        store?.lookUpContentRuleList(forIdentifier: listID(kind)) { found, _ in
            MainActor.assumeIsolated {
                if let found {
                    self.fetched[kind] = found
                    self.retune()
                }
            }
        }
    }

    /// Each list fetched again once a day, converted off the main thread,
    /// compiled, and put on every open page.
    func refreshLists(force: Bool = false) {
        let when = UserDefaults.standard.dictionary(forKey: fetchedKey) as? [String: Double] ?? [:]
        let now = Date().timeIntervalSince1970
        for kind in BlockKind.allCases {
            guard force || now - (when[kind.rawValue] ?? 0) > 86_400, let url = kind.listURL else { continue }
            Task.detached(priority: .utility) {
                guard let (data, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let text = String(data: data, encoding: .utf8) else { return }
                let converted = FilterList.convert(text)
                guard converted.rules > 0, converted.rules <= FilterList.limit else { return }
                await MainActor.run {
                    let store = self.store
                    store?.compileContentRuleList(forIdentifier: self.listID(kind), encodedContentRuleList: converted.json) { list, _ in
                        MainActor.assumeIsolated {
                            guard let list else { return }
                            self.fetched[kind] = list
                            self.listRules[kind] = converted.rules
                            var stamps = UserDefaults.standard.dictionary(forKey: self.fetchedKey) as? [String: Double] ?? [:]
                            stamps[kind.rawValue] = Date().timeIntervalSince1970
                            UserDefaults.standard.set(stamps, forKey: self.fetchedKey)
                            self.retune()
                        }
                    }
                }
            }
        }
    }

    // MARK: - on a page

    /// Every page's controller, so a list that arrives late reaches them.
    private let controllers = NSHashTable<WKUserContentController>.weakObjects()
    private var hosts: [ObjectIdentifier: (String?, Bool)] = [:]

    /// Before each page: the kinds this site has on go on, the rest off.
    /// `bare`: the original page, with nothing blocked, once.
    func tune(_ controller: WKUserContentController, for host: String?, bare: Bool = false) {
        controllers.add(controller)
        hosts[ObjectIdentifier(controller)] = (host, bare)
        let site = Sites.shared.settings(for: host)
        var on: [WKContentRuleList] = []
        if !bare && ProcessInfo.processInfo.environment["QUO_NOBLOCK"] == nil {
            if site.blockAds { on += [builtIn[.ads], fetched[.ads]].compactMap { $0 } }
            if site.blockTrackers { on += [builtIn[.trackers], fetched[.trackers]].compactMap { $0 } }
            if site.blockCookieBanners { on += [builtIn[.cookies], fetched[.cookies]].compactMap { $0 } }
        }
        let signature = on.map(\.identifier).joined(separator: ",") as NSString
        if holding.object(forKey: controller) == signature { return }
        controller.removeAllContentRuleLists()
        on.forEach(controller.add)
        holding.setObject(signature, forKey: controller)
    }

    /// A list arrived or a site's settings changed: every page again.
    func retune() {
        for controller in controllers.allObjects {
            let (host, bare) = hosts[ObjectIdentifier(controller)] ?? (nil, false)
            tune(controller, for: host, bare: bare)
        }
    }

    /// How many of the addresses a page asked for were ads or trackers
    /// this site blocks: those it named in its markup, which never loaded.
    func count(_ addresses: [String], on host: String?) -> Int {
        let site = Sites.shared.settings(for: host)
        var domains: [String] = []
        if site.blockAds { domains += Blocker.adDomains }
        if site.blockTrackers { domains += Blocker.trackerDomains }
        let pageHost = Sites.key(host) ?? ""
        var seen = Set<String>()
        for address in addresses {
            guard let other = URL(string: address)?.host()?.lowercased(), !other.hasSuffix(pageHost) else { continue }
            if domains.contains(where: { other == $0 || other.hasSuffix("." + $0) }) { seen.insert(address) }
        }
        return seen.count
    }

    // MARK: - click IDs

    /// The parameters that only follow you, as the Mac removes them.
    static let clickIDs: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid", "mc_eid", "mc_cid", "yclid",
        "twclid", "ttclid", "li_fat_id", "igshid", "_hsenc", "_hsmi", "oly_enc_id", "oly_anon_id", "vero_id",
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "utm_id", "s_cid", "mkt_tok",
    ]

    /// An address without them, and how many were taken out.
    static func scrub(_ url: URL) -> (URL, Int)? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = parts.queryItems else { return nil }
        let kept = items.filter { !clickIDs.contains($0.name.lowercased()) }
        guard kept.count < items.count else { return nil }
        parts.queryItems = kept.isEmpty ? nil : kept
        guard let clean = parts.url else { return nil }
        return (clean, items.count - kept.count)
    }
}
