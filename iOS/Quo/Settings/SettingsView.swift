import SwiftUI
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
                    Toggle(isOn: $settings.autoKeyboard) { label("keyboard", "Auto-open keyboard") }
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
                Button("Clear History") { History.shared.clear() }
                Button("Clear Cookies and Site Data", role: .destructive) { Cleaner.siteData() }
                Button("Clear Everything", role: .destructive) { Cleaner.everything() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Clearing cookies signs you out of sites. Your Mac\u{2019}s spaces, pins and bookmarks stay.")
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
    @MainActor static func siteData() {
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    }

    @MainActor static func everything() {
        siteData()
        History.shared.clear()
        Favicons.shared.forget()
        Tabs.shared.closeAll(incognito: false)
        Tabs.shared.closeAll(incognito: true)
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
        let when = RelativeDateTimeFormatter().localizedString(for: lastSynced, relativeTo: Date())
        let with = macs.isEmpty ? "no Mac yet" : macs.joined(separator: ", ")
        return "\(with) \u{00B7} \(when)"
    }
}

struct SyncView: View {
    @ObservedObject private var sync = MacSync.shared

    var body: some View {
        List {
            Section {
                Toggle("Sync with Quo on your Mac", isOn: $sync.on)
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
                    Text("Comes from your Mac: spaces, their pins, your bookmarks, and the search engine you use there.")
                        .font(Q.footnote).foregroundStyle(Q.muted)
                    Text("Goes to your Mac: what you pin here. Your iPhone\u{2019}s open tabs, history and passwords stay here.")
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
                Toggle("Suggestions as you type", isOn: $settings.engineSuggests)
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
                Text("Quo has no account, no server and no analytics. Nothing you do in it is sent to us, because there is nowhere for it to go.")
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

    var body: some View {
        List {
            if downloads.items.isEmpty {
                Text("Nothing downloaded yet. Downloads also appear in the Files app, under On My iPhone \u{203A} Quo.")
                    .font(Q.footnote).foregroundStyle(Q.muted)
            }
            ForEach(downloads.items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.failed ? "exclamationmark.circle" : "doc").foregroundStyle(Q.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        if !item.done && !item.failed { ProgressView().controlSize(.mini) }
                        if item.failed { Text("Didn\u{2019}t finish").font(Q.footnote).foregroundStyle(Q.muted) }
                    }
                    Spacer()
                    if item.done, let file = item.file {
                        ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }
                    }
                }
                .swipeActions { Button("Delete", role: .destructive) { downloads.remove(item) } }
            }
        }
        .tint(Q.ink)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
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
