import AppKit

/// Handoff: the page in front is offered to your other devices, as Safari
/// offers its own. Quo for iPhone, or Safari on an iPhone without it, shows
/// it in the app switcher, and the Mac's own pages come here the same way:
/// macOS hands a web page from another device to the Mac's browser, which
/// is Quo once it's the default (Links.application(_:continue:)).
///
/// Never a private tab, an internal page or anything but http and https;
/// with none of those in front, nothing is offered. Handoff itself is the
/// Mac's: System Settings › General › AirDrop & Handoff.
@MainActor
enum Handoff {
    private static var activity: NSUserActivity?
    /// What's offered now, for the bench: nil when nothing is.
    private(set) static var offered: URL?

    /// The window in front, or its tab, changed: offer its page, or stop.
    static func noted(_ browser: Browser?) {
        guard let browser, browser === Browsers.front, let tab = browser.active, !tab.shy,
              let url = tab.address, ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else { return stop() }
        offered = url
        // A test run offers nothing to the devices of whoever runs it.
        guard !Store.testing else { return }
        let current = activity ?? {
            let made = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
            made.isEligibleForHandoff = true
            made.isEligibleForSearch = false
            made.isEligibleForPublicIndexing = false
            activity = made
            return made
        }()
        current.webpageURL = url
        current.title = tab.label
        current.becomeCurrent()
    }

    static func stop() {
        offered = nil
        activity?.invalidate()
        activity = nil
    }

    /// A page another device handed over: opened as a link from another
    /// app is, in a tab of the window in front.
    static func take(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == NSUserActivityTypeBrowsingWeb, let url = activity.webpageURL,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        Links.arrived(url)
        return true
    }
}
