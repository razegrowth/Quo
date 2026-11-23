import ActivityKit
import AppIntents
import Foundation

// Listen to Page on the Lock Screen and in the Dynamic Island: what's being
// read, how far, and buttons to pause or stop. Built into the app and its
// widget extension alike; the buttons' intents run in the app.

struct ListenAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var paused: Bool
        /// The paragraph being read, from 1, and how many there are.
        var part: Int
        var parts: Int
    }
    var title: String
    var site: String
}

/// What the Live Activity's buttons ask, answered by the app (Listener).
enum ListenControl {
    enum Action { case pauseOrGo, stop }
    @MainActor static var handler: ((Action) -> Void)?
}

struct PauseListening: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Go On"
    static let isDiscoverable = false
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        ListenControl.handler?(.pauseOrGo)
        return .result()
    }
}

struct StopListening: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Reading"
    static let isDiscoverable = false
    init() {}
    @MainActor func perform() async throws -> some IntentResult {
        ListenControl.handler?(.stop)
        return .result()
    }
}
