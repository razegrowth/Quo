import AppKit
import Foundation
import SwiftUI
import WebKit
#if canImport(FoundationModels)
import FoundationModels
#endif

// Apple's own model, the one Apple Intelligence runs on this Mac (macOS 26
// and later, Apple silicon, Apple Intelligence turned on): three small jobs
// it is good at, and nothing it reads leaves the Mac.
//
//   - a shorter name for a tab whose page calls itself something long
//     (TabTitles, Settings › Tabs);
//   - Tidy Tabs: a space's loose tabs sorted into named groups (Browser
//     .tidyTabs, the View menu and the space's menu);
//   - what a link says, before you open it: hold Shift over it (LinkPreview).
//
// On a Mac without it, none of the three is offered: the setting, the menu
// item and the card don't appear, and a preview shows the page's own
// description instead of a summary. Search's downloaded model (AIEngine)
// is for asking questions of a page, and stays that.
enum OnDevice {
    /// Whether Apple's model can answer now. Asked each time: Apple
    /// Intelligence can be turned on or off, or still be downloading.
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// A tab's name in two to four words, or nil.
    static func shortTitle(_ title: String, host: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), available {
            let session = LanguageModelSession(instructions: """
                You shorten browser tab titles so a person can tell their tabs apart in a narrow sidebar. \
                Answer with the short title alone, two to five words, no quotes, no full stop.
                Keep what makes this page different from the others: its subject, and any number, date, ticket or \
                issue number, version or person's name in it, with a word or two of what it is about.
                Drop the site's name, counts in brackets, email addresses, and filler like Home, Dashboard, Best Prices or Recipe.
                If the title says nothing specific, like "Untitled document", answer with the title as it is, without the site's name.
                Examples:
                Title: Pricing - Linear  →  Linear pricing
                Title: Inbox (12) - jo@example.com - Gmail  →  Gmail inbox
                Title: Re: Contract renewal for Acme (3) - jo@example.com - Gmail  →  Re: Acme contract renewal
                Title: ENG-88 Login button does nothing on Safari - Linear  →  ENG-88 login button
                Title: iPhone 17 Pro review: the best camera yet | The Verge  →  iPhone 17 Pro review
                """)
            let prompt = "Title: \(title)\nSite: \(host)"
            guard let answer = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2)) else { return nil }
            return TabTitles.tidy(answer.content, from: title)
        }
        #endif
        return nil
    }

    /// Groups of the tabs, each a name and its tabs' titles as the model
    /// gave them back. Titles rather than numbers: a small model counting a
    /// list of tabs slips by one now and then.
    static func groups(_ titles: [String]) async -> [(name: String, titles: [String])]? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), available {
            let session = LanguageModelSession(instructions: """
                You sort a person's browser tabs into a few groups by what they are for. Only group tabs that clearly \
                belong together, at least two in a group. A tab that fits no group stays out of every group. Name each \
                group in one to three plain words, the way a person would label a folder.
                """)
            let list = titles.map { "- " + $0 }.joined(separator: "\n")
            guard let answer = try? await session.respond(to: "Tabs:\n\(list)", generating: Sorting.self,
                                                          options: GenerationOptions(sampling: .greedy)) else { return nil }
            return answer.content.groups.map { ($0.name, $0.tabs) }
        }
        #endif
        return nil
    }

    /// A folder's name for tabs already put together, from their titles
    /// alone: for a group whose first name says nothing about them.
    static func folderName(_ titles: [String]) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), available {
            let session = LanguageModelSession(instructions: """
                You name a folder of browser tabs. Answer with the name alone: one to three words, no quotes, no \
                explanation. Say the place, product, project or subject the tabs share, using a word from their titles.
                """)
            guard let answer = try? await session.respond(to: titles.map { "- " + $0 }.joined(separator: "\n"),
                                                          options: GenerationOptions(sampling: .greedy)) else { return nil }
            var name = answer.content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            name = name.split(separator: ":").first.map(String.init) ?? name
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*.").union(.whitespaces))
            guard !name.isEmpty, name.split(separator: " ").count <= 4, name.count <= 40 else { return nil }
            return name
        }
        #endif
        return nil
    }

    /// What a page says, in two or three sentences, or nil.
    static func summary(title: String, host: String, text: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), available {
            let session = LanguageModelSession(instructions: """
                You tell a person what a web page says before they open it. In two or three short sentences, say what \
                the page is and what it says that matters, plainly. Start with what it says, never with words like \
                "This page", "The page" or "The article", and don't repeat the title. Leave out the site's own menus, \
                notices, error messages and cookie banners: only what the page itself is about. \
                If the text is only a sign-in wall, cookie notice or error, say so in one sentence.
                """)
            let prompt = "Title: \(title)\nSite: \(host)\n\nText:\n\(text)"
            guard let answer = try? await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3)) else { return nil }
            let said = answer.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return said.isEmpty ? nil : said
        }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
@Generable
struct Sorting {
    @Guide(description: "Groups of tabs that belong together. Tabs that fit no group are left out.")
    var groups: [Sorted]
}

@available(macOS 26, *)
@Generable
struct Sorted {
    @Guide(description: "The group's name, one to three words")
    var name: String
    @Guide(description: "The titles of the tabs in this group, each copied exactly as listed")
    var tabs: [String]
}
#endif

// MARK: - shorter tab names

/// Settings › Tabs › Shorter tab names: a long page title, as its tab shows
/// it, in a few words of Apple's model's choosing ("Q3 Growth Plan" for
/// "Untitled document - Google Docs"). The page's own title stays everywhere
/// else (the window, bookmarks, history, a tab's tooltip), and a name you
/// gave a tab always wins. Off unless turned on.
@MainActor
enum TabTitles {
    static let key = "tabs.shortTitles"
    static var on = false {
        didSet { if on != oldValue { Browsers.all.flatMap(\.tabs).forEach { on ? changed($0) : $0.objectWillChange.send() } } }
    }

    /// Answers already had, by site and title, so a page reloaded or a tab
    /// opened twice costs nothing. Only in memory.
    private static var known: [String: String] = [:]
    private static var waiting: [Tab.ID: DispatchWorkItem] = [:]
    /// One question at a time, in the order asked: dozens of tabs restored
    /// at launch line up behind each other rather than all at once.
    private static var tail: Task<Void, Never>?

    /// A title short enough already is left as it is.
    nonisolated static func short(_ title: String) -> Bool {
        title.count <= 26 && title.split(whereSeparator: \.isWhitespace).count <= 4
    }

    /// The model's answer made fit for a tab: one line, no quotes or full
    /// stop, and nil when it is no shorter than the title or not a name.
    nonisolated static func tidy(_ answer: String, from title: String) -> String? {
        var name = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*.:"))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("name ") { name = String(name.dropFirst(5)) }
        guard !name.isEmpty, name.count <= 40, name.count < title.count,
              name.split(whereSeparator: \.isWhitespace).count <= 6 else { return nil }
        return name
    }

    /// A tab's title changed: once it has stopped changing, ask for a
    /// shorter one, unless it is short already or the tab has your name.
    static func changed(_ tab: Tab) {
        waiting[tab.id]?.cancel()
        let title = tab.title
        guard on, tab.name == nil, !title.isEmpty, !short(title) else {
            if tab.short != nil { tab.short = nil }
            return
        }
        let full = tab.address?.host() ?? tab.pending?.host() ?? ""
        let host = full.hasPrefix("www.") ? String(full.dropFirst(4)) : full
        let key = host + "\n" + title
        if let had = known[key] {
            tab.short = had
            return
        }
        guard OnDevice.available else { return }
        let work = DispatchWorkItem { [weak tab] in
            guard let tab else { return }
            waiting[tab.id] = nil
            let before = tail
            tail = Task { @MainActor [weak tab] in
                await before?.value
                guard let tab, tab.title == title, on else { return }
                let name = await OnDevice.shortTitle(title, host: host)
                if let name { known[key] = name }
                if known.count > 600 { known.removeAll() }
                if tab.title == title, on { tab.short = name }
            }
        }
        waiting[tab.id] = work
        // A loading page changes its title a few times; ask about the last.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }
}

// MARK: - what a link says

/// Hold Shift over a link and, a moment later, a card at the foot of the
/// page says what's behind it: the page's title and site, and two or three
/// sentences from Apple's model (or the page's own description without
/// it). The page is fetched once, with nothing of yours: no cookies, no
/// sign-in, through the proxy when one is set, so the site sees a visit
/// from nobody in particular. Only when asked: never on a plain hover.
@MainActor
final class LinkPreview: ObservableObject {
    struct Card: Equatable {
        let url: URL
        var title: String
        var site: String
        var summary: String?
        /// Still being fetched or read.
        var reading: Bool
        /// The page couldn't be read: not a web page, or no answer.
        var failed: String?
        /// The link's address as the bubble shows it, until the title comes.
        var address: String
        /// Where the pointer was on the page, from its top left: the card
        /// opens just under it, or above it near the foot of the page.
        var anchor: CGPoint
        /// The page the link is on, so a split's other pane doesn't show it.
        var page: ObjectIdentifier?
    }

    @Published private(set) var card: Card?
    static let key = "links.preview"
    static var on = true

    /// The link under the pointer, as the address bubble has it, and the
    /// page it's on.
    private var hovered: URL?
    private weak var view: NSView?
    private var holding: DispatchWorkItem?
    private var job: Task<Void, Never>?
    private var monitor: Any?
    private static var known: [URL: Card] = [:]

    init() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.take(event) }
            return event
        }
    }

    /// From the page: the link the pointer is on, or none.
    func hover(_ address: String?, over page: NSView? = nil) {
        if let page { view = page }
        let url = address.flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        guard url != hovered else { return }
        hovered = url
        if card?.url != url { dismiss() }
        // Shift already down as the pointer reaches the link.
        if url != nil, NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift { arm() }
    }

    private func take(_ event: NSEvent) {
        if event.type == .keyDown {
            // Shift held to type a capital is typing, not asking.
            holding?.cancel()
            if event.keyCode == 53 { dismiss() }
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .shift, hovered != nil { arm() } else { holding?.cancel() }
    }

    /// Shift alone, held a moment over a link.
    private func arm() {
        guard Self.on else { return }
        holding?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.show() }
        holding = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    /// For a test run: the card for `url`, as Shift over it would bring.
    func showNow(_ url: URL, at point: CGPoint? = nil, over page: NSView? = nil) {
        if let page { view = page }
        hovered = url
        testPoint = point
        show()
    }
    private var testPoint: CGPoint?

    func dismiss() {
        holding?.cancel()
        job?.cancel()
        job = nil
        if card != nil { card = nil }
    }

    private func show() {
        guard let url = hovered else { return }
        if var had = Self.known[url] {
            (had.anchor, had.page) = pointer()
            card = had
            return
        }
        let site = Address.pretty(url).split(separator: "/").first.map(String.init) ?? (url.host() ?? "")
        let (anchor, page) = pointer()
        let opening = Card(url: url, title: site, site: site, summary: nil, reading: true, failed: nil,
                           address: Address.pretty(url), anchor: anchor, page: page)
        card = opening
        job?.cancel()
        job = Task { [weak self] in
            var read = await Self.read(url)
            // Refused to a stranger (a private repo's 404, a sign-in page):
            // once more as you, with this site's own cookies from the tab's
            // store. Never from a private tab, whose sign-ins are its own.
            if read.refused, let store = await MainActor.run(body: { self?.signedInStore }) {
                let cookies = await store.httpCookieStore.allCookies()
                let header = Self.cookieHeader(for: url, from: cookies)
                if !header.isEmpty, !Task.isCancelled { read = await Self.read(url, cookie: header) }
            }
            guard !Task.isCancelled else { return }
            var made = opening
            made.title = read.title ?? site
            made.failed = read.failed
            // The title as soon as it's known, the summary still coming.
            if read.failed == nil, let self, self.hovered == url, self.card?.url == url { self.card = made }
            made.reading = false
            if read.failed == nil {
                if !read.text.isEmpty, let said = await OnDevice.summary(title: made.title, host: site, text: read.text) {
                    made.summary = said
                } else {
                    made.summary = read.description
                }
            }
            guard !Task.isCancelled, let self, self.hovered == url else { return }
            // Remembered for the link, but placed where the pointer is next time.
            Self.known[url] = made
            if Self.known.count > 60 { Self.known.removeAll() }
            self.card = made
        }
    }

    /// The cookie store of the page the link is on, unless it's a private
    /// tab's (kept in memory only, and never lent to a preview).
    var signedInStore: WKWebsiteDataStore? {
        guard let store = (view as? WKWebView)?.configuration.websiteDataStore, store.isPersistent else { return nil }
        return store
    }

    /// The pointer on the page it's over, from the page's top left.
    private func pointer() -> (CGPoint, ObjectIdentifier?) {
        if let testPoint { return (testPoint, nil) }
        guard let view, let window = view.window else { return (CGPoint(x: 40, y: 60), nil) }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let y = view.isFlipped ? point.y : view.bounds.height - point.y
        return (CGPoint(x: point.x, y: y), ObjectIdentifier(view))
    }

    // MARK: reading a page

    struct Read: Equatable {
        var title: String?
        var description: String?
        var text: String
        var failed: String?
        /// Turned away as a stranger would be: 401, 403, 404, or sent to a
        /// sign-in page. Worth asking again signed in.
        var refused = false
    }

    private static var session: URLSession {
        ProxyNetwork.kept("link-preview") {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieAcceptPolicy = .never
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 12
            configuration.httpAdditionalHeaders = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) \(Web.userAgentName)",
                "Accept": "text/html,application/xhtml+xml",
                "Sec-GPC": "1",
            ]
            ProxyNetwork.stamp(configuration)
            return URLSession(configuration: configuration)
        }
    }

    /// `cookie`: the Cookie header for `url`'s own site, when asking as
    /// you. It goes to that host alone: a redirect anywhere else drops it.
    static func read(_ url: URL, cookie: String? = nil) async -> Read {
        var request = URLRequest(url: url)
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let keeper = cookie == nil ? nil : SameHost(host: url.host()?.lowercased() ?? "")
        guard let (data, response) = try? await session.data(for: request, delegate: keeper) else {
            return Read(text: "", failed: "Couldn't reach it")
        }
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        // What's said if this is the last try: a stranger is told it's
        // private, someone signed in that it isn't theirs to see.
        let shut = cookie == nil ? "Private, or you need to be signed in to read it" : "Signed in, but not yours to see"
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 404: return Read(text: "", failed: cookie == nil ? "Not there, or private" : "Not there, or not yours to see", refused: true)
            case 401, 403: return Read(text: "", failed: shut, refused: true)
            default: return Read(text: "", failed: "The site answered \(http.statusCode)")
            }
        }
        if signIn(response.url, from: url) {
            return Read(text: "", failed: shut, refused: true)
        }
        if !type.isEmpty, !type.contains("html") {
            let kind = type.split(separator: ";").first.map(String.init) ?? type
            let size = ByteCountFormatter.string(fromByteCount: response.expectedContentLength > 0 ? response.expectedContentLength : Int64(data.count), countStyle: .file)
            return Read(text: "", failed: kind.contains("pdf") ? "A PDF, \(size)" : "Not a web page: \(kind)")
        }
        let html = String(decoding: data.prefix(2_000_000), as: UTF8.self)
        return parse(html)
    }

    /// Whether the page landed on is a sign-in page rather than the one
    /// asked for: a login or account path, or an accounts host.
    nonisolated static func signIn(_ landed: URL?, from asked: URL) -> Bool {
        guard let landed, landed != asked else { return false }
        let host = landed.host()?.lowercased() ?? ""
        let path = landed.path.lowercased()
        let words = ["login", "log-in", "signin", "sign-in", "sign_in", "/auth", "/sso", "/session", "/oauth", "accounts/"]
        return ["accounts.", "login.", "auth.", "signin.", "sso.", "id."].contains { host.hasPrefix($0) }
            || words.contains { path.contains($0) }
    }

    /// The Cookie header the tab's store would send to `url`: its host's
    /// cookies (and its parent domains' that ask to be shared), on a matching
    /// path, secure ones over https only, none expired.
    nonisolated static func cookieHeader(for url: URL, from cookies: [HTTPCookie], now: Date = Date()) -> String {
        guard let host = url.host()?.lowercased() else { return "" }
        let path = url.path.isEmpty ? "/" : url.path
        let https = url.scheme?.lowercased() == "https"
        let fitting = cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let hostFits = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
            let pathFits = path.hasPrefix(cookie.path.isEmpty ? "/" : cookie.path)
            return hostFits && pathFits && (!cookie.isSecure || https) && (cookie.expiresDate.map { $0 > now } ?? true)
        }
        return HTTPCookie.requestHeaderFields(with: fitting)["Cookie"] ?? ""
    }

    /// Keeps a signed-in request's cookies on the host they're for: a
    /// redirect to any other host goes without them.
    private final class SameHost: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let host: String
        init(host: String) { self.host = host }
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            var next = request
            if next.url?.host()?.lowercased() != host { next.setValue(nil, forHTTPHeaderField: "Cookie") }
            completionHandler(next)
        }
    }

    /// The title, description and readable text of a page's HTML: enough
    /// for a summary, without drawing it.
    nonisolated static func parse(_ html: String) -> Read {
        func meta(_ names: [String]) -> String? {
            for name in names {
                for pattern in ["<meta[^>]+(?:property|name)=[\"']\(name)[\"'][^>]*content=[\"']([^\"']*)[\"']",
                                "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]*(?:property|name)=[\"']\(name)[\"']"] {
                    if let found = first(pattern, in: html), !found.isEmpty { return entities(found) }
                }
            }
            return nil
        }
        let title = meta(["og:title", "twitter:title"])
            ?? first("<title[^>]*>([\\s\\S]*?)</title>", in: html).map { entities(squeeze(strip($0))) }
        let description = meta(["og:description", "description", "twitter:description"])
        var body = html
        for tag in ["script", "style", "noscript", "svg", "nav", "footer", "header", "form", "template", "aside"] {
            body = body.replacingOccurrences(of: "<\(tag)\\b[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        body = body.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: " ", options: .regularExpression)
        // What the page keeps out of sight until something goes wrong: an
        // element marked hidden, or drawn with display: none.
        body = body.replacingOccurrences(of: "<([a-z][a-z0-9-]*)\\b[^>]*(?:\\shidden(?=[\\s>=/])|style=[\"'][^\"']*display:\\s*none)[^>]*>[\\s\\S]*?</\\1>",
                                         with: " ", options: [.regularExpression, .caseInsensitive])
        // Paragraphs and headings carry what a page says; a page with none
        // gives its whole text.
        var parts: [String] = []
        if let blocks = try? NSRegularExpression(pattern: "<(p|h1|h2|h3|li|blockquote)\\b[^>]*>([\\s\\S]*?)</\\1>", options: .caseInsensitive) {
            let ns = body as NSString
            for match in blocks.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
                let piece = entities(squeeze(strip(ns.substring(with: match.range(at: 2)))))
                if piece.count > 2, !notice(piece) { parts.append(piece) }
            }
        }
        var text = parts.joined(separator: "\n")
        if text.count < 200 { text = entities(squeeze(strip(body))) }
        for phrase in noticePhrases { text = text.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive) }
        return Read(title: title?.isEmpty == false ? title : nil, description: description,
                    text: String(text.prefix(7_000)), failed: nil)
    }

    /// What sites say about themselves rather than the page: errors kept
    /// ready, session notices, skip links, cookie banners.
    nonisolated static let noticePhrases = [
        "There was an error while loading.", "Please reload this page.", "You can't perform that action at this time.",
        "You signed in with another tab or window.", "You signed out in another tab or window.",
        "You switched accounts on another tab or window.", "Reload to refresh your session.", "Dismiss alert",
        "Skip to content", "Skip to main content", "We use cookies", "Accept all cookies", "Enable JavaScript",
        "JavaScript is disabled", "Please enable JavaScript", "Something went wrong",
    ]

    nonisolated static func notice(_ piece: String) -> Bool {
        let lower = piece.lowercased()
        return noticePhrases.contains { lower.hasPrefix($0.lowercased()) } && piece.count < 160
    }

    nonisolated private static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func strip(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    nonisolated private static func squeeze(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    nonisolated private static func entities(_ text: String) -> String {
        var out = text
        for (from, to) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"),
                           ("&apos;", "'"), ("&nbsp;", " "), ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
                           ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“")] {
            out = out.replacingOccurrences(of: from, with: to)
        }
        if let numeric = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let ns = out as NSString
            var result = ""
            var last = 0
            for match in numeric.matches(in: out, range: NSRange(location: 0, length: ns.length)) {
                result += ns.substring(with: NSRange(location: last, length: match.range.location - last))
                if let code = Int(ns.substring(with: match.range(at: 1))), let scalar = Unicode.Scalar(code) {
                    result.append(Character(scalar))
                }
                last = match.range.location + match.range.length
            }
            result += ns.substring(from: last)
            out = result
        }
        return out
    }
}

/// The card, opening out of the pointer: just under the link, or above it
/// near the foot of the page. While the page is read its lines shimmer and
/// a glow in Apple Intelligence's colours runs round its edge; the summary
/// comes into focus as the glow goes. Click-through: the link under it
/// still opens as it would.
struct LinkPreviewCard: View {
    @ObservedObject var preview: LinkPreview
    @ObservedObject var status: LinkStatus
    var page: NSView? = nil

    var body: some View {
        GeometryReader { space in
            if let card = preview.card, page.map({ ObjectIdentifier($0) == card.page }) ?? true {
                let width = min(360, space.size.width - 20)
                let x = min(max(10, card.anchor.x - 22), space.size.width - width - 10)
                let below = card.anchor.y + 20
                let above = space.size.height - below < 210 && card.anchor.y > 230
                Group {
                    if above {
                        LinkCard(card: card)
                            .frame(width: width)
                            .frame(height: max(0, card.anchor.y - 14), alignment: .bottom)
                            .offset(x: x)
                            .transition(Self.opening(from: .bottomLeading))
                    } else {
                        LinkCard(card: card)
                            .frame(width: width)
                            .offset(x: x, y: below)
                            .transition(Self.opening(from: .topLeading))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .id(card.url)
            }
        }
        .allowsHitTesting(false)
    }

    /// Out of the pointer on Motion's out curve; gone at once on a fade.
    private static func opening(from corner: UnitPoint) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.92, anchor: corner).combined(with: .opacity).animation(Motion.out(0.32)),
            removal: .opacity.animation(Motion.out(0.12))
        )
    }
}

private struct LinkCard: View {
    let card: LinkPreview.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(card.site)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: OnDevice.available ? "apple.intelligence" : "text.magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(card.reading ? AnyShapeStyle(Glow.gradient(angle: .degrees(30))) : AnyShapeStyle(Palette.muted))
                    .symbolEffect(.pulse, options: .repeating, isActive: card.reading && !Motion.reduced)
            }
            Text(card.title == card.site && card.reading ? card.address : card.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(card.title == card.site && card.reading ? Palette.muted : Palette.ink)
                .lineLimit(2)
                .contentTransition(.opacity)
            Group {
                if let failed = card.failed {
                    Text(failed)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .transition(.unblur)
                } else if card.reading {
                    Shimmer()
                        .transition(.opacity)
                } else if let summary = card.summary {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.unblur)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .overlay { Glow(on: card.reading) }
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .animation(Motion.out(0.36), value: card.reading)
        .animation(Motion.out(0.28), value: card.title)
    }
}

/// Lines where the summary will be, a light running across them.
private struct Shimmer: View {
    var body: some View {
        TimelineView(.animation(paused: Motion.reduced)) { time in
            let phase = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            GeometryReader { space in
                let band = space.size.width * 0.55
                Rectangle()
                    .fill(Palette.ink.opacity(0.08))
                    .overlay {
                        LinearGradient(colors: [.clear, Glow.colours[1].opacity(0.55), Glow.colours[3].opacity(0.55), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (space.size.width + band) * phase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mask(lines(space.size.width))
            }
        }
        .frame(height: 8 * 3 + 7 * 2)
    }

    private func lines(_ width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach([1.0, 0.92, 0.58], id: \.self) { part in
                Capsule().frame(width: width * part, height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Apple Intelligence's colours running round the card's edge while it reads,
/// with a soft light of the same outside it.
private struct Glow: View {
    let on: Bool
    static let colours: [Color] = [
        Color(red: 1.00, green: 0.62, blue: 0.36), Color(red: 1.00, green: 0.42, blue: 0.62),
        Color(red: 0.74, green: 0.45, blue: 1.00), Color(red: 0.36, green: 0.62, blue: 1.00),
        Color(red: 1.00, green: 0.62, blue: 0.36),
    ]

    static func gradient(angle: Angle) -> AngularGradient {
        AngularGradient(colors: colours, center: .center, angle: angle)
    }

    var body: some View {
        TimelineView(.animation(paused: !on || Motion.reduced)) { time in
            let angle = Angle.degrees(time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360)
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            ZStack {
                shape.strokeBorder(Self.gradient(angle: angle), lineWidth: 1.5)
                shape.stroke(Self.gradient(angle: angle), lineWidth: 6)
                    .blur(radius: 10)
                    .opacity(0.55)
            }
        }
        .opacity(on ? 1 : 0)
        .allowsHitTesting(false)
    }
}

/// Coming into focus: from a blur and nothing to sharp and there.
private struct Unblur: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

extension AnyTransition {
    static var unblur: AnyTransition {
        .modifier(active: Unblur(radius: 6, opacity: 0), identity: Unblur(radius: 0, opacity: 1))
    }
}
