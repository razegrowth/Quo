import Foundation
import NaturalLanguage

/// History found by what the pages were about, not only by the words in
/// them: "flights to lisbon" finds the page called "TAP Air Portugal: Book
/// cheap tickets", "that pasta recipe" a page called "Cacio e pepe". Each
/// visited page's title is placed in the phone's own sentence embedding
/// (NLEmbedding, built into iOS, no Apple Intelligence needed), and what you
/// type is placed in it too; the nearest pages are suggested after the ones
/// that match by word. Worked out on the phone, kept only in memory.
@MainActor
final class Meaning {
    static let shared = Meaning()

    private var vectors: [String: [Double]] = [:]
    private var building: Task<Void, Never>?
    /// The sentence embedding where the phone has it; otherwise the average
    /// of the words' own vectors, which every iPhone has.
    private let embedding = Place(sentence: NLEmbedding.sentenceEmbedding(for: .english),
                                  words: NLEmbedding.wordEmbedding(for: .english))

    var available: Bool { embedding != nil }

    /// Where a piece of text sits in meaning.
    struct Place: @unchecked Sendable {
        let sentence: NLEmbedding?
        let words: NLEmbedding?
        let usesSentences: Bool

        init?(sentence: NLEmbedding?, words: NLEmbedding?) {
            guard sentence != nil || words != nil else { return nil }
            self.sentence = sentence
            self.words = words
            usesSentences = sentence != nil
        }

        private static let skipped: Set<String> = ["the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "with",
                                                   "at", "by", "from", "is", "are", "that", "this", "my", "your", "how",
                                                   "what", "i", "it", "be", "as"]

        func vector(for text: String) -> [Double]? {
            if let sentence { return sentence.vector(for: text) }
            guard let words else { return nil }
            var sum: [Double]?
            var count = 0.0
            for raw in text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                let word = String(raw)
                guard word.count > 1, !Self.skipped.contains(word), let vector = words.vector(for: word) else { continue }
                if sum == nil { sum = vector } else { for i in vector.indices { sum![i] += vector[i] } }
                count += 1
            }
            return sum.map { $0.map { $0 / count } }
        }
    }

    /// The titles' places, worked out off the main thread a few at a time.
    func build(_ visits: [History.Visit]) {
        guard let embedding, building == nil else { return }
        let wanted = visits.filter { !$0.title.isEmpty && vectors[$0.url] == nil }.map { ($0.url, $0.title) }
        guard !wanted.isEmpty else { return }
        nonisolated(unsafe) let model = embedding
        building = Task {
            var made: [String: [Double]] = [:]
            for chunk in stride(from: 0, to: wanted.count, by: 200) {
                let part = Array(wanted[chunk..<min(chunk + 200, wanted.count)])
                let done = await Task.detached(priority: .utility) {
                    var out: [String: [Double]] = [:]
                    for (url, title) in part { if let vector = model.vector(for: title) { out[url] = vector } }
                    return out
                }.value
                made.merge(done) { $1 }
            }
            vectors.merge(made) { $1 }
            building = nil
        }
    }

    func forget(_ urls: Set<String>? = nil) {
        if let urls { for url in urls { vectors[url] = nil } } else { vectors = [:] }
    }

    /// Pages near in meaning to what's typed, the nearest first, above a
    /// closeness that keeps loose guesses out.
    func nearest(_ typed: String, in visits: [History.Visit], limit: Int) -> [History.Visit] {
        let words = typed.split(whereSeparator: \.isWhitespace)
        guard let embedding, words.count >= 2, let query = embedding.vector(for: typed) else { return [] }
        let byURL = Dictionary(visits.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var scored: [(History.Visit, Double)] = []
        for (url, vector) in vectors {
            guard let visit = byURL[url] else { continue }
            let closeness = Self.cosine(query, vector)
            if closeness > (embedding.usesSentences ? 0.62 : Self.wordCut) { scored.append((visit, closeness)) }
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    /// How close averaged word vectors must be to count (tuned on test runs).
    static var wordCut = 0.52

    nonisolated static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in a.indices { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }

    /// For a test run: the closeness of each page to what's typed.
    func scores(_ typed: String, in visits: [History.Visit]) -> [(String, Double)] {
        guard let embedding, let query = embedding.vector(for: typed) else { return [] }
        return visits.compactMap { visit in vectors[visit.url].map { (visit.title, Self.cosine(query, $0)) } }
            .sorted { $0.1 > $1.1 }
    }
}
