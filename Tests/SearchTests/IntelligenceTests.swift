import XCTest
@testable import Search

/// What doesn't need Apple's model (Intelligence.swift): which titles are
/// short enough already, how an answer is made fit for a tab, and what a
/// fetched page gives a link's card.
final class IntelligenceTests: XCTestCase {
    func testAShortTitleIsLeftAlone() {
        XCTAssertTrue(TabTitles.short("Hacker News"))
        XCTAssertTrue(TabTitles.short("Linear pricing"))
        XCTAssertFalse(TabTitles.short("Untitled document - Google Docs"))
        XCTAssertFalse(TabTitles.short("Q3 2026 Growth Plan: Paid Acquisition - Google Docs"))
    }

    func testAnAnswerIsMadeFitForATab() {
        let title = "Q3 2026 Growth Plan: Paid Acquisition, Lifecycle Email - Google Docs"
        XCTAssertEqual(TabTitles.tidy("\"Q3 2026 Growth Plan.\"", from: title), "Q3 2026 Growth Plan")
        XCTAssertEqual(TabTitles.tidy("Q3 Growth Plan\nThis is a planning doc.", from: title), "Q3 Growth Plan", "one line only")
        XCTAssertEqual(TabTitles.tidy("  **Growth plan**  ", from: title), "Growth plan")
        XCTAssertNil(TabTitles.tidy("", from: title))
        XCTAssertNil(TabTitles.tidy(title, from: title), "no shorter, no use")
        XCTAssertNil(TabTitles.tidy("A sentence that goes on and on about what this page might be", from: title + title))
    }

    func testAPageGivesItsTitleDescriptionAndText() {
        let html = """
        <html><head><title>Ignored &amp; plain</title>
        <meta content="Webb &amp; the water" property="og:title">
        <meta name="description" content="Water vapour around GJ 486 b.">
        <script>var secret = "never read";</script><style>p { color: red }</style></head>
        <body><nav><p>Home</p></nav><h1>Webb finds water</h1>
        <p>Astronomers found signs of water vapour, 26&nbsp;light years away.</p>
        <p>It&#39;s too hot for oceans.</p><footer><p>Copyright</p></footer></body></html>
        """
        let read = LinkPreview.parse(html)
        XCTAssertEqual(read.title, "Webb & the water", "og:title first, either attribute order, entities read")
        XCTAssertEqual(read.description, "Water vapour around GJ 486 b.")
        XCTAssertTrue(read.text.contains("Astronomers found signs of water vapour, 26 light years away."), read.text)
        XCTAssertTrue(read.text.contains("It's too hot for oceans."), read.text)
        XCTAssertFalse(read.text.contains("never read"), "scripts aren't text")
        XCTAssertFalse(read.text.contains("Copyright"), "nor footers")
        XCTAssertFalse(read.text.contains("Home"), "nor navigation")
    }

    func testWhatTheSiteSaysAboutItselfIsLeftOut() {
        let html = """
        <title>Refine homepage · Pull Request #18</title>
        <div class="flash flash-error" hidden><p>There was an error while loading. Please reload this page.</p></div>
        <div style="display: none"><p>Kept out of sight.</p></div>
        <p>You signed in with another tab or window. Reload to refresh your session.</p>
        <p>Changes to homepage messaging focus on funded startups and consultative booking.</p>
        """
        let read = LinkPreview.parse(html)
        XCTAssertFalse(read.text.contains("error while loading"), read.text)
        XCTAssertFalse(read.text.contains("out of sight"), read.text)
        XCTAssertFalse(read.text.contains("another tab"), read.text)
        XCTAssertTrue(read.text.contains("funded startups"), read.text)
    }

    func testAPageWithoutParagraphsGivesItsWholeText() {
        let read = LinkPreview.parse("<title>Bare</title><div>" + String(repeating: "words in a div ", count: 30) + "</div>")
        XCTAssertEqual(read.title, "Bare")
        XCTAssertTrue(read.text.hasPrefix("Bare words in a div"), read.text)
        XCTAssertLessThanOrEqual(LinkPreview.parse("<p>" + String(repeating: "x ", count: 10_000) + "</p>").text.count, 7_000)
    }

    func testOnlyTheSitesOwnCookiesGo() throws {
        func cookie(_ name: String, _ domain: String, path: String = "/", secure: Bool = false, expires: Date? = nil) -> HTTPCookie {
            var props: [HTTPCookiePropertyKey: Any] = [.name: name, .value: "1", .domain: domain, .path: path]
            if secure { props[.secure] = "TRUE" }
            if let expires { props[.expires] = expires }
            return HTTPCookie(properties: props)!
        }
        let jar = [cookie("own", "github.com"), cookie("shared", ".github.com"), cookie("api", "api.github.com"),
                   cookie("other", "gitlab.com"), cookie("deep", "github.com", path: "/settings"),
                   cookie("secure", "github.com", secure: true), cookie("old", "github.com", expires: Date(timeIntervalSinceNow: -60))]
        let header = LinkPreview.cookieHeader(for: URL(string: "https://github.com/razegrowth/quo")!, from: jar)
        let names = Set(header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces).split(separator: "=").first.map(String.init) ?? "" })
        XCTAssertEqual(names, ["own", "shared", "secure"], header)
        let plain = LinkPreview.cookieHeader(for: URL(string: "http://github.com/x")!, from: jar)
        XCTAssertFalse(plain.contains("secure"), "a secure cookie never over plain http")
        let sub = LinkPreview.cookieHeader(for: URL(string: "https://gist.github.com/x")!, from: jar)
        XCTAssertTrue(sub.contains("shared") && !sub.contains("own="), sub)
    }

    func testASignInPageIsToldApart() {
        let asked = URL(string: "https://linear.app/raze/issue/QUO-1")!
        XCTAssertTrue(LinkPreview.signIn(URL(string: "https://linear.app/login?next=x"), from: asked))
        XCTAssertTrue(LinkPreview.signIn(URL(string: "https://accounts.google.com/v3/signin/identifier"), from: asked))
        XCTAssertTrue(LinkPreview.signIn(URL(string: "https://github.com/session?return_to=x"), from: asked))
        XCTAssertFalse(LinkPreview.signIn(asked, from: asked), "the page asked for")
        XCTAssertFalse(LinkPreview.signIn(URL(string: "https://linear.app/raze/issue/QUO-1/fix-it"), from: asked))
    }

    func testTheModelIsAskedOnlyWhereItIs() async throws {
        guard OnDevice.available else { throw XCTSkip("no Apple Intelligence on this Mac") }
        let name = await OnDevice.shortTitle("Q3 2026 Growth Plan: Paid Acquisition, Lifecycle Email and Referral Experiments - Google Docs", host: "docs.google.com")
        XCTAssertNotNil(name)
        XCTAssertTrue(name?.contains("Q3") == true, name ?? "")
    }
}
