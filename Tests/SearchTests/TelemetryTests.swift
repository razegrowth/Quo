import XCTest
@testable import Search

/// What a fork's usage count sends (Telemetry.swift): the fields TelemetryDeck
/// needs, a hashed stand-in for the user and never the UUID itself, nothing
/// about browsing, and an install counted as new only when nothing from an
/// earlier launch is there.
final class TelemetryTests: XCTestCase {
    func testTheUserLeavesHashed() {
        let user = UUID().uuidString
        let sent = Telemetry.hashed(user)
        XCTAssertEqual(sent.count, 64)
        XCTAssertFalse(sent.contains(user))
        XCTAssertEqual(sent, Telemetry.hashed(user), "the same Mac counts as one")
        XCTAssertNotEqual(sent, Telemetry.hashed(UUID().uuidString))
    }

    func testASignalHasWhatTheIngestAPINeedsAndNoMore() throws {
        let user = UUID().uuidString
        let body = Telemetry.signals(["App.opened"], user: user)
        XCTAssertEqual(body.count, 1)
        let signal = try XCTUnwrap(body.first)
        XCTAssertEqual(Set(signal.keys), ["appID", "clientUser", "sessionID", "type", "isTestMode", "payload"])
        XCTAssertEqual(signal["type"] as? String, "App.opened")
        XCTAssertEqual(signal["clientUser"] as? String, Telemetry.hashed(user))
        let payload = try XCTUnwrap(signal["payload"] as? [String: String])
        XCTAssertTrue(payload.keys.allSatisfy { $0.hasPrefix("TelemetryDeck.AppInfo.") || $0.hasPrefix("TelemetryDeck.Device.") },
                      "only the version and the kind of Mac: \(payload.keys.sorted())")
        XCTAssertEqual(payload["TelemetryDeck.Device.platform"], "macOS")
        XCTAssertTrue(payload["TelemetryDeck.Device.systemVersion"]?.hasPrefix("macOS ") == true)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(body))
    }

    func testTheNamespaceIsInTheAddress() {
        XCTAssertTrue(Telemetry.endpoint.absoluteString.hasPrefix("https://nom.telemetrydeck.com/v2/"))
    }

    func testANewInstallIsCountedOnceAndAnOldOneNever() throws {
        let fresh = try XCTUnwrap(UserDefaults(suiteName: "telemetry.test.fresh.\(getpid())"))
        Telemetry.settleInstall(in: fresh)
        XCTAssertEqual(fresh.string(forKey: "telemetry.installed"), "due")
        fresh.set(true, forKey: "passkeys.for")
        Telemetry.settleInstall(in: fresh)
        XCTAssertEqual(fresh.string(forKey: "telemetry.installed"), "due", "settled once: a later launch's lines don't undo it")

        let old = try XCTUnwrap(UserDefaults(suiteName: "telemetry.test.old.\(getpid())"))
        old.set(true, forKey: "welcomed")
        Telemetry.settleInstall(in: old)
        XCTAssertEqual(old.string(forKey: "telemetry.installed"), "counted")

        fresh.removePersistentDomain(forName: "telemetry.test.fresh.\(getpid())")
        old.removePersistentDomain(forName: "telemetry.test.old.\(getpid())")
    }

    func testSearchItselfCountsNothing() {
        // No app id in the bundle under test, as in Search: no row, no sending.
        XCTAssertFalse(Telemetry.configured)
        XCTAssertNil(SettingsIndex.item("privacy.telemetry"))
    }
}
