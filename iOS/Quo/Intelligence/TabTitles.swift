import Foundation

/// Settings › Shorter tab names: a long page title, as the tab switcher
/// shows it, in a few words of Apple's model's choosing ("Linear pricing"
/// for "Pricing - Linear"). The page's own title stays everywhere else
/// (history, sharing, sending to your Mac). On by default where Apple
/// Intelligence is; not offered where it isn't.
@MainActor
enum TabTitles {
    static var on: Bool { AppSettings.shared.shortTitles && OnDevice.available }

    /// Answers already had, by site and title, so a page reloaded or a tab
    /// opened twice costs nothing. Only in memory.
    private static var known: [String: String] = [:]
    private static var waiting: [UUID: DispatchWorkItem] = [:]
    /// One question at a time, in the order asked: a dozen tabs restored at
    /// launch line up behind each other rather than all at once.
    private static var tail: Task<Void, Never>?

    /// A title short enough already is left as it is.
    nonisolated static func short(_ title: String) -> Bool {
        title.count <= 26 && title.split(whereSeparator: \.isWhitespace).count <= 4
    }

    /// The model's answer made fit for a tab: one line, no quotes or full
    /// stop, and nil when it is no shorter than the title or not a name.
    nonisolated static func tidy(_ answer: String, from title: String) -> String? {
        var name = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`*.:"))
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.lowercased().hasPrefix("name ") { name = String(name.dropFirst(5)) }
        guard !name.isEmpty, name.count <= 40, name.count < title.count,
              name.split(whereSeparator: \.isWhitespace).count <= 6 else { return nil }
        return name
    }

    /// A tab's title changed: once it has stopped changing, ask for a
    /// shorter one, unless it's short already.
    static func changed(_ tab: Tab) {
        waiting[tab.id]?.cancel()
        let title = tab.title
        guard on, !tab.incognito, !title.isEmpty, !short(title) else {
            if tab.short != nil { tab.short = nil }
            return
        }
        let full = tab.url?.host() ?? ""
        let host = full.hasPrefix("www.") ? String(full.dropFirst(4)) : full
        let key = host + "\n" + title
        if let had = known[key] {
            tab.short = had
            return
        }
        let work = DispatchWorkItem { [weak tab] in
            guard let tab else { return }
            waiting[tab.id] = nil
            let before = tail
            tail = Task { @MainActor [weak tab] in
                await before?.value
                guard let tab, tab.title == title, on else { return }
                let name = await OnDevice.shortTitle(title, host: host)
                if let name { known[key] = name }
                if known.count > 400 { known.removeAll() }
                if tab.title == title, on { tab.short = name }
                Trace.mark("short title \(name ?? "none") for \(title)")
            }
        }
        waiting[tab.id] = work
        // A loading page changes its title a few times; ask about the last.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    /// The setting turned on or off.
    static func refresh() {
        for tab in Tabs.shared.all { on ? changed(tab) : (tab.short = nil) }
    }
}
