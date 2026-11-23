import Foundation
import NaturalLanguage

// History found by what it was about, not only by its words: "japan trip"
// finds the Tokyo hotels and flights, "home loan" the mortgage calculator.
// Each word you type is set beside the words of every page's title and site
// in macOS's own word embedding (NaturalLanguage, on this Mac, nothing sent
// anywhere, no Apple Intelligence needed), and the pages whose words sit
// closest come under the ones that matched outright, as Close in meaning.
//
// Sentence embeddings were tried first and ranked a curry recipe above a
// monstera for "houseplant care"; a word's nearest word in a title does
// much better on titles, which are short and mostly nouns.
enum Meaning {
    /// How close a page's words must come, on average, to count: below it,
    /// a list of anything at all.
    static let threshold = -0.1

    private static let lock = NSLock()
    nonisolated(unsafe) private static var embeddings: [NLLanguage: NLEmbedding] = [:]
    nonisolated(unsafe) private static var missing: Set<NLLanguage> = []

    private static func embedding(for language: NLLanguage) -> NLEmbedding? {
        lock.lock()
        defer { lock.unlock() }
        if let kept = embeddings[language] { return kept }
        if missing.contains(language) { return nil }
        guard let made = NLEmbedding.wordEmbedding(for: language) else {
            missing.insert(language)
            return nil
        }
        embeddings[language] = made
        return made
    }

    /// Words that say nothing about what a page is.
    private static let filler: Set<String> = [
        "the", "a", "an", "in", "on", "of", "to", "for", "and", "or", "with", "from", "how", "what", "my", "is", "it",
        "at", "by", "best", "yet", "can", "i", "much", "without", "when", "after", "ready", "according", "easy", "your",
        "you", "this", "that", "are", "was", "be", "new", "top", "about", "all", "more", "www", "com", "org", "net", "html",
        "page", "home", "pages", "site", "official", "online", "free", "vs", "via", "into", "out", "up", "get", "do",
    ]

    /// The words of `text` worth comparing, lowercased.
    static func words(_ text: String) -> [String] {
        let lower = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = lower
        var out: [String] = []
        tokenizer.enumerateTokens(in: lower.startIndex..<lower.endIndex) { range, _ in
            let word = String(lower[range])
            if word.count > 1, !filler.contains(word), word.rangeOfCharacter(from: .letters) != nil, !out.contains(word) {
                out.append(word)
            }
            return out.count < 16
        }
        return out
    }

    /// The language to read `query` in: what it looks like, or English.
    static func language(of query: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(query)
        let guess = recognizer.dominantLanguage ?? .english
        return embedding(for: guess) != nil ? guess : .english
    }

    /// For each text, how close its words come to the query's: the mean,
    /// over the query's words, of each one's nearest word in the text, from
    /// -1 to 1. Nil when the query has no word the embedding knows.
    static func scores(for query: String, among texts: [String]) -> [Double]? {
        let language = language(of: query)
        guard let embedding = embedding(for: language) else { return nil }
        let asked = words(query).filter { embedding.contains($0) }
        guard !asked.isEmpty else { return nil }
        // Each distinct word's distance worked out once.
        var near: [String: Double] = [:]
        func closeness(_ a: String, _ b: String) -> Double {
            if a == b { return 1 }
            let key = a + "\u{1}" + b
            if let kept = near[key] { return kept }
            let made = 1 - embedding.distance(between: a, and: b, distanceType: .cosine)
            near[key] = made
            return made
        }
        return texts.map { text in
            let theirs = words(text).filter { embedding.contains($0) }
            guard !theirs.isEmpty else { return -1 }
            let total = asked.reduce(0.0) { sum, word in sum + (theirs.map { closeness(word, $0) }.max() ?? -1) }
            return total / Double(asked.count)
        }
    }

    /// Settings › AI & Agents › Find history by what it was about.
    nonisolated(unsafe) static var on = true

    /// The traces closest in meaning to `query`, best first, those already
    /// listed left out. Worked out away from the window's thread. None with
    /// the switch off.
    static func related(to query: String, among traces: [History.Trace], limit: Int = 30) async -> [History.Trace] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard on, query.count >= 3 else { return [] }
        let candidates = Array(traces.prefix(4000))
        return await Task.detached(priority: .userInitiated) {
            let texts = candidates.map { trace -> String in
                let site = trace.url.host()?.replacingOccurrences(of: "www.", with: "").split(separator: ".").first.map(String.init) ?? ""
                return trace.title + " " + site
            }
            guard let scores = scores(for: query, among: texts) else { return [] }
            return zip(candidates, scores)
                .filter { $0.1 > threshold }
                .sorted { $0.1 > $1.1 }
                .prefix(limit)
                .map(\.0)
        }.value
    }
}
