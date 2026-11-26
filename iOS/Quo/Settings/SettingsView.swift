import SwiftUI
import QuickLook
import WebKit

/// App settings: what Quo does everywhere.
struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var sync = MacSync.shared
    @ObservedObject private var tabs = Tabs.shared
    @Environment(\.dismiss) private var dismiss
    @State private var clearing = false
    @State private var onboarding = false
    @State private var homeScreen = false
    @State private var showDownloads = false
    @State private var showArchive = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        Button { showDownloads = true } label: { pill("folder", "Downloads") }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("settings.downloads")
                        Button { showArchive = true } label: { pill("archivebox", "Archive") }
                            .buttonStyle(PressStyle())
                            .accessibilityIdentifier("settings.archive")
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink { GlobalSiteSettingsView() } label: { label("globe", "Global site settings") }
                }

                Section {
                    Button { open(UIApplication.openSettingsURLString) } label: {
                        HStack { label("checkmark.seal", "Set Quo as default browser"); Spacer(); chevron }
                    }
                    NavigationLink { AppIconView() } label: { label("app.badge.checkmark", "Change app icon") }
                    Button { homeScreen = true } label: { label("plus.square.on.square", "Add to Home Screen") }
                }

                Section {
                    NavigationLink { EngineView() } label: {
                        HStack { label("magnifyingglass", "Search engine"); Spacer(); note(settings.engine.name(custom: settings.customTemplate)) }
                    }
                    NavigationLink { LanguagesView() } label: {
                        HStack { label("character.bubble", "Languages"); Spacer(); note(Locale.current.localizedString(forLanguageCode: settings.translateTo) ?? "") }
                    }
                }

                Section {
                    Toggle(isOn: $settings.autoKeyboard) { label("keyboard", "Auto-open keyboard") }.tint(Q.on)
                    Toggle(isOn: $settings.playsInBackground) { label("play.circle", "Keep playing when you leave Quo") }.tint(Q.on)
                    if IncognitoLock.available {
                        Toggle(isOn: $settings.lockIncognito) { label("lock", "Lock Incognito tabs with \(IncognitoLock.method)") }.tint(Q.on)
                            .onChange(of: settings.lockIncognito) { _, on in
                                // Switched off while locked: only once Face ID says it's you.
                                guard !on, IncognitoLock.shared.locked else { return }
                                Task { if !(await IncognitoLock.shared.unlock()) { settings.lockIncognito = true } }
                            }
                    }
                    if OnDevice.available {
                        Toggle(isOn: $settings.shortTitles) { label("apple.intelligence", "Shorter tab names") }.tint(Q.on)
                        Toggle(isOn: $settings.linkSummaries) { label("text.bubble", "Summaries in link previews") }.tint(Q.on)
                    }
                    Picker(selection: $settings.archiveAfter) {
                        ForEach(ArchiveAfter.allCases) { Text($0.title).tag($0) }
                    } label: { label("archivebox", "Archive inactive tabs") }
                    Picker(selection: $settings.appLinks) {
                        ForEach(AppLinks.allCases) { Text($0.title).tag($0) }
                    } label: { label("arrow.up.forward.app", "Open app links in") }
                    Button { clearing = true } label: { label("eraser", "Clear browsing data\u{2026}") }
                    ShareLink(item: tabs.exported.isEmpty ? "No tabs open" : tabs.exported, subject: Text("Open tabs")) {
                        VStack(alignment: .leading, spacing: 2) {
                            label("square.and.arrow.up", "Export data")
                            Text("Share your open tabs\u{2019} addresses").font(Q.footnote).foregroundStyle(Q.muted).padding(.leading, 40)
                        }
                    }
                }

                Section {
                    NavigationLink { SyncView() } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            label("arrow.triangle.2.circlepath", "Sync with Quo on your Mac")
                            Text(sync.summary).font(Q.footnote).foregroundStyle(Q.muted).padding(.leading, 40).lineLimit(1)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $settings.sharesUsage) { label("chart.bar", "Help count how many people use Quo") }.tint(Q.on)
                } footer: {
                    Text("Once a day: the version, your iPhone\u{2019}s model and iOS. Never what you browse.")
                }

                Section {
                    Button { onboarding = true } label: { label("hand.wave", "Show onboarding") }
                    NavigationLink { PrivacyView() } label: { label("hand.raised", "Privacy policy") }
                    NavigationLink { LicencesView() } label: { label("doc.text", "Open source licences") }
                } footer: {
                    Text("Quo \(Store.version)")
                        .font(Q.footnote)
                        .foregroundStyle(Q.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                }
            }
            .foregroundStyle(Q.ink)
            .tint(Q.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
            .confirmationDialog("Clear browsing data", isPresented: $clearing, titleVisibility: .visible) {
                ForEach(Cleaner.Span.allCases) { span in
                    Button(span.button, role: span == .everything ? .destructive : nil) {
                        Cleaner.clear(span)
                        Haptics.done()
                        Browser.shared.say(span.done)
                    }
                    .accessibilityIdentifier("clear.\(span.rawValue)")
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("History, closed tabs and site data from then: those sites sign you out. Everything also closes your tabs.")
            }
            .navigationDestination(isPresented: $showDownloads) { DownloadsView() }
            .navigationDestination(isPresented: $showArchive) { ArchiveView() }
            .fullScreenCover(isPresented: $onboarding) { OnboardingView { onboarding = false } }
            .sheet(isPresented: $homeScreen) { HomeScreenGuide().presentationDetents([.medium]) }
        }
        .presentationCornerRadius(28)
    }

    private func pill(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
            Text(title).font(Q.bodyEmphasis)
        }
        .foregroundStyle(Q.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }

    private func label(_ symbol: String, _ title: String) -> some View {
        Label {
            Text(title).foregroundStyle(Q.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Q.muted).fontWeight(.medium)
        }
    }

    private func note(_ text: String) -> some View { Text(text).foregroundStyle(Q.muted) }
    private var chevron: some View {
        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Q.faint)
    }

    private func open(_ text: String) {
        if let url = URL(string: text) { UIApplication.shared.open(url) }
    }
}

enum Cleaner {
    /// How far back Clear Browsing Data goes.
    enum Span: String, CaseIterable, Identifiable {
        case hour, day, everything
        var id: String { rawValue }
        var button: String {
            switch self {
            case .hour: return "Clear the Last Hour"
            case .day: return "Clear the Last Day"
            case .everything: return "Clear Everything"
            }
        }
        var done: String {
            switch self {
            case .hour: return "Cleared the last hour"
            case .day: return "Cleared the last day"
            case .everything: return "Cleared everything"
            }
        }
        func since(_ now: Date = Date()) -> Date {
            switch self {
            case .hour: return now.addingTimeInterval(-3600)
            case .day: return now.addingTimeInterval(-86_400)
            case .everything: return .distantPast
            }
        }
    }

    /// History, recently closed tabs, cookies and site data from the span;
    /// for everything, the tabs, the archive and sites' icons too.
    @MainActor static func clear(_ span: Span) {
        let since = span.since()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: since) {}
        HTTPCookieStorage.shared.removeCookies(since: since)
        History.shared.clear(since: since)
        Tabs.shared.forgetClosed(since: since)
        guard span == .everything else { return }
        Favicons.shared.forget()
        Tabs.shared.closeAll(incognito: false, remember: false)
        Tabs.shared.closeAll(incognito: true, remember: false)
        Tabs.shared.clearArchive()
    }
}

// MARK: - sync

extension MacSync {
    var summary: String {
        if !on { return "Off" }
        if !available { return "Not in this build" }
        if let problem { return problem }
        if running && lastSynced == nil { return "Syncing\u{2026}" }
        guard let lastSynced else { return "Not yet synced" }
        let with = macs.isEmpty ? "no Mac yet" : "with " + SyncTabs.once(macs).joined(separator: ", ")
        return "\(with) \u{00B7} \(SyncTabs.synced(lastSynced))"
    }
}

struct SyncView: View {
    @ObservedObject private var sync = MacSync.shared

    var body: some View {
        List {
            Section {
                Toggle("Sync with Quo on your Mac", isOn: $sync.on).tint(Q.on)
            } footer: {
                Text("Your Mac\u{2019}s spaces, pins and bookmarks, through your own iCloud. End to end encrypted with a key in your iCloud Keychain: nobody else can read them, Apple and us included. There\u{2019}s no account to make.")
            }
            if sync.on {
                Section("Status") {
                    LabeledContent("Through", value: sync.way)
                    LabeledContent("Macs", value: sync.macs.isEmpty ? "None yet" : sync.macs.joined(separator: ", "))
                    LabeledContent("Spaces", value: "\(sync.spaces.count)")
                    if let problem = sync.problem { LabeledContent("Last try", value: problem) }
                    if let last = sync.lastSynced {
                        LabeledContent("Last synced", value: last.formatted(date: .omitted, time: .shortened))
                    }
                    Button {
                        sync.pass()
                    } label: {
                        HStack { Text("Sync Now"); Spacer(); if sync.running { ProgressView() } }
                    }
                    .disabled(sync.running || !sync.available)
                }
                Section {
                    Toggle("Sync history", isOn: $sync.syncsHistory).tint(Q.on)
                        .accessibilityIdentifier("sync.history")
                } footer: {
                    Text("The pages you\u{2019}ve visited, both ways, so they come up as you type on either. What you clear here is cleared there too. Never Incognito.")
                }
                Section {
                    Text("Comes from your Mac: spaces, their pins, your bookmarks, the search engine you use there, its open tabs\(sync.syncsHistory ? " and its history" : "").")
                        .font(Q.footnote).foregroundStyle(Q.muted)
                    Text("Goes to your Mac: what you pin here, your open tabs\(sync.syncsHistory ? " and your history" : ""). Never an Incognito tab, and never passwords.")
                        .font(Q.footnote).foregroundStyle(Q.muted)
                } header: { Text("What syncs") }
                Section {
                    Text("In Quo on your Mac, choose Settings \u{203A} Sync \u{203A} iCloud. Both need the same Apple Account.")
                        .font(Q.footnote)
                        .foregroundStyle(Q.muted)
                } header: { Text("On your Mac") }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - smaller pages

struct GlobalSiteSettingsView: View {
    @ObservedObject private var sites = Sites.shared
    @State private var resetting = false

    var body: some View {
        List {
            Section {
                toggle("hand.raised", "Block ads", \.blockAds)
                toggle("checklist.unchecked", "Block cookie banners", \.blockCookieBanners)
                toggle("eye.slash", "Block trackers", \.blockTrackers)
            } footer: {
                Text("Every site starts with these. Ads and trackers are blocked with EasyList and EasyPrivacy, cookie banners with Fanboy\u{2019}s Cookie Monster, refreshed daily.")
            }
            Section {
                toggle("rectangle.bottomhalf.inset.filled", "Collapse bottom bar", \.collapseBar)
                Picker(selection: Binding(get: { sites.global.swipe }, set: { var g = sites.global; g.swipe = $0; sites.setGlobal(g) })) {
                    ForEach(SwipeNav.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Swipe to navigate") } icon: { Image(systemName: "hand.draw").foregroundStyle(Q.muted) }
                }
            }
            if !sites.bySite.isEmpty {
                Section {
                    ForEach(sites.bySite.keys.sorted(), id: \.self) { host in
                        HStack(spacing: 12) {
                            SiteMark(host: host, size: 20)
                            Text(host)
                        }
                    }
                    Button("Reset Every Site", role: .destructive) { resetting = true }
                } header: { Text("Sites with their own settings") }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Global site settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Every site goes back to these settings.", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset Every Site", role: .destructive) { sites.forgetAll(); Blocker.shared.retune() }
        }
    }

    private func toggle(_ symbol: String, _ title: String, _ path: WritableKeyPath<SiteSettings, Bool>) -> some View {
        Toggle(isOn: Binding(get: { sites.global[keyPath: path] }, set: {
            var g = sites.global
            g[keyPath: path] = $0
            sites.setGlobal(g)
            Blocker.shared.retune()
        })) {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(Q.muted) }
        }
        .tint(Q.on)
    }
}

struct EngineView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                Button { settings.engineChoice = nil } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Same as my Mac").foregroundStyle(Q.ink)
                            Text(settings.macEngine.map { $0.name(custom: settings.customTemplate) } ?? "Google until your Mac says otherwise")
                                .font(Q.footnote).foregroundStyle(Q.muted)
                        }
                        Spacer()
                        if settings.engineChoice == nil { Image(systemName: "checkmark").foregroundStyle(Q.ink) }
                    }
                }
            }
            Section {
                ForEach(Engine.allCases.filter { $0 != .custom || !settings.customTemplate.isEmpty }) { engine in
                    Button { settings.engineChoice = engine } label: {
                        HStack {
                            Text(engine.name(custom: settings.customTemplate)).foregroundStyle(Q.ink)
                            Spacer()
                            if settings.engineChoice == engine { Image(systemName: "checkmark").foregroundStyle(Q.ink) }
                        }
                    }
                }
            }
            Section {
                Picker("Questions go to", selection: $settings.answers) {
                    Text("Search engine").tag(Engine?.none)
                    Text("Perplexity").tag(Engine?.some(.perplexity))
                    Text("ChatGPT").tag(Engine?.some(.chatgpt))
                }
            } footer: {
                Text("Something you ask, like \u{201C}how long do I boil an egg?\u{201D}, goes there for an answer. Anything else is a search. A site\u{2019}s name on its own, like github, goes to the site.")
            }
            Section {
                Toggle("Suggestions as you type", isOn: $settings.engineSuggests).tint(Q.on)
            } footer: {
                Text("What you type goes to the search engine to suggest searches. Never in Incognito.")
            }
        }
        .tint(Q.ink)
        .navigationTitle("Search engine")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LanguagesView: View {
    @ObservedObject private var settings = AppSettings.shared
    private let codes = ["en", "de", "fr", "es", "it", "pt", "nl", "sv", "da", "nb", "pl", "tr", "ru", "uk", "ar", "hi", "id", "th", "vi", "ja", "ko", "zh"]

    var body: some View {
        List {
            Section {
                ForEach(codes, id: \.self) { code in
                    Button { settings.translateTo = code } label: {
                        HStack {
                            Text(Locale.current.localizedString(forLanguageCode: code) ?? code).foregroundStyle(Q.ink)
                            Spacer()
                            if settings.translateTo == code { Image(systemName: "checkmark").foregroundStyle(Q.ink) }
                        }
                    }
                }
            } header: {
                Text("Translate pages into")
            } footer: {
                Text("Pages are translated on this iPhone by Apple\u{2019}s Translation. A language you haven\u{2019}t used before is downloaded the first time.")
            }
            Section {
                Button("Languages in iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Languages")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppIconView: View {
    @State private var current = UIApplication.shared.alternateIconName

    var body: some View {
        List {
            choice(nil, "Light", "White tile, ink Q")
            choice("AppIconInk", "Ink", "Ink tile, white Q")
        }
        .tint(Q.ink)
        .navigationTitle("App icon")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice(_ name: String?, _ title: String, _ note: String) -> some View {
        Button {
            UIApplication.shared.setAlternateIconName(name) { _ in
                DispatchQueue.main.async { current = UIApplication.shared.alternateIconName }
            }
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(name == nil ? Color(white: 0.98) : Color(white: 0.09))
                    .overlay(Image("QMark").resizable().aspectRatio(contentMode: .fit).padding(12)
                        .foregroundStyle(name == nil ? Color(white: 0.09) : Color(white: 0.98)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Q.hairline))
                    .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Q.ink)
                    Text(note).font(Q.footnote).foregroundStyle(Q.muted)
                }
                Spacer()
                if current == name { Image(systemName: "checkmark").foregroundStyle(Q.ink) }
            }
        }
    }
}

struct HomeScreenGuide: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quo on your Home Screen").font(Q.title).foregroundStyle(Q.ink)
            step(1, "Swipe left past your last Home Screen page to the App Library.")
            step(2, "Find Quo, then touch and hold its icon.")
            step(3, "Drag it to where you want it, or choose Add to Home Screen.")
            Spacer()
        }
        .padding(24)
        .presentationCornerRadius(28)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(Q.footnote.weight(.semibold)).foregroundStyle(Q.ground)
                .frame(width: 22, height: 22).background(Q.ink, in: Circle())
            Text(text).font(Q.body).foregroundStyle(Q.ink)
        }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quo has no account and no server. Nothing you do in it is sent to us: no page, address, search or tab.")
                Text("To know how many people use it, Quo tells TelemetryDeck once a day that it was opened, with its version and your iPhone\u{2019}s model and iOS version. You stand in as a random number, hashed before it leaves, and TelemetryDeck doesn\u{2019}t look at your IP address. Turn it off in Settings and the number is forgotten.")
                Text("Your history, open tabs and site settings are kept on this iPhone. Sync goes through your own iCloud, end to end encrypted with a key in your iCloud Keychain, so neither Apple nor we can read it.")
                Text("Sites you visit see what any browser shows them. Quo blocks ads, trackers and cookie banners, and takes tracking IDs off links, unless you turn that off for a site.")
                Text("What you type in the address field goes to your search engine for suggestions, never in Incognito. Voice search turns speech into words on this iPhone where it can. Translation happens on this iPhone.")
                Text("Site icons are asked of each site itself.")
            }
            .font(Q.body)
            .foregroundStyle(Q.ink)
            .padding(20)
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LicencesView: View {
    var body: some View {
        List {
            item("Search", "MIT", "Quo is a fork of Search by Office Commun. Its sync format and site lists are shared with Quo on the Mac.")
            item("adblock-rust", "MPL-2.0", "Quo\u{2019}s filter list converter is a port of Brave\u{2019}s adblock-rust content-blocking converter.")
            item("EasyList and EasyPrivacy", "GPLv3 / CC BY-SA 3.0", "Filter lists by the EasyList authors, fetched from easylist.to.")
            item("Fanboy\u{2019}s Cookie Monster", "GPLv3 / CC BY-SA 3.0", "A filter list for cookie banners, fetched from fanboy.co.nz.")
        }
        .navigationTitle("Open source licences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ name: String, _ licence: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(name).font(Q.bodyEmphasis); Spacer(); Text(licence).font(Q.footnote).foregroundStyle(Q.muted) }
            Text(note).font(Q.footnote).foregroundStyle(Q.muted)
        }
        .padding(.vertical, 4)
    }
}

struct DownloadsView: View {
    @ObservedObject private var downloads = Downloads.shared
    @State private var previewing: URL?
    @State private var clearing = false

    var body: some View {
        List {
            Section {
                if downloads.items.isEmpty {
                    Text("Nothing downloaded yet. Downloads are kept in the Files app too, under On My iPhone \u{203A} Quo.")
                        .font(Q.footnote).foregroundStyle(Q.muted)
                }
                ForEach(downloads.items) { item in
                    DownloadRow(item: item) {
                        if item.done, let file = item.file { previewing = file }
                        else if item.failed { downloads.retry(item) }
                    }
                    .swipeActions {
                        Button(item.running ? "Cancel" : "Delete", role: .destructive) { downloads.remove(item) }
                    }
                    .contextMenu {
                        if item.done, let file = item.file {
                            Button { previewing = file } label: { Label("Open", systemImage: "eye") }
                            ShareLink(item: file) { Label("Share\u{2026}", systemImage: "square.and.arrow.up") }
                        }
                        if item.failed, item.source != nil {
                            Button { downloads.retry(item) } label: { Label("Try Again", systemImage: "arrow.clockwise") }
                        }
                        if let source = item.source {
                            Button { UIPasteboard.general.url = source } label: { Label("Copy Address", systemImage: "link") }
                        }
                        Button(role: .destructive) { downloads.remove(item) } label: {
                            Label(item.running ? "Cancel" : "Delete", systemImage: item.running ? "xmark" : "trash")
                        }
                    }
                }
            } footer: {
                if !downloads.items.isEmpty {
                    Text("Also in the Files app, under On My iPhone \u{203A} Quo \u{203A} Downloads.")
                }
            }
            if downloads.items.contains(where: { !$0.running }) {
                Section {
                    Button("Clear Downloads", role: .destructive) { clearing = true }
                        .accessibilityIdentifier("downloads.clear")
                }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewing, in: downloads.finishedFiles)
        .confirmationDialog("The files are deleted from this iPhone.", isPresented: $clearing, titleVisibility: .visible) {
            Button("Delete Downloads", role: .destructive) { downloads.clear() }
        }
    }
}

/// One download: what kind of file, its name, and how far it's got.
private struct DownloadRow: View {
    let item: Downloads.Item
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(item.failed ? Q.caution : Q.muted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(Q.body)
                        .foregroundStyle(Q.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if item.running {
                        if let fraction = item.fraction {
                            ProgressView(value: fraction).tint(Q.ink)
                        } else {
                            ProgressView(value: 0).progressViewStyle(.linear).tint(Q.ink).opacity(0.4)
                        }
                    }
                    Text(item.failed && item.source != nil ? "Didn\u{2019}t finish \u{00B7} Tap to try again" : item.detail)
                        .font(Q.footnote)
                        .foregroundStyle(Q.muted)
                        .monospacedDigit()
                    if let suggested = item.suggested {
                        HStack(spacing: 6) {
                            Button { Downloads.shared.takeName(item) } label: {
                                Label("Rename to \u{201C}\(suggested)\u{201D}", systemImage: "apple.intelligence")
                                    .font(Q.footnote.weight(.medium))
                                    .foregroundStyle(Q.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Q.tile, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("download.rename")
                            Button { Downloads.shared.ignoreName(item) } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Q.muted)
                                    .frame(width: 26, height: 26)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Keep the name")
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("download.\(item.name)")
    }

    private var symbol: String {
        if item.failed { return "exclamationmark.circle" }
        if item.running { return "arrow.down.circle" }
        switch (item.name as NSString).pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "svg", "tif", "tiff": return "photo"
        case "mp4", "mov", "m4v", "webm": return "film"
        case "mp3", "m4a", "wav", "aac", "flac": return "waveform"
        case "zip", "gz", "tar", "7z", "rar": return "doc.zipper"
        case "txt", "md", "csv", "json", "rtf": return "doc.plaintext"
        default: return "doc"
        }
    }
}

/// Tabs closed lately, the last first, a tap from coming back with their
/// history. Never an incognito one.
struct ClosedTabsView: View {
    @ObservedObject private var tabs = Tabs.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if tabs.recentlyClosed.isEmpty {
                    Text("Tabs you close come here, a tap from coming back. Hold + to get to them.")
                        .font(Q.footnote).foregroundStyle(Q.muted)
                }
                ForEach(tabs.recentlyClosed) { item in
                    Button {
                        tabs.reopen(item)
                        Browser.shared.sheet = nil
                        Browser.shared.panel = .none
                    } label: {
                        HStack(spacing: 12) {
                            SiteMark(host: URL(string: item.url)?.host(), size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(Q.ink).lineLimit(1)
                                Text(item.closedAt.formatted(.relative(presentation: .named)))
                                    .font(Q.footnote).foregroundStyle(Q.muted)
                            }
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { tabs.forgetClosed(item) } }
                }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Recently Closed")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
    }
}

/// Holding +: the last few tabs closed, and the whole list.
struct ClosedMenu: View {
    @ObservedObject private var tabs = Tabs.shared

    var body: some View {
        let items = Array(tabs.recentlyClosed.prefix(8))
        if items.isEmpty {
            Text("No recently closed tabs")
        } else {
            Section("Recently Closed") {
                ForEach(items) { item in
                    Button {
                        tabs.reopen(item)
                        Browser.shared.panel = .none
                    } label: {
                        Label(item.title, systemImage: "arrow.uturn.backward")
                    }
                }
            }
            Button { Browser.shared.sheet = .closed } label: {
                Label("Show All Recently Closed", systemImage: "clock.arrow.circlepath")
            }
        }
    }
}

struct ArchiveView: View {
    @ObservedObject private var tabs = Tabs.shared
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if tabs.archived.isEmpty {
                    Text(settings.archiveAfter == .never
                         ? "Tabs aren\u{2019}t archived. Choose when in Settings \u{203A} Archive inactive tabs."
                         : "Tabs you leave alone for \(settings.archiveAfter.title.lowercased().replacingOccurrences(of: "after ", with: "")) come here, a tap from coming back.")
                        .font(Q.footnote).foregroundStyle(Q.muted)
                }
                ForEach(tabs.archived) { item in
                    Button {
                        tabs.restore(item)
                        Browser.shared.sheet = nil
                        Browser.shared.panel = .none
                    } label: {
                        HStack(spacing: 12) {
                            SiteMark(host: URL(string: item.url)?.host(), size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title).foregroundStyle(Q.ink).lineLimit(1)
                                Text(item.archived.formatted(.relative(presentation: .named)))
                                    .font(Q.footnote).foregroundStyle(Q.muted)
                            }
                        }
                    }
                    .swipeActions { Button("Remove", role: .destructive) { tabs.forgetArchived(item) } }
                }
            }
            if !tabs.archived.isEmpty {
                Section { Button("Clear Archive", role: .destructive) { tabs.clearArchive() } }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
    }
}
