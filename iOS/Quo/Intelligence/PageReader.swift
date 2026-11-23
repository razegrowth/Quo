import Foundation
import WebKit

// What a page says, read without drawing it: fetched once with nothing of
// yours (no cookies, no sign-in), and only when a site turns a stranger
// away, once more with that site's own cookies from the tab's store, never
// carried across a redirect to another host. The Mac's own reader
// (Sources/Search/Intelligence.swift, LinkPreview), so the two read pages
// the same way.
enum PageReader {
    struct Read: Equatable {
        var title: String?
        var description: String?
        var text: String
        var failed: String?
        /// Turned away as a stranger would be: 401, 403, 404, or sent to a
        /// sign-in page. Worth asking again signed in.
        var refused = false
    }

    /// Nothing of yours goes with it: no cookies, no cache, no credentials.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml",
            "Sec-GPC": "1",
        ]
        return URLSession(configuration: configuration)
    }()

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

    /// A page read for a summary: as a stranger, then signed in to its own
    /// site if refused (never from Incognito, whose sign-ins are its own).
    static func readForSummary(_ url: URL, store: WKWebsiteDataStore?) async -> Read {
        var read = await read(url)
        if read.refused, let store, store.isPersistent {
            let cookies = await store.httpCookieStore.allCookies()
            let header = cookieHeader(for: url, from: cookies)
            if !header.isEmpty, !Task.isCancelled { read = await self.read(url, cookie: header) }
        }
        return read
    }
}
