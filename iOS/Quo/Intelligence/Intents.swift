import AppIntents
import Foundation

// Quo for Siri, Spotlight and Shortcuts: what the page in front says, read
// it aloud, send your tabs to your Mac, and open a link in Quo. Each is an
// App Shortcut, so it works by voice with no setting up ("Summarise this
// page in Quo").

/// What the page in front says, in two or three sentences, spoken or shown
/// by Siri. The page's own words when it's open, otherwise the page fetched
/// without your cookies, as a link's preview is. Apple Intelligence only.
struct SummarisePageIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarise This Page"
    static let description = IntentDescription("Says what the page in front of Quo is about, using Apple Intelligence on this iPhone.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard OnDevice.available else {
            return .result(value: "", dialog: "Summaries need Apple Intelligence, turned on in Settings.")
        }
        guard let tab = Tabs.shared.current ?? Tabs.shared.regular.max(by: { $0.lastActive < $1.lastActive }),
              let url = tab.url else {
            return .result(value: "", dialog: "There\u{2019}s no page open in Quo.")
        }
        let host = tab.host ?? ""
        var title = tab.shownTitle, text = ""
        if let page = await tab.readable() {
            title = page.title
            text = page.text
        } else {
            let read = await PageReader.readForSummary(url, store: tab.incognito ? nil : Tabs.shared.store(for: tab))
            title = read.title ?? title
            text = read.text
        }
        guard !text.isEmpty, let said = await OnDevice.summary(title: title, host: host, text: text) else {
            return .result(value: "", dialog: "Couldn\u{2019}t read \(title) just now.")
        }
        return .result(value: said, dialog: "\(said)")
    }
}

/// The page in front read aloud (Listen to Page), Quo opening to start it.
struct ReadAloudIntent: AppIntent {
    static let title: LocalizedStringResource = "Read This Page Aloud"
    static let description = IntentDescription("Reads the page in front of Quo aloud, with a Live Activity to pause or stop it.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        if let tab = Tabs.shared.current, !Listener.shared.reading(tab) { Listener.shared.toggle(tab) }
        return .result()
    }
}

/// Your open tabs sent to your Mac, each opening there in a moment, as
/// Send to Mac does one at a time.
struct SendTabsToMacIntent: AppIntent {
    static let title: LocalizedStringResource = "Send My Tabs to My Mac"
    static let description = IntentDescription("Opens the tabs you have open in Quo on your iPhone in Quo on your Mac.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let sync = MacSync.shared
        guard sync.on, let mac = sync.targets.first(where: { !$0.phone }) else {
            return .result(dialog: "Turn on Sync with Quo on your Mac first, in Quo\u{2019}s Settings.")
        }
        let tabs = Tabs.shared.regular.sorted { $0.lastActive > $1.lastActive }.prefix(SyncTabs.mostSent)
        var sent = 0
        for tab in tabs {
            guard let url = tab.url else { continue }
            sync.send(url, title: tab.shownTitle, to: mac)
            sent += 1
        }
        guard sent > 0 else { return .result(dialog: "There are no tabs open to send.") }
        return .result(dialog: "Sent \(sent) \(sent == 1 ? "tab" : "tabs") to \(mac.name).")
    }
}

/// A link opened in Quo, in a new tab.
struct OpenInQuoIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Quo"
    static let description = IntentDescription("Opens a web address in a new tab in Quo.")
    static let openAppWhenRun = true

    @Parameter(title: "Address")
    var url: URL

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$url) in Quo") }

    @MainActor
    func perform() async throws -> some IntentResult {
        Browser.shared.go(url, newTab: true)
        return .result()
    }
}

struct QuoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SummarisePageIntent(), phrases: [
            "Summarise this page in \(.applicationName)",
            "Summarize this page in \(.applicationName)",
            "What's this page about in \(.applicationName)",
        ], shortTitle: "Summarise This Page", systemImageName: "apple.intelligence")
        AppShortcut(intent: ReadAloudIntent(), phrases: [
            "Read this page in \(.applicationName)",
            "Read this aloud in \(.applicationName)",
        ], shortTitle: "Read This Aloud", systemImageName: "headphones")
        AppShortcut(intent: SendTabsToMacIntent(), phrases: [
            "Send my tabs to my Mac with \(.applicationName)",
            "Send my \(.applicationName) tabs to my Mac",
        ], shortTitle: "Send Tabs to Mac", systemImageName: "laptopcomputer.and.arrow.down")
        AppShortcut(intent: OpenInQuoIntent(), phrases: [
            "Open a link in \(.applicationName)",
        ], shortTitle: "Open in Quo", systemImageName: "safari")
    }
}
