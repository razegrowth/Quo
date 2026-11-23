import Foundation

// Settings, for an agent with full control (AgentFull's `settings` verb):
// every switch, choice, number and text Preferences keeps under one
// defaults key, read and set through Preferences itself, so what a switch
// does when you flip it in Settings happens when an agent flips it too.
//
// The table is what Prefs.swift declares, written out once by a script (a
// setting whose didSet stores it under one key, as its own value, its
// rawValue, or a Double), and kept by hand since: a setting added to
// Preferences is added here too. Left out on purpose: the bench's switch,
// the agents' own two, and anything that isn't one of those shapes.

@MainActor
struct AgentSetting {
    let key: String
    let kind: String
    let choices: [String]
    let get: @MainActor (Preferences) -> Any
    let set: @MainActor (Preferences, Any) -> Bool

    static func bool(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, Bool>) -> AgentSetting {
        AgentSetting(key: key, kind: "bool", choices: [], get: { $0[keyPath: path] }, set: { prefs, value in
            guard let on = value as? Bool else { return false }
            if prefs[keyPath: path] != on { prefs[keyPath: path] = on }
            return true
        })
    }

    static func number<T: BinaryFloatingPoint>(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, T>) -> AgentSetting {
        AgentSetting(key: key, kind: "number", choices: [], get: { Double($0[keyPath: path]) }, set: { prefs, value in
            guard let number = (value as? NSNumber)?.doubleValue, number.isFinite else { return false }
            prefs[keyPath: path] = T(number)
            return true
        })
    }

    static func text(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, String>) -> AgentSetting {
        AgentSetting(key: key, kind: "text", choices: [], get: { $0[keyPath: path] }, set: { prefs, value in
            guard let text = value as? String else { return false }
            prefs[keyPath: path] = text
            return true
        })
    }

    static func choice<T: RawRepresentable & Equatable>(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, T>) -> AgentSetting
        where T.RawValue == String {
        let all = (T.self as? any CaseIterable.Type).map { type in
            (type.allCases as any Collection).compactMap { ($0 as? T)?.rawValue }
        } ?? []
        return AgentSetting(key: key, kind: "choice", choices: all, get: { $0[keyPath: path].rawValue }, set: { prefs, value in
            guard let raw = value as? String, let choice = T(rawValue: raw) else { return false }
            if prefs[keyPath: path] != choice { prefs[keyPath: path] = choice }
            return true
        })
    }

    /// A choice kept as a number (how long before a tab closes by itself).
    static func choice<T: RawRepresentable & Equatable>(_ key: String, _ path: ReferenceWritableKeyPath<Preferences, T>) -> AgentSetting
        where T.RawValue == Int {
        let all = (T.self as? any CaseIterable.Type).map { type in
            (type.allCases as any Collection).compactMap { ($0 as? T).map { String($0.rawValue) } }
        } ?? []
        return AgentSetting(key: key, kind: "choice", choices: all, get: { $0[keyPath: path].rawValue }, set: { prefs, value in
            let raw = (value as? NSNumber)?.intValue ?? (value as? String).flatMap { Int($0) }
            guard let raw, let choice = T(rawValue: raw) else { return false }
            if prefs[keyPath: path] != choice { prefs[keyPath: path] = choice }
            return true
        })
    }

    /// What Settings calls it, from its row (SettingsIndex), if it has one.
    var row: SettingsItem? { SettingsIndex.items.first { $0.keys.contains(key) } }

    func describe(_ prefs: Preferences) -> [String: Any] {
        var out: [String: Any] = ["key": key, "kind": kind, "value": get(prefs)]
        if !choices.isEmpty { out["choices"] = choices }
        if let row {
            out["title"] = row.title
            out["detail"] = row.detail
            out["page"] = row.page.rawValue
        }
        return out
    }
}

@MainActor
enum AgentSettings {
    static func named(_ key: String) -> AgentSetting? { all.first { $0.key == key } }

    static let all: [AgentSetting] = [
        .bool("toolbar.left", \.navigationLeft),
        .bool("sidebar.addressBar", \.addressBar),
        .bool("tabs.compact", \.compactStrip),
        .choice("look", \.look),
        .bool("sidebar", \.sidebar),
        .number("sidepanel.width", \.sidePanelWidth),
        .choice("sidebar.position", \.sidePosition),
        .bool("sidebar.hides", \.sideHides),
        .bool(Motion.slidesKey, \.slidesColumn),
        .bool("sidebar.roomy", \.roomyTabs),
        .bool("sidebar.icons", \.sideIcons),
        .bool("sidebar.foldIcons", \.foldsToIcons),
        .bool("sidebar.player", \.showsPlayer),
        .number("sidebar.width", \.sideWidth),
        .bool("layout.cards", \.cards),
        .bool("layout.cardsFullScreen", \.cardsInFullScreen),
        .choice("glyph", \.glyph),
        .choice("search.engine", \.engine),
        .text("search.custom", \.customEngine),
        .text("search.shiftCustom", \.shiftCustom),
        .bool("tabs.give", \.tabsGive),
        .bool("tabs.popupWindows", \.popupWindows),
        .bool("tabs.sleep", \.sleepsTabs),
        .choice("tabs.close.after", \.tabLife),
        .choice(SleepPace.key, \.sleepPace),
        .bool("notifications.ask", \.siteNotifications),
        .bool("tabs.lazy", \.lazyTabs),
        .bool("tabs.newAfterLast", \.newTabAfterLast),
        .bool("tabs.closeGoesBack", \.closeGoesBack),
        .bool("tabs.undoReopens", \.undoReopensTab),
        .bool("tabs.switcherBehindFirst", \.switcherBehindFirst),
        .bool("tabs.switcherLeavesOutPins", \.switcherLeavesOutPins),
        .choice("tabs.newPlace", \.newTabPlace),
        .bool("tabs.frontBeside", \.frontLinksBeside),
        .bool("tabs.mirror", \.mirrorsTabs),
        .bool(Preferences.freshKey, \.startsFresh),
        .bool(Preferences.confirmQuitKey, \.confirmsQuit),
        .bool("search.suggest", \.engineSuggests),
        .bool("tabs.shortcuts", \.showsTabShortcuts),
        .bool("tabs.reading", \.showsReading),
        .bool("tabs.address", \.showsAddress),
        .bool("shield", \.shielded),
        .bool("sites.keep", \.keepsSignIns),
        .bool("privacy.gpc", \.sendsPrivacySignal),
        .bool("privacy.clickIDs", \.removesClickIDs),
        .bool(TabTitles.key, \.shortTitles),
        .bool(LinkPreview.summaryKey, \.summarizesLinks),
        .bool(LinkPreview.key, \.previewsLinks),
        .bool(Telemetry.key, \.sharesUsage),
        .bool("passkeys", \.passkeys),
        .bool("downloads.ask", \.asksWhereToSave),
        .bool("passwords.save", \.savesPasswords),
        .bool("passwords.fill", \.fillsPasswords),
        .bool("sync.history", \.syncsHistory),
        .bool("cards.fill", \.fillsCards),
        .bool("contacts.fill", \.fillsContacts),
        .bool("passwords.apple", \.applePasswords),
        .bool("welcomed", \.welcomed),
        .bool("autocorrect", \.autocorrect),
        .number("pageZoom", \.pageZoom),
        .bool("pages.dusk", \.darkensPages),
        .bool("pages.capture", \.capturesPages),
        .bool("sites.styles", \.sitesStyles),
        .bool("inspector.chrome", \.inspectorChrome),
        .bool("inspector.dark", \.inspectorDark),
        .bool("autoscroll", \.autoScroll),
        .bool("scroll.smoothWheel", \.smoothWheel),
        .bool("pages.bounce", \.bounces),
        .choice("pages.120.mode", \.fastPages),
        .bool(Motion.lightKey, \.lightMotion),
        .bool(Motion.instantKey, \.instantMotion),
        .choice("links.peekClick", \.peekClick),
        .choice("pins.links", \.pinLinks),
        .bool("links.peek", \.peeksLinks),
        .bool("links.peek.stays", \.peekStays),
        .bool("links.optionSplit", \.optionClickSplits),
        .bool("pins.peek", \.pinsPeek),
        .bool("reader.twins", \.readsTwins),
        .bool("reader.follows", \.readerFollowsLook),
        .bool(Preferences.littleKey, \.littleLinks),
        .choice("mail.webmail", \.webmail),
        .bool("links.little.tabs", \.littleFindsTabs),
        .bool(SpaceRoutes.key, \.sendsLinksToSpaces),
        .bool("downloads.button", \.alwaysShowsDownloads),
        .choice("downloads.open", \.downloadsOpening),
        .bool("bookmarks.bar", \.bookmarksBar),
        .bool("links.show", \.showsLinks),
        .bool("swipe.history", \.holdsHistory),
        .bool("float.flicks", \.floatFlicks),
        .bool("float.minimize", \.floatMinimizes),
        .bool("float.away", \.floatsAway),
        .bool(Preferences.waitsKey, \.waitsForPlay),
        .text("translate.target", \.translateTarget),
        .bool("float.leave", \.floatsOnLeave),
        .text("panel.site", \.panelSite),
        .choice("float.style", \.floatStyle),
        .bool("fullscreen.escapeTwice", \.escapeTwice),
        .bool("fullscreen.keepsWindow", \.keepsWindow),
        .bool(Updater.installKey, \.installsUpdates),
        .bool("spaces", \.usesSpaces),
        .bool(Preferences.spacesOnCommandKey, \.spacesOnCommand),
        .bool("profiles.oneWindow", \.profilesInOneWindow),
        .bool("pins.list", \.listsPins),
        .bool("pins.folders", \.pinFolders),
        .bool("pins.home", \.pinsGoHome),
        .bool("pins.commandNewTab", \.pinCommandOpensTab),
        .bool("ai", \.ai),
        .bool("commandbar", \.commandBar),
        .bool("newtab.floating", \.floatingNewTab),
        .bool("launcher.on", \.launcher),
        .bool("launcher.little", \.launcherLittle),
        .bool("newtab.recent", \.recentInNewTab),
        .bool(Preferences.writingToolsKey, \.writingTools),
        .bool(Preferences.meaningKey, \.meaningSearch),
        .bool(GroupNames.key, \.namesGroups),
        .bool(DownloadNames.key, \.namesDownloads),
    ]
}
