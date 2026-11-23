import XCTest
@testable import Search

/// Perplexity and ChatGPT among the search engines (Engine.swift): words go
/// to each as a search, and neither is asked for suggestions, nor anyone else
/// in its place.
final class AnswerEngineTests: XCTestCase {
    func testWordsGoToPerplexityAndChatGPT() {
        let perplexity = Engine.url(for: "best ramen tokyo", template: Engine.perplexity.template(custom: ""))
        XCTAssertEqual(perplexity?.absoluteString, "https://www.perplexity.ai/search?q=best%20ramen%20tokyo")
        let chatgpt = Engine.url(for: "c++ & rust?", template: Engine.chatgpt.template(custom: ""))
        XCTAssertEqual(chatgpt?.absoluteString, "https://chatgpt.com/?q=c%2B%2B%20%26%20rust%3F&hints=search")
        XCTAssertEqual(Engine.perplexity.title, "Perplexity")
        XCTAssertEqual(Engine.chatgpt.name(custom: ""), "ChatGPT")
    }

    func testNeitherIsAskedForSuggestions() {
        XCTAssertNil(EngineSuggest.endpoint(for: .perplexity))
        XCTAssertNil(EngineSuggest.endpoint(for: .chatgpt))
        XCTAssertNil(EngineSuggest.url(for: "words", engine: .chatgpt))
    }

    func testAnOlderQuoReadsThemAsTheDefault() {
        // What an older Quo for iPhone does with a name it doesn't know.
        XCTAssertNil(Engine(rawValue: "someday"))
        XCTAssertEqual(Engine(rawValue: "perplexity"), .perplexity)
    }
}
