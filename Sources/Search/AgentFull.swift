import AppKit
import WebKit

// Full control: an agent you allowed, with Settings › AI & Agents ›
// Give agents full control on, uses the whole browser as you would. Every
// window, space, group, pin and tab; every menu command (Shortcuts.swift's
// Command); bookmarks, history, downloads and settings; and pages — any
// tab's, with your sign-ins — through the page verbs AgentControl already
// has, plus scripts of its own in a world of their own.
//
// What it still never gets: saved passwords, card numbers and one-time
// codes (the page verbs and the script world's guard keep them back,
// PageScripts.scriptGuard), private tabs (never listed, never found), this
// switch, the agents switch and the agents you always allow (left out of
// AgentSettings). Before anything that can't be undone and takes a lot at
// once — clearing history, deleting a space, closing several tabs — you are
// asked in the window, and the agent hears your answer.
//
// Each verb does what the menus and the column do, through the same calls,
// so what happens next (the session written, the row redrawn, the space's
// pins kept) is what happens when you do it.

@MainActor
enum AgentFull {
    static let verbs: Set<String> = [
        "state", "commands", "command", "tab", "space", "group", "window", "bookmarks", "history",
        "downloads", "settings", "script",
    ]

    /// The verbs that may put a question to you, and wait for it.
    static let mayAsk: Set<String> = ["command", "space", "group", "window", "bookmarks"]

    /// Closing more tabs than this at once asks you first.
    static let many = 3

    static func short(_ id: UUID) -> String { String(id.uuidString.prefix(8)).lowercased() }

    /// A tab as get_state and list_tabs give it.
    static func describe(_ tab: Tab, in browser: Browser, _ session: AgentSession, control: AgentControl) -> [String: Any] {
        var out = control.describe(tab, session)
        out["mine"] = session.own.contains(tab.id)
        if browser.activeID == tab.id { out["active"] = true }
        if tab.pin != nil { out["pinned"] = true }
        if let name = tab.name { out["name"] = name }
        if let group = browser.group(of: tab) { out["group"] = short(group) }
        if tab.muted { out["muted"] = true }
        if tab.asleep { out["asleep"] = true }
        if let split = browser.split(for: tab) { out["split"] = short(split.id) }
        return out
    }
}

extension AgentControl {
    /// The window a request names (1 is the oldest, as get_state counts),
    /// or `fallback`.
    func window(_ request: [String: Any], _ fallback: Browser) throws -> Browser {
        guard let n = (request["window"] as? NSNumber)?.intValue else { return fallback }
        guard Browsers.all.indices.contains(n - 1) else {
            throw AgentRefusal(code: "no_window", message: "No window \(n)", hint: "get_state lists the windows.")
        }
        return Browsers.all[n - 1]
    }

    /// The window a tab is in.
    func owner(of tab: Tab) -> Browser? {
        Browsers.all.first { window in window.tabs.contains { $0 === tab } }
    }

    private func number(of browser: Browser) -> Int {
        (Browsers.all.firstIndex { $0 === browser } ?? 0) + 1
    }

    /// Asked in the window, as a sheet you answer with a click; the agent
    /// is told no, or the thing is done.
    private func confirm(_ title: String, _ detail: String, _ yes: String, _ session: AgentSession,
                         _ answer: @escaping ([String: Any]) -> Void, then: @escaping () -> Void) {
        let who = session.client
        Ask.sure(title, detail: "\(who) asked for this. " + detail, confirm: yes, otherwise: {
            answer(AgentRefusal(code: "declined", message: "The person said no",
                                hint: "Don't do it another way unless they ask you to.").said)
        }) { [weak self] in
            guard let self, live(session) else {
                return answer(AgentRefusal(code: "stopped", message: "Stopped in \(Store.name)").said)
            }
            then()
        }
    }

    func runFull(_ verb: String, _ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                 _ answer: @escaping ([String: Any]) -> Void) throws {
        switch verb {
        case "state": answer(state(request, session))
        case "commands": answer(commands(try window(request, Browsers.front ?? browser)))
        case "command": try command(request, session, browser, answer)
        case "tab": try tabAction(request, session, browser, answer)
        case "space": try spaceAction(request, session, browser, answer)
        case "group": try groupAction(request, session, browser, answer)
        case "window": try windowAction(request, session, browser, answer)
        case "bookmarks": try bookmarks(request, session, browser, answer)
        case "history": try history(request, session, browser, answer)
        case "downloads": try downloads(request, browser, answer)
        case "settings": try settings(request, browser, answer)
        case "script": try script(request, session, browser, answer)
        default: throw AgentRefusal(code: "no_verb", message: "\(Store.name) doesn't do “\(verb)” for an agent")
        }
    }

    // MARK: - the whole browser at a glance

    private func state(_ request: [String: Any], _ session: AgentSession) -> [String: Any] {
        let only = (request["window"] as? NSNumber)?.intValue
        let windows = Browsers.all.enumerated().compactMap { n, browser -> [String: Any]? in
            if let only, only != n + 1 { return nil }
            let shown = browser.tabs.filter { !$0.shy }
            var out: [String: Any] = [
                "window": n + 1,
                "front": browser === Browsers.front,
                "tabs": shown.map { AgentFull.describe($0, in: browser, session, control: self) },
                "groups": browser.tabGroups.map { group -> [String: Any] in
                    ["group": AgentFull.short(group.id), "name": group.name, "folded": group.collapsed,
                     "tabs": browser.tabs(in: group.id).filter { !$0.shy }.map { session.handle(for: $0) }]
                },
            ]
            if browser.prefs.usesSpaces {
                out["space"] = AgentFull.short(browser.spaceID)
                out["spaces"] = browser.spaces.map { space -> [String: Any] in
                    var row: [String: Any] = ["space": AgentFull.short(space.id), "name": space.name]
                    if space.id == browser.spaceID { row["current"] = true }
                    if let icon = space.icon { row["icon"] = icon }
                    return row
                }
            }
            if let split = browser.activeSplit {
                out["split"] = ["split": AgentFull.short(split.id), "pages": split.tabs.compactMap { id in
                    browser.tabs.first { $0.id == id }.map { session.handle(for: $0) }
                }] as [String: Any]
            }
            return out
        }
        return ["windows": windows, "hint": "Tabs of other spaces show once that space is current (space switch)."]
    }

    // MARK: - menu commands

    private func commands(_ browser: Browser) -> [String: Any] {
        ["commands": Command.all.map { command -> [String: Any] in
            var out: [String: Any] = ["command": command.id, "title": command.title, "menu": command.section.rawValue,
                                      "available": AddressCommand.menu(command.id).available(in: browser)]
            if let key = ShortcutStore.shared.key(for: command.id)?.display { out["key"] = key }
            return out
        }]
    }

    private func command(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                         _ answer: @escaping ([String: Any]) -> Void) throws {
        let id = request["command"] as? String ?? ""
        guard let command = Command.named(id) else {
            throw AgentRefusal(code: "no_command", message: "No command “\(id)”", hint: "list_commands has them all.")
        }
        var target = try window(request, Browsers.front ?? browser)
        // On a tab: that tab is put in front first, as you'd click it.
        if request["page"] != nil {
            let tab = try self.tab(request, session, browser, .drive)
            if let home = owner(of: tab) { target = home }
            if target.activeID != tab.id { target.select(tab) }
        }
        func run() {
            command.run(target)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                var out: [String: Any] = ["ran": id, "title": command.title, "window": number(of: target)]
                if let active = target.active, !active.shy { out["active"] = describe(active, session) }
                answer(out)
            }
        }
        let others = target.tabs.filter { $0.id != target.activeID && $0.pin == nil && !$0.shy }.count
        switch id {
        case "history.clear":
            confirm("Clear your history?", "Every page you have been to is forgotten, in every space.", "Clear History",
                    session, answer, then: run)
        case "tabs.closeOthers" where others > AgentFull.many:
            confirm("Close \(others) other tabs?", "Every tab but the one in front closes.", "Close Tabs", session, answer, then: run)
        case "file.closeWindow" where target.tabs.count > AgentFull.many:
            confirm("Close this window and its \(target.tabs.count) tabs?", "Its tabs close with it.", "Close Window",
                    session, answer, then: run)
        default:
            run()
        }
    }

    // MARK: - tabs

    private func tabAction(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                           _ answer: @escaping ([String: Any]) -> Void) throws {
        let tab = try self.tab(request, session, browser, .drive)
        guard let home = owner(of: tab) else { throw AgentRefusal(code: "stale_page", message: "That tab is gone") }
        let action = request["action"] as? String ?? ""
        func done(_ extra: [String: Any] = [:]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                var out: [String: Any] = ["did": action]
                if let now = owner(of: tab) {
                    out["tab"] = AgentFull.describe(tab, in: now, session, control: self)
                    out["window"] = number(of: now)
                }
                answer(out.merging(extra) { _, new in new })
            }
        }
        switch action {
        case "select":
            home.select(tab)
            if request["front"] as? Bool == true { home.window?.makeKeyAndOrderFront(nil) }
            done()
        case "close":
            let handle = session.handle(for: tab)
            home.close(tab)
            session.own.remove(tab.id)
            session.forget(handle)
            answer(["did": action, "closed": handle])
        case "reload": tab.reload(fromOrigin: request["hard"] as? Bool ?? false); done()
        case "stop": tab.stop(); done()
        case "pin":
            if tab.pin == nil { home.pin(tab, listed: request["listed"] as? Bool ?? false) }
            done()
        case "unpin":
            if tab.pin != nil { home.unpin(tab) }
            done()
        case "mute", "unmute":
            if tab.muted != (action == "mute") { tab.toggleMute() }
            done()
        case "rename":
            let name = (request["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            tab.name = name.isEmpty ? nil : String(name.prefix(200))
            home.writeSession(now: true)
            done()
        case "duplicate":
            if home.activeID != tab.id { home.select(tab) }
            home.duplicate()
            done(["new": home.active.map { session.handle(for: $0) } ?? ""])
        case "move":
            guard let index = (request["index"] as? NSNumber)?.intValue else {
                throw AgentRefusal(code: "bad_request", message: "move needs index, from 0")
            }
            home.move(tab, to: max(0, min(index, home.tabs.count - 1)))
            done()
        case "move_to_space":
            let space = try self.space(request, home)
            home.move(tab, toSpace: space.id)
            done(["space": space.name])
        case "move_to_window":
            if request["window"] as? String == "new" || request["new"] as? Bool == true {
                home.moveToWindow(tab, nil)
            } else {
                let target = try window(request, home)
                guard target !== home else { return done() }
                home.moveToWindow(tab, target)
            }
            done()
        case "group":
            if let name = request["new"] as? String {
                let made = home.addTabGroup(containing: tab)
                if !name.isEmpty { home.renameTabGroup(made, to: name) }
                home.editingGroupID = nil
                done(["group": AgentFull.short(made)])
            } else {
                let group = try self.group(request, home)
                home.move(tab, toGroup: group.id)
                done(["group": AgentFull.short(group.id)])
            }
        case "ungroup":
            home.move(tab, toGroup: nil)
            done()
        case "split":
            guard let otherHandle = request["with"] as? String else {
                throw AgentRefusal(code: "bad_request", message: "split needs with: another page handle")
            }
            let other = try self.tab(["page": otherHandle], session, browser, .drive)
            guard owner(of: other) === home else {
                throw AgentRefusal(code: "bad_request", message: "Both tabs must be in the same window", hint: "move_to_window first.")
            }
            guard home.canSplit(tab, with: other) else {
                throw AgentRefusal(code: "cant_split", message: "Those two can't be split together", hint: "Neither may be private, or in a split already full.")
            }
            home.pair(other, with: tab, onLeft: request["left"] as? Bool ?? false)
            done()
        case "unsplit":
            if home.split(for: tab) != nil { home.detachSplit(tab) }
            done()
        case "zoom":
            guard let level = (request["level"] as? NSNumber)?.doubleValue, (0.25...5).contains(level) else {
                throw AgentRefusal(code: "bad_request", message: "zoom needs level, 0.25 to 5 (1 is actual size)")
            }
            tab.magnify(to: CGFloat(level))
            done()
        default:
            throw AgentRefusal(code: "bad_action", message: "No tab action “\(action)”",
                               hint: "select, close, reload, stop, pin, unpin, mute, unmute, rename, duplicate, move, move_to_space, move_to_window, group, ungroup, split, unsplit, zoom")
        }
    }

    // MARK: - spaces

    private func space(_ request: [String: Any], _ browser: Browser) throws -> Space {
        guard browser.prefs.usesSpaces else {
            throw AgentRefusal(code: "no_spaces", message: "Spaces are off", hint: "settings set spaces true turns them on.")
        }
        let named = (request["space"] as? String ?? "").lowercased()
        guard let found = browser.spaces.first(where: { AgentFull.short($0.id) == named || $0.name.lowercased() == named })
            ?? browser.spaces.first(where: { $0.id.uuidString.lowercased().hasPrefix(named) && !named.isEmpty }) else {
            throw AgentRefusal(code: "no_space", message: "No space “\(named)”", hint: "get_state lists the spaces, by id and name.")
        }
        return found
    }

    private func spaceAction(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                             _ answer: @escaping ([String: Any]) -> Void) throws {
        let home = try window(request, Browsers.front ?? browser)
        let action = request["action"] as? String ?? ""
        func done(_ extra: [String: Any] = [:]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self else { return }
                var out = state(["window": number(of: home)], session)
                out["did"] = action
                answer(out.merging(extra) { _, new in new })
            }
        }
        switch action {
        case "new":
            guard home.prefs.usesSpaces else {
                throw AgentRefusal(code: "no_spaces", message: "Spaces are off", hint: "settings set spaces true turns them on.")
            }
            let name = (request["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            home.addSpace(named: name.isEmpty ? "Space \(home.spaces.count + 1)" : name, icon: request["icon"] as? String,
                          sharesSignIns: request["fresh"] as? Bool != true)
            done()
        case "switch":
            home.switchSpace(to: try space(request, home).id)
            done()
        case "rename":
            let space = try self.space(request, home)
            let name = (request["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw AgentRefusal(code: "bad_request", message: "rename needs a name") }
            home.renameSpace(space.id, to: name)
            done()
        case "icon":
            let space = try self.space(request, home)
            guard let icon = request["icon"] as? String, !icon.isEmpty else { throw AgentRefusal(code: "bad_request", message: "icon needs icon") }
            home.setSpaceIcon(space.id, to: icon)
            done()
        case "colour", "color":
            let space = try self.space(request, home)
            guard let colour = (request["colour"] as? NSNumber ?? request["color"] as? NSNumber)?.intValue,
                  Spaces.colours.indices.contains(colour) else {
                throw AgentRefusal(code: "bad_request", message: "colour needs a number from 0 to \(Spaces.colours.count - 1)")
            }
            home.setSpaceColour(space.id, to: colour)
            done()
        case "move":
            let space = try self.space(request, home)
            guard let index = (request["index"] as? NSNumber)?.intValue else { throw AgentRefusal(code: "bad_request", message: "move needs index, from 0") }
            home.moveSpace(space.id, to: max(0, min(index, home.spaces.count - 1)))
            done()
        case "delete":
            let space = try self.space(request, home)
            guard home.spaces.count > 1 else { throw AgentRefusal(code: "last_space", message: "The last space stays") }
            confirm("Delete the space “\(space.name)”?", "Its tabs and pins close with it.", "Delete Space", session, answer) {
                home.deleteSpace(space.id)
                done()
            }
        default:
            throw AgentRefusal(code: "bad_action", message: "No space action “\(action)”",
                               hint: "new, switch, rename, icon, colour, move, delete")
        }
    }

    // MARK: - groups

    private func group(_ request: [String: Any], _ browser: Browser) throws -> TabGroup {
        let named = (request["group"] as? String ?? "").lowercased()
        guard !named.isEmpty, let found = browser.tabGroups.first(where: { AgentFull.short($0.id) == named || $0.name.lowercased() == named }) else {
            throw AgentRefusal(code: "no_group", message: "No group “\(named)”", hint: "get_state lists the groups, by id and name.")
        }
        return found
    }

    private func groupAction(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                             _ answer: @escaping ([String: Any]) -> Void) throws {
        let home = try window(request, Browsers.front ?? browser)
        let group = try self.group(request, home)
        let action = request["action"] as? String ?? ""
        func done() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                var out = state(["window": number(of: home)], session)
                out["did"] = action
                answer(out)
            }
        }
        switch action {
        case "rename":
            let name = (request["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw AgentRefusal(code: "bad_request", message: "rename needs a name") }
            home.renameTabGroup(group.id, to: name)
            done()
        case "fold", "unfold":
            if group.collapsed != (action == "fold") { home.toggleTabGroup(group.id) }
            done()
        case "ungroup":
            for tab in home.tabs(in: group.id) { home.move(tab, toGroup: nil) }
            done()
        case "move_to_space":
            home.move(group: group.id, toSpace: try space(request, home).id)
            done()
        case "close":
            let count = home.tabs(in: group.id).count
            if count > AgentFull.many {
                confirm("Close the group “\(group.name)” and its \(count) tabs?", "Its tabs close with it.", "Close Group", session, answer) {
                    home.closeTabGroup(group.id)
                    done()
                }
            } else {
                home.closeTabGroup(group.id)
                done()
            }
        default:
            throw AgentRefusal(code: "bad_action", message: "No group action “\(action)”",
                               hint: "rename, fold, unfold, ungroup, move_to_space, close")
        }
    }

    // MARK: - windows

    private func windowAction(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                              _ answer: @escaping ([String: Any]) -> Void) throws {
        let action = request["action"] as? String ?? ""
        func done() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                var out = state([:], session)
                out["did"] = action
                answer(out)
            }
        }
        switch action {
        case "new":
            Browsers.newWindow()
            done()
        case "focus":
            let target = try window(request, browser)
            target.window?.makeKeyAndOrderFront(nil)
            if request["activate"] as? Bool == true { NSApp.activate() }
            done()
        case "close":
            let target = try window(request, browser)
            guard Browsers.all.count > 1 || request["last"] as? Bool == true else {
                throw AgentRefusal(code: "last_window", message: "That is the last window", hint: "Pass last: true to close it anyway.")
            }
            if target.tabs.count > AgentFull.many {
                confirm("Close this window and its \(target.tabs.count) tabs?", "Its tabs close with it.", "Close Window", session, answer) {
                    target.window?.close()
                    done()
                }
            } else {
                target.window?.close()
                done()
            }
        default:
            throw AgentRefusal(code: "bad_action", message: "No window action “\(action)”", hint: "new, focus, close")
        }
    }

    // MARK: - bookmarks

    private func bookmarks(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                           _ answer: @escaping ([String: Any]) -> Void) throws {
        let kept = browser.bookmarks
        let action = request["action"] as? String ?? "list"
        func flat(_ nodes: [Bookmark], _ path: [String]) -> [[String: Any]] {
            nodes.flatMap { node -> [[String: Any]] in
                if node.isFolder { return flat(node.children ?? [], path + [node.title]) }
                return [["bookmark": AgentFull.short(node.id), "title": node.label, "url": AgentRules.url(node.url ?? ""),
                         "folder": path.joined(separator: " › ")]]
            }
        }
        func find(_ id: String) -> Bookmark? {
            func walk(_ nodes: [Bookmark]) -> Bookmark? {
                for node in nodes {
                    if AgentFull.short(node.id) == id.lowercased() { return node }
                    if let inside = walk(node.children ?? []) { return inside }
                }
                return nil
            }
            return walk(kept.roots)
        }
        switch action {
        case "list", "search":
            let needle = (request["query"] as? String ?? "").lowercased()
            let all = flat(kept.roots, [])
            let found = needle.isEmpty ? all : all.filter {
                ($0["title"] as? String ?? "").lowercased().contains(needle) || ($0["url"] as? String ?? "").lowercased().contains(needle)
            }
            let most = (request["limit"] as? NSNumber)?.intValue ?? 200
            answer(["bookmarks": Array(found.prefix(max(1, most))), "count": found.count])
        case "add":
            guard let url = (request["url"] as? String).flatMap(Address.url(from:)) else {
                throw AgentRefusal(code: "bad_request", message: "add needs a url")
            }
            guard let made = kept.add(url, title: request["title"] as? String ?? url.host() ?? url.absoluteString) else {
                return answer(["added": false, "already": true])
            }
            answer(["added": AgentFull.short(made.id)])
        case "remove":
            guard let node = find(request["bookmark"] as? String ?? "") else {
                throw AgentRefusal(code: "no_bookmark", message: "No such bookmark", hint: "bookmarks list gives their ids.")
            }
            if node.isFolder, (node.children ?? []).count > AgentFull.many {
                confirm("Delete the folder “\(node.title)” and what's in it?", "Its \((node.children ?? []).count) bookmarks go with it.",
                        "Delete", session, answer) {
                    kept.remove(node.id)
                    answer(["removed": AgentFull.short(node.id)])
                }
            } else {
                kept.remove(node.id)
                answer(["removed": AgentFull.short(node.id)])
            }
        case "open":
            guard let node = find(request["bookmark"] as? String ?? ""), let url = node.address else {
                throw AgentRefusal(code: "no_bookmark", message: "No such bookmark", hint: "bookmarks list gives their ids.")
            }
            let tab = browser.open(url, foreground: request["foreground"] as? Bool ?? true, atEnd: true)
            session.own.insert(tab.id)
            settle(tab, session, timeout: request["timeout"] as? Double ?? 20, answer)
        default:
            throw AgentRefusal(code: "bad_action", message: "No bookmarks action “\(action)”", hint: "list, search, add, remove, open")
        }
    }

    // MARK: - history

    private func history(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                         _ answer: @escaping ([String: Any]) -> Void) throws {
        let history = browser.history
        let action = request["action"] as? String ?? "search"
        let most = max(1, min((request["limit"] as? NSNumber)?.intValue ?? 50, 500))
        func row(_ trace: History.Trace) -> [String: Any] {
            ["url": AgentRules.url(trace.url.absoluteString), "title": trace.title,
             "last": ISO8601DateFormatter().string(from: trace.last), "visits": trace.count]
        }
        switch action {
        case "search", "list":
            let found = history.everything(matching: request["query"] as? String ?? "")
                .sorted { $0.last > $1.last }
            answer(["history": found.prefix(most).map(row), "count": found.count])
        case "recent":
            answer(["history": history.recent().prefix(most).map(row)])
        case "remove":
            guard let text = request["url"] as? String,
                  let trace = history.everything(matching: "").first(where: { $0.url.absoluteString == text || $0.key == text }) else {
                throw AgentRefusal(code: "no_entry", message: "No history entry for that url", hint: "history search gives them.")
            }
            history.forget(trace.key)
            answer(["removed": AgentRules.url(trace.url.absoluteString)])
        default:
            throw AgentRefusal(code: "bad_action", message: "No history action “\(action)”", hint: "search, recent, remove")
        }
    }

    // MARK: - downloads

    private func downloads(_ request: [String: Any], _ browser: Browser, _ answer: @escaping ([String: Any]) -> Void) throws {
        let loot = Shared.loot
        let action = request["action"] as? String ?? "list"
        func kept(_ id: String) throws -> Keep {
            guard let keep = loot.kept.first(where: { $0.path == id || $0.name == id }) else {
                throw AgentRefusal(code: "no_download", message: "No download “\(id)”", hint: "downloads list gives them.")
            }
            return keep
        }
        switch action {
        case "list":
            let running = browser.fetches.entries.map { entry -> [String: Any] in
                ["name": entry.name, "state": "\(entry.state)", "done": entry.completedBytes, "of": entry.totalBytes]
            }
            answer(["under_way": running, "downloads": loot.kept.prefix(100).map { keep -> [String: Any] in
                var out: [String: Any] = ["name": keep.name, "path": keep.path, "date": ISO8601DateFormatter().string(from: keep.date)]
                if let from = keep.address { out["from"] = AgentRules.url(from) }
                return out
            }])
        case "reveal":
            loot.reveal(try kept(request["download"] as? String ?? ""))
            answer(["revealed": true])
        case "forget":
            let keep = try kept(request["download"] as? String ?? "")
            loot.forget(keep)
            answer(["forgotten": keep.name, "note": "Taken off the list; the file stays where it is."])
        default:
            throw AgentRefusal(code: "bad_action", message: "No downloads action “\(action)”",
                               hint: "list, reveal, forget. A download starts from a page: click its link.")
        }
    }

    // MARK: - settings

    private func settings(_ request: [String: Any], _ browser: Browser, _ answer: @escaping ([String: Any]) -> Void) throws {
        let prefs = browser.prefs
        let action = request["action"] as? String ?? "list"
        switch action {
        case "list":
            let needle = (request["query"] as? String ?? "").lowercased()
            let rows = AgentSettings.all.map { $0.describe(prefs) }.filter { row in
                needle.isEmpty || [row["key"], row["title"], row["detail"]].compactMap { $0 as? String }
                    .contains { $0.lowercased().contains(needle) }
            }
            answer(["settings": rows])
        case "get":
            let key = request["key"] as? String ?? ""
            guard let setting = AgentSettings.named(key) else { throw Self.noSetting(key) }
            answer(setting.describe(prefs))
        case "set":
            let key = request["key"] as? String ?? ""
            guard let setting = AgentSettings.named(key) else { throw Self.noSetting(key) }
            guard let value = request["value"], setting.set(prefs, value) else {
                throw AgentRefusal(code: "bad_value", message: "Not a value “\(key)” takes",
                                   hint: setting.choices.isEmpty ? "It takes a \(setting.kind)." : "One of: \(setting.choices.joined(separator: ", ")).")
            }
            answer(setting.describe(prefs))
        case "open":
            let target = try window(request, Browsers.front ?? browser)
            if let name = request["page"] as? String {
                guard let page = SettingsPanel.Page.named(name) else {
                    throw AgentRefusal(code: "bad_request", message: "No Settings page “\(name)”",
                                       hint: SettingsPanel.Page.allCases.map(\.rawValue).joined(separator: ", "))
                }
                target.settingsPage = page
            }
            target.tuning = true
            answer(["opened": target.settingsPage.rawValue])
        default:
            throw AgentRefusal(code: "bad_action", message: "No settings action “\(action)”", hint: "list, get, set, open")
        }
    }

    private static func noSetting(_ key: String) -> AgentRefusal {
        AgentRefusal(code: "no_setting", message: "No setting “\(key)” an agent can change",
                     hint: "settings list gives the keys. The agents' own switches are the person's alone.")
    }

    // MARK: - scripts of its own

    /// The agent's own scripts: in a world of their own, apart from the
    /// page's and from Quo's, with the guard (PageScripts.scriptGuard) run
    /// there first. The body of an async function: `return` what to hand back.
    static let scriptWorld = WKContentWorld.world(name: "\(Store.name) agent")

    private func script(_ request: [String: Any], _ session: AgentSession, _ browser: Browser,
                        _ answer: @escaping ([String: Any]) -> Void) throws {
        let tab = try self.tab(request, session, browser, .drive)
        let body = request["script"] as? String ?? ""
        guard !body.isEmpty, body.count <= 100_000 else {
            throw AgentRefusal(code: "bad_request", message: "script needs a script, at most 100,000 characters")
        }
        // Through `page`, so a sleeping tab is woken and an unshown one laid out.
        page(tab, session, "JSON.stringify({ok: true})") { [weak self] result in
            guard let self else { return }
            if case .failure(let refusal) = result { return answer(refusal.said) }
            guard live(session) else { return answer(AgentRefusal(code: "stopped", message: "Stopped in \(Store.name)").said) }
            let web = tab.web
            web.evaluateJavaScript(PageScripts.scriptGuard, in: nil, in: AgentControl.scriptWorld) { _ in
                web.callAsyncJavaScript(body, arguments: [:], in: nil, in: AgentControl.scriptWorld) { result in
                    switch result {
                    case .failure(let error):
                        let said = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
                        answer(AgentRefusal(code: "script", message: AgentRules.scrubbed(said)).said)
                    case .success(let value):
                        answer(["page": session.handle(for: tab), "result": Self.plain(value)])
                    }
                }
            }
        }
    }

    /// What a script handed back, as JSON can carry it.
    nonisolated static func plain(_ value: Any?) -> Any {
        guard let value, !(value is NSNull) else { return NSNull() }
        if value is String || value is NSNumber { return value }
        if let list = value as? [Any] { return list.map { plain($0) } }
        if let map = value as? [String: Any] { return map.mapValues { plain($0) } }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        return String(describing: value)
    }
}
