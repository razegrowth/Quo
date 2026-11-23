import Foundation

/// Where typed words should go, before they're a search:
///
///   - a site's name ("github", "nytimes") goes to the site: one you've been
///     to, pinned or bookmarked, or one of the few big sites whose name is
///     only ever that site;
///   - a question ("how do I…", "what is…?") goes to the answer engine you
///     chose in Settings › Search Engine › Questions go to, Perplexity or
///     ChatGPT; with none chosen, asking one is the top suggestion.
///
/// Everything else is a search, as before. Decided here on the phone, as you
/// type: nothing is sent anywhere to decide it.
@MainActor
enum Routing {
    /// Words that only ever mean one site, typed alone.
    private static let known: [String: String] = [
        "youtube": "youtube.com", "github": "github.com", "reddit": "reddit.com", "wikipedia": "wikipedia.org",
        "netflix": "netflix.com", "gmail": "mail.google.com", "linkedin": "linkedin.com", "instagram": "instagram.com",
        "facebook": "facebook.com", "twitter": "x.com", "figma": "figma.com", "notion": "notion.so",
        "spotify": "open.spotify.com", "chatgpt": "chatgpt.com", "perplexity": "perplexity.ai", "nytimes": "nytimes.com",
        "hackernews": "news.ycombinator.com", "stackoverflow": "stackoverflow.com", "twitch": "twitch.tv",
        "pinterest": "pinterest.com", "dribbble": "dribbble.com", "vercel": "vercel.com", "airbnb": "airbnb.com",
    ]

    /// The site a single typed word names, or nil.
    static func site(for typed: String) -> URL? {
        let word = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard word.count >= 3, word.count <= 30, !word.contains(" "), !word.contains("."),
              word.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return nil }
        // A site you've been to, the most visited first.
        let visited = History.shared.visits
            .filter { visit in
                guard let host = URL(string: visit.url)?.host()?.lowercased() else { return false }
                let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                return bare.split(separator: ".").first.map(String.init) == word
            }
            .max { $0.count < $1.count }
        if let visited, let url = URL(string: visited.url), let host = url.host() {
            return URL(string: "https://\(host)/")
        }
        // A pin or bookmark of yours.
        let sync = MacSync.shared
        let marks = sync.pins(in: sync.currentSpaceID).map(\.home) + SearchPanel.flatten(sync.bookmarks).map(\.1)
        for home in marks {
            guard let url = URL(string: home), let host = url.host()?.lowercased() else { continue }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if bare.split(separator: ".").first.map(String.init) == word { return URL(string: "https://\(host)/") }
        }
        return known[word].flatMap { URL(string: "https://\($0)/") }
    }

    private static let askers: Set<String> = [
        "what", "why", "how", "who", "whom", "whose", "when", "where", "which", "is", "are", "was", "were", "can",
        "could", "should", "would", "will", "do", "does", "did", "explain", "compare", "difference", "whats", "hows",
    ]

    /// Whether the words read as a question a person would ask, rather than
    /// keywords: a question mark, or four words or more starting with one of
    /// the words questions start with.
    static func isQuestion(_ typed: String) -> Bool {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 3, Address.url(text) == nil else { return false }
        if text.hasSuffix("?") { return true }
        guard words.count >= 4, let first = words.first else { return false }
        return askers.contains(first.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: ""))
    }

    /// The answer engine questions go to, if one is chosen or is the search
    /// engine itself.
    static var answerEngine: Engine? {
        let settings = AppSettings.shared
        if [.perplexity, .chatgpt].contains(settings.engine) { return settings.engine }
        return settings.answers
    }

    /// The engine offered for a question when none is chosen.
    static let offered: Engine = .perplexity

    static func url(_ engine: Engine, asking words: String) -> URL? {
        Engine.url(for: words, template: engine.template(custom: ""))
    }
}
