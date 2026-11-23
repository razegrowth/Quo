import XCTest
@testable import Search

/// History between devices (SyncHistory.swift): what a record holds, when
/// it's written again, what's taken from another device, and that a Clear
/// History or a forgotten page on one device is made on the others, a page
/// visited since staying.
@MainActor
final class SyncHistoryTests: XCTestCase {
    let now = Date().timeIntervalSince1970
    let day: Double = 24 * 60 * 60

    func testARecordHoldsTheLastSixtyDaysOfWebPagesNewestFirst() {
        let visits = [
            SyncedVisit(u: "https://old.example/", t: "Old", c: 3, l: now - 61 * day),
            SyncedVisit(u: "https://a.example/", t: "A", c: 2, l: now - day),
            SyncedVisit(u: "https://b.example/", t: "B", c: 1, l: now - 60),
            SyncedVisit(u: "file:///Users/me/secret.txt", t: "File", c: 1, l: now),
            SyncedVisit(u: "https://a.example/", t: "A again", c: 1, l: now - 2 * day),
        ]
        let tidy = SyncHistory.tidy(visits, now: now)
        XCTAssertEqual(tidy.map(\.u), ["https://b.example/", "https://a.example/"])
        XCTAssertEqual(tidy.last?.t, "A", "each address once, its latest")
        let many = (0..<3_000).map { SyncedVisit(u: "https://e.example/\($0)", t: "", c: 1, l: now - Double($0)) }
        XCTAssertEqual(SyncHistory.tidy(many, now: now).count, SyncHistory.most)
    }

    func testARecordReadsBackAndIsWrittenOnlyWhenDue() throws {
        let visits = [SyncedVisit(u: "https://a.example/", t: "A", c: 2, l: now - 30)]
        let file = SyncHistory.file(device: "mac-1", name: "Mac", scope: SyncHistory.scope("profile-x"),
                                    visits: visits, forgets: HistoryForgets(), now: now)
        let read = try XCTUnwrap(SyncHistory.read(file))
        XCTAssertEqual(read.visits, visits)
        XCTAssertFalse(SyncHistory.due(file, visits: visits, forgets: HistoryForgets(), name: "Mac", now: now + 10), "nothing new")
        let more = visits + [SyncedVisit(u: "https://b.example/", t: "B", c: 1, l: now)]
        XCTAssertFalse(SyncHistory.due(file, visits: more, forgets: HistoryForgets(), name: "Mac", now: now + 10), "new visits wait two minutes")
        XCTAssertTrue(SyncHistory.due(file, visits: more, forgets: HistoryForgets(), name: "Mac", now: now + 130))
        XCTAssertTrue(SyncHistory.due(file, visits: visits, forgets: HistoryForgets(all: now + 5), name: "Mac", now: now + 10),
                      "a forget goes at once")
        XCTAssertNil(SyncHistory.read(SyncFile(format: 1, device: "x", name: nil, scope: "tabs-profile-x", written: now, items: file.items)),
                     "only a history record is read as one")
    }

    func testWhatIsTakenFromAnotherDevice() {
        let theirs = [
            SyncedVisit(u: "https://kept.example/", t: "", c: 1, l: now - 10),
            SyncedVisit(u: "https://cleared.example/", t: "", c: 1, l: now - 5 * day),
            SyncedVisit(u: "https://forgot.example/", t: "", c: 1, l: now - day),
            SyncedVisit(u: "https://again.example/", t: "", c: 1, l: now - 10),
        ]
        let mine = HistoryForgets(all: now - 2 * day, pages: ["https://forgot.example/": now - 100, "https://again.example/": now - 100])
        XCTAssertEqual(SyncHistory.taken(theirs, mine: mine).map(\.u), ["https://kept.example/", "https://again.example/"],
                       "nothing from before a Clear History, no page forgotten since, a page visited again after it was")
    }

    /// A History on a file of its own, once it has read it.
    private func loaded() async -> History {
        let history = History(file: "history-synctest-\(UUID().uuidString).json")
        for _ in 0..<400 where history.stillLoading { try? await Task.sleep(nanoseconds: 5_000_000) }
        return history
    }

    func testAnotherDevicesPagesAndForgetsMadeHere() async {
        let history = await loaded()
        history.take(URL(string: "https://mine.example/")!, title: "Mine", count: 1, last: Date(timeIntervalSince1970: now - 3 * day))
        history.take(URL(string: "https://recent.example/")!, title: "Recent", count: 1, last: Date(timeIntervalSince1970: now - 10))
        let taken = history.take(handed: [SyncedVisit(u: "https://theirs.example/", t: "Theirs", c: 4, l: now - 60)])
        XCTAssertEqual(taken, 1)
        XCTAssertEqual(history.take(handed: [SyncedVisit(u: "https://theirs.example/", t: "Theirs", c: 4, l: now - 60)]), 0,
                       "the same page again changes nothing")
        XCTAssertTrue(history.handed().contains { $0.u.contains("theirs.example") && $0.c == 4 })
        // Cleared on the other device two days ago: what was older goes, what's newer stays.
        let gone = history.forget(handed: HistoryForgets(all: now - 2 * day))
        XCTAssertEqual(gone, 1)
        let left = Set(history.handed().map(\.u).compactMap { URL(string: $0)?.host() })
        XCTAssertFalse(left.contains("mine.example"))
        XCTAssertTrue(left.contains("recent.example") && left.contains("theirs.example"), "\(left)")
        XCTAssertTrue(history.forgets.isEmpty, "made here, not written down as this device's own forget")
    }

    func testForgettingHereIsWrittenDownForTheOthers() async {
        let history = await loaded()
        history.take(URL(string: "https://a.example/page")!, title: "A", count: 1, last: Date())
        let key = history.everything().first?.key ?? ""
        history.forget(key)
        XCTAssertEqual(history.forgets.pages.keys.first.flatMap { URL(string: $0)?.host() }, "a.example")
        history.forget()
        XCTAssertNotNil(history.forgets.all)
        XCTAssertTrue(history.forgets.pages.isEmpty, "a Clear History says it all")
    }
}
