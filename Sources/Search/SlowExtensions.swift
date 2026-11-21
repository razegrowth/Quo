import AppKit
import SwiftUI
import WebKit

// Extensions that slow pages down, found by what they cost, and offered
// "On click" (Site access) in a card at the side of the window.
//
// Each extension's scripts in a web page are timed where they do the work
// that makes a page feel slow: its handlers for the pointer and scrolling,
// and its change observers (ExtensionShims, `__searchCost`). The pages tell
// the browser now and then; this adds them up, per extension, over the last
// quarter of an hour. One that has taken more than two seconds of the pages'
// time in that while, and still runs on every site, is offered On click: it
// keeps working, a click on its button away, and pages don't carry it.
//
// Never for one that only does its job everywhere (a password manager), for
// one already limited, or after Don't Ask Again. Not Now waits a fortnight
// for that extension. Found on a Mac with Fonts Ninja and Ahrefs' toolbar
// both in every page: a third of Gmail's time went to the pointer's
// handlers, a fifth with the two on click, where Safari's is.
//
// New installs that look like tools — a button, scripts on every site, and
// a name that says so (SEO, fonts, an inspector, a colour picker) — start
// On click (`startsOnClick`), and say so.

@MainActor
final class SlowExtensions: ObservableObject {
    static let shared = SlowExtensions()

    struct Suggestion: Equatable, Identifiable {
        let id: String
        let name: String
        /// Of the pages' time, in the window counted.
        let seconds: Double
    }

    @Published private(set) var suggestion: Suggestion?

    /// The quarter of an hour counted, and what is too much in it.
    static let window: TimeInterval = 15 * 60
    static let tooMuch: Double = 2000

    static let neverKey = "extensions.slow.never"
    static func laterKey(_ id: String) -> String { "extensions.slow.later.\(id)" }

    private var costs: [String: [(at: Date, ms: Double)]] = [:]
    /// Asked about this run already: not again until the next.
    private var asked: Set<String> = []

    /// A page's report: what `id`'s handlers took there since its last.
    func noted(_ ms: Double, for id: String, at now: Date = Date()) {
        guard ms.isFinite, ms > 0 else { return }
        var kept = (costs[id] ?? []).filter { now.timeIntervalSince($0.at) < SlowExtensions.window }
        kept.append((now, min(ms, 60_000)))
        costs[id] = kept
        let total = kept.reduce(0) { $0 + $1.ms }
        if total >= SlowExtensions.tooMuch { consider(id, total: total, now: now) }
    }

    /// What `id` has cost in the window, for the bench and Settings.
    func cost(of id: String, at now: Date = Date()) -> Double {
        (costs[id] ?? []).filter { now.timeIntervalSince($0.at) < SlowExtensions.window }.reduce(0) { $0 + $1.ms }
    }

    private func consider(_ id: String, total: Double, now: Date) {
        guard suggestion == nil, !asked.contains(id), !Store.settings.bool(forKey: SlowExtensions.neverKey) else { return }
        if let later = Store.settings.object(forKey: SlowExtensions.laterKey(id)) as? Date, later > now { return }
        guard #available(macOS 15.4, *) else { return }
        let extensions = Extensions.shared
        guard let item = extensions.installed.first(where: { $0.id == id }), item.enabled,
              extensions.siteAccess(id).mode == .all,
              !SiteAccess.needsEverySite(name: item.name, said: [:]),
              extensions.buttons.contains(where: { $0.id == id }) else { return }
        asked.insert(id)
        suggestion = Suggestion(id: id, name: item.name, seconds: total / 1000)
    }

    /// Run on Click: only where its button is pressed, from now on.
    func accept() {
        guard let suggestion else { return }
        self.suggestion = nil
        costs[suggestion.id] = nil
        guard #available(macOS 15.4, *) else { return }
        let extensions = Extensions.shared
        var access = extensions.siteAccess(suggestion.id)
        access.mode = .click
        extensions.setSiteAccess(suggestion.id, access)
        Browsers.front?.announce("\(suggestion.name) now runs when you click its button")
    }

    /// Not Now: this one, not for a fortnight.
    func later() {
        guard let suggestion else { return }
        self.suggestion = nil
        Store.settings.set(Date().addingTimeInterval(14 * 86_400), forKey: SlowExtensions.laterKey(suggestion.id))
    }

    /// Don't Ask Again: about any extension.
    func never() {
        suggestion = nil
        Store.settings.set(true, forKey: SlowExtensions.neverKey)
    }

    /// For the bench: as it was before anything was noted or answered.
    func reset() {
        costs = [:]
        asked = []
        suggestion = nil
    }

    /// Where a page's report comes in: a handler in the extension's own
    /// content world, so the extension is the world's and not anything the
    /// page or another extension could say. One number, the milliseconds
    /// since its last report.
    final class CostHandler: NSObject, WKScriptMessageHandler {
        static let name = "searchCost"
        let id: String
        let world: WKContentWorld

        init(id: String) {
            self.id = id
            world = .world(name: "WebExtension-" + id)
            super.init()
        }

        func attach(_ controller: WKUserContentController) {
            controller.add(self, contentWorld: world, name: CostHandler.name)
        }

        func detach(_ controller: WKUserContentController) {
            controller.removeScriptMessageHandler(forName: CostHandler.name, contentWorld: world)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.world == world, let ms = (message.body as? NSNumber)?.doubleValue else { return }
            let id = self.id
            MainActor.assumeIsolated { SlowExtensions.shared.noted(ms, for: id) }
        }
    }

    // MARK: - new installs

    /// A tool you reach for, not one that works in every page: a button,
    /// scripts on every site, and a name or description that says it is
    /// for looking at pages — SEO, fonts, an inspector, a colour picker.
    /// Never a password manager, a blocker, dark mode, a translator or a
    /// writing aid, which do their work in the page without a click.
    static func startsOnClick(manifest: [String: Any], name: String, about: String) -> Bool {
        guard manifest["action"] != nil || manifest["browser_action"] != nil else { return false }
        let everywhere: Set<String> = ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"]
        let scripts = manifest["content_scripts"] as? [[String: Any]] ?? []
        guard scripts.contains(where: { ($0["matches"] as? [String] ?? []).contains(where: everywhere.contains) }) else { return false }
        let permissions = (manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        if permissions.contains(where: { $0.hasPrefix("declarativeNetRequest") || $0 == "webRequestBlocking" || $0 == "proxy" }) { return false }
        let words = (name + " " + about).lowercased()
        if SiteAccess.needsEverySite(name: name, said: [:]) { return false }
        let always = ["dark", "night", "translat", "grammar", "spell", "adblock", "ad block", "ublock", "block", "privacy",
                      "tracker", "vpn", "accessib", "dyslex", "read aloud", "speed", "autofill", "reader"]
        if always.contains(where: words.contains) { return false }
        let tools = ["seo", "font", "wappalyzer", "technology profiler", "inspector", "developer tool", "devtools", "dev tools",
                     "color picker", "colour picker", "eyedropper", "eye dropper", "page ruler", "css viewer", "whatfont",
                     "lighthouse", "web vitals", "tag assistant", "pixel helper", "backlink", "keyword", "serp"]
        return tools.contains(where: words.contains)
    }
}

/// The card at the side of the window: what an extension costs pages, and
/// On click a press away.
struct SlowExtensionCard: View {
    @ObservedObject var slow = SlowExtensions.shared
    /// Drawn with this instead of the one waiting, off screen (the bench).
    var drawn: SlowExtensions.Suggestion?

    var body: some View {
        ZStack {
            if let suggestion = drawn ?? slow.suggestion {
                card(suggestion)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Motion.settle, value: slow.suggestion)
    }

    private func card(_ suggestion: SlowExtensions.Suggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                icon(suggestion.id)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(suggestion.name) is slowing pages down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("It used \(SlowExtensionCard.seconds(suggestion.seconds)) of page time in the last 15 minutes, reacting to your pointer and scrolling. Set to On click, it runs only when you press its button.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 8) {
                Pill("Run on Click", filled: true) { slow.accept() }
                Pill("Not Now") { slow.later() }
                Spacer(minLength: 0)
                Button("Don't Ask Again") { slow.never() }
                    .buttonStyle(PressStyle())
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.14), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func icon(_ id: String) -> some View {
        if #available(macOS 15.4, *), let image = Extensions.shared.contexts[id]?.webExtension.icon(for: CGSize(width: 28, height: 28)) {
            Image(nsImage: image).resizable().interpolation(.high)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 28, height: 28)
        }
    }

    /// "2.4 seconds", "1 minute 5 seconds".
    static func seconds(_ value: Double) -> String {
        if value < 60 { return String(format: value < 10 ? "%.1f seconds" : "%.0f seconds", value) }
        let whole = Int(value.rounded())
        return "\(whole / 60) minute\(whole / 60 == 1 ? "" : "s") \(whole % 60) seconds"
    }
}
