import SwiftUI
import UIKit

/// From the ^: the address, back and forward, three big things to do with
/// the page, how it's shown, its site's settings, and what was blocked. It
/// sits in the bottom bar grown into a sheet (Chrome).
struct ToolbarPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    @ObservedObject private var sync = MacSync.shared
    /// Display options, open or closed as you last left them; closed at first.
    @AppStorage("toolbar.displayOpen") private var displayOpen = false
    @State private var copied = false

    private func dismiss() { browser.panel = .none }

    var body: some View {
        // No scroll view: what's here always fits, and a scroll view sized
        // to its contents is laid out twice over on every open.
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                address
                tiles
                display
                Button { browser.sheet = .site } label: {
                    Row(symbol: "gearshape", title: "Site settings", chevron: true)
                }
                .buttonStyle(RowButton())
                .background(Q.tile, in: RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous))
                .accessibilityIdentifier("toolbar.site")
                blocked
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - the address

    private var address: some View {
        HStack(spacing: 2) {
            small("chevron.left", enabled: tab.canGoBack, label: "Back") { tab.goBack() }
            small("chevron.right", enabled: tab.canGoForward, label: "Forward") { tab.goForward() }
            Button {
                browser.panel = .search(prefill: tab.url?.absoluteString, incognito: tab.incognito)
            } label: {
                HStack(spacing: 5) {
                    if tab.url?.scheme == "http" {
                        Image(systemName: "lock.open").font(.system(size: 11, weight: .semibold)).foregroundStyle(Q.caution)
                    }
                    Text(Address.shown(tab.url))
                        .font(Q.bodyEmphasis)
                        .foregroundStyle(Q.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Edit address")
            small(copied ? "checkmark" : "link", enabled: tab.url != nil, label: "Copy link") {
                UIPasteboard.general.url = tab.url
                Haptics.tap()
                withAnimation(Q.quick) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { withAnimation(Q.quick) { copied = false } }
            }
            small(tab.loading ? "xmark" : "arrow.clockwise", enabled: true, label: tab.loading ? "Stop" : "Reload") { tab.reload() }
        }
        .padding(.horizontal, 6)
        .frame(height: 54)
        .background(Q.tile, in: Capsule())
        .overlay(Capsule().strokeBorder(Q.hairline))
    }

    private func small(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(enabled ? Q.ink : Q.faint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: - three things to do

    private var tiles: some View {
        let pinned = tab.url.flatMap { sync.pin(for: $0) }
        return HStack(spacing: 10) {
            Tile(symbol: "doc.text.magnifyingglass", title: "Find on page") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    tab.webViewIfBuilt?.findInteraction?.presentFindNavigator(showingReplace: false)
                }
            }
            .accessibilityIdentifier("toolbar.find")
            Tile(symbol: pinned == nil ? "pin" : "pin.slash", title: pinned == nil ? "Pin" : "Unpin") {
                guard let url = tab.url else { return }
                if let pinned {
                    sync.unpin(pinned)
                    browser.say("Unpinned from \(sync.currentSpace?.name ?? "your space")")
                } else {
                    sync.pin(url, title: tab.shownTitle)
                    Haptics.done()
                    browser.say("Pinned to \(sync.currentSpace?.name ?? "your space")")
                }
            }
            .accessibilityIdentifier("toolbar.pin")
            if let url = tab.url {
                ShareLink(item: url, subject: Text(tab.shownTitle)) {
                    TileFace(symbol: "square.and.arrow.up", title: "Share")
                }
                .buttonStyle(PressStyle())
                .accessibilityIdentifier("toolbar.share")
            } else {
                Tile(symbol: "square.and.arrow.up", title: "Share") {}
            }
        }
    }

    // MARK: - how it's shown

    private var display: some View {
        VStack(spacing: 0) {
            Button { withAnimation(Q.snap) { displayOpen.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "textformat.size").font(.system(size: 16, weight: .medium)).foregroundStyle(Q.muted)
                        .frame(width: 24)
                    Text("Display options").font(Q.body).foregroundStyle(Q.ink)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Q.muted)
                        .rotationEffect(.degrees(displayOpen ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButton())
            .accessibilityIdentifier("toolbar.display")

            if displayOpen {
                Divider().overlay(Q.hairline).padding(.leading, 52)
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { browser.translate(tab) }
                } label: { Row(symbol: "translate", title: browser.translating == .done ? "Show original" : "Translate") }
                    .buttonStyle(RowButton())
                    .accessibilityIdentifier("toolbar.translate")
                Divider().overlay(Q.hairline).padding(.leading, 52)
                Button {
                    Task {
                        if let article = await Reader.extract(from: tab) {
                            browser.reader = article
                            browser.sheet = .reader
                        } else {
                            browser.say("Reader isn\u{2019}t available for this page")
                        }
                    }
                } label: { Row(symbol: "doc.plaintext", title: "Reader mode") }
                    .buttonStyle(RowButton())
                    .accessibilityIdentifier("toolbar.reader")
                Divider().overlay(Q.hairline).padding(.leading, 52)
                ZoomRow(tab: tab)
                Divider().overlay(Q.hairline).padding(.leading, 52)
                Button { tab.setDesktop(!tab.desktop) } label: {
                    Row(symbol: tab.desktop ? "iphone" : "desktopcomputer",
                        title: tab.desktop ? "Request mobile site" : "Request desktop site")
                }
                .buttonStyle(RowButton())
                .accessibilityIdentifier("toolbar.desktop")
            }
        }
        .background(Q.tile, in: RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous))
    }

    // MARK: - what was blocked

    private var blocked: some View {
        let count = tab.blocked + tab.scrubbed
        let headline: String = {
            if tab.bare { return "Showing the original page" }
            if count == 0 { return "Nothing to block here" }
            return "Quo blocked \(count) \(count == 1 ? "tracker" : "ads and trackers")"
        }()
        return Button {
            if tab.bare { tab.reload() } else { tab.showOriginal() }
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(Q.bodyEmphasis)
                    .foregroundStyle(Q.ink)
                Text(tab.bare ? "Tap to block again" : "Problems? Tap to restore the original page")
                    .font(Q.footnote)
                    .foregroundStyle(Q.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Q.tile, in: RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("toolbar.blocked")
    }
}

private struct ZoomRow: View {
    @ObservedObject var tab: Tab
    @State private var zoom: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "textformat.size.larger").font(.system(size: 16, weight: .medium)).foregroundStyle(Q.muted).frame(width: 24)
            Text("Page zoom").font(Q.body).foregroundStyle(Q.ink)
            Spacer()
            Text("\(Int((zoom * 100).rounded()))%")
                .font(Q.footnote.monospacedDigit())
                .contentTransition(.numericText(value: Double(zoom)))
                .animation(Q.quick, value: zoom)
                .foregroundStyle(Q.muted)
                .onTapGesture { set(1) }
            HStack(spacing: 0) {
                Button { set(zoom - 0.1) } label: { Image(systemName: "minus").frame(width: 42, height: 34) }
                    .accessibilityLabel("Zoom out")
                Rectangle().fill(Q.hairline).frame(width: 1, height: 18)
                Button { set(zoom + 0.1) } label: { Image(systemName: "plus").frame(width: 42, height: 34) }
                    .accessibilityLabel("Zoom in")
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Q.ink)
            .background(Q.wash, in: RoundedRectangle(cornerRadius: Q.radiusSM, style: .continuous))
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .onAppear { zoom = tab.zoom }
    }

    private func set(_ value: CGFloat) {
        let next = (min(max(value, 0.5), 3) * 10).rounded() / 10
        tab.zoom = next
        zoom = next
    }
}

// MARK: - pieces

struct Row: View {
    let symbol: String
    let title: String
    var note: String? = nil
    var chevron = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Q.muted)
                .frame(width: 24)
            Text(title).font(Q.body).foregroundStyle(Q.ink)
            Spacer()
            if let note { Text(note).font(Q.body).foregroundStyle(Q.muted) }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Q.faint)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .contentShape(Rectangle())
    }
}

struct RowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Q.wash : Color.clear)
            .animation(Q.quick, value: configuration.isPressed)
    }
}

struct Tile: View {
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { TileFace(symbol: symbol, title: title) }
            .buttonStyle(PressStyle())
    }
}

struct TileFace: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(Q.ink)
                .frame(height: 30)
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(Q.footnote.weight(.medium))
                .foregroundStyle(Q.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 96)
        .background(Q.tile, in: RoundedRectangle(cornerRadius: Q.radiusXL, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Q.radiusXL, style: .continuous))
    }
}

// MARK: - site settings

struct SiteSettingsView: View {
    let host: String?
    @ObservedObject var browser: Browser
    @ObservedObject private var sites = Sites.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let settings = sites.settings(for: host)
        List {
            Section {
                toggle("hand.raised", "Block ads", \.blockAds, settings)
                toggle("checklist.unchecked", "Block cookie banners", \.blockCookieBanners, settings)
                toggle("eye.slash", "Block trackers", \.blockTrackers, settings)
            } header: {
                Text("Settings for \(Sites.key(host) ?? "this site")").textCase(nil)
            }
            Section {
                toggle("rectangle.bottomhalf.inset.filled", "Collapse bottom bar", \.collapseBar, settings)
                Picker(selection: Binding(get: { settings.swipe }, set: { change(\.swipe, $0) })) {
                    ForEach(SwipeNav.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label { Text("Swipe to navigate") } icon: { Image(systemName: "hand.draw").foregroundStyle(Q.muted) }
                }
                .pickerStyle(.menu)
            }
            Section {
                Button {
                    browser.sheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { browser.sheet = .settings }
                } label: {
                    HStack {
                        Label { Text("App settings").foregroundStyle(Q.ink) } icon: { Image(systemName: "gearshape").foregroundStyle(Q.muted) }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Q.faint)
                    }
                }
                .accessibilityIdentifier("site.app")
            }
        }
        .tint(Q.ink)
        .scrollContentBackground(.hidden)
        .background(Q.sheet)
        .navigationTitle("Site settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    private func toggle(_ symbol: String, _ title: String, _ path: WritableKeyPath<SiteSettings, Bool>, _ settings: SiteSettings) -> some View {
        Toggle(isOn: Binding(get: { settings[keyPath: path] }, set: { change(path, $0) })) {
            Label { Text(title) } icon: { Image(systemName: symbol).foregroundStyle(Q.muted) }
        }
    }

    private func change<T>(_ path: WritableKeyPath<SiteSettings, T>, _ value: T) {
        var next = sites.settings(for: host)
        next[keyPath: path] = value
        sites.set(next, for: host)
        Blocker.shared.retune()
        Tabs.shared.current?.webViewIfBuilt?.allowsBackForwardNavigationGestures = next.swipe == .edges
        let blocking: [AnyKeyPath] = [\SiteSettings.blockAds, \SiteSettings.blockTrackers, \SiteSettings.blockCookieBanners]
        if blocking.contains(path as AnyKeyPath) {
            Tabs.shared.current?.reload()
        }
    }
}
