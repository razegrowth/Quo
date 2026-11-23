import SwiftUI

/// Your Mac's spaces: one page each, its pins, then the tabs open in it on
/// each Mac, then the bookmarks, the spaces' icons along the foot. Swipe or
/// tap an icon to change space.
struct SpacesSheet: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var sync = MacSync.shared
    /// How far it's being pulled down: back to nothing on its own when a
    /// drag ends or is cancelled.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.9))) private var drag: CGFloat = 0
    /// Where it was let go, held as it goes down and away.
    @State private var released: CGFloat = 0
    /// The spaces strip's own width, so a few spaces sit centred in it.
    @State private var stripWidth: CGFloat = 0
    /// The home indicator's strip under the sheet, from the sheet's own
    /// geometry, so it follows the window as it changes.
    @State private var footInset: CGFloat = 0

    private func dismiss() { browser.spacesOpen = false }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(sync.currentSpace?.name ?? "Personal")
                    .font(.title2.weight(.semibold))
                    .titleTracking()
                    .foregroundStyle(.white)
                    .contentTransition(.opacity)
                    .animation(Q.quick, value: sync.currentSpaceID)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 8)

            TabView(selection: $sync.currentSpaceID) {
                ForEach(sync.spaces) { space in
                    SpacePage(space: space, browser: browser)
                        .tag(space.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Each space landed on is felt, as a picker's step is.
            .onChange(of: sync.currentSpaceID) { _, _ in Haptics.pick() }
            .animation(Q.snap, value: sync.currentSpaceID)

            foot
        }
        .padding(.bottom, footInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ground }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous))
        .padding(.top, 10)
        .ignoresSafeArea(edges: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { footInset = $0 }
        .environment(\.colorScheme, .dark)
        .offset(y: max(drag, released))
        // Anywhere on it, measured on the screen so it follows the finger.
        .simultaneousGesture(closing)
    }

    /// Dark, washed with the space's colour, which crossfades as you go
    /// from one space to the next, as Arc's does.
    private var ground: some View {
        ZStack {
            Color(white: 0.11)
            ForEach(sync.spaces) { space in
                LinearGradient(colors: [Q.colour(of: space).opacity(0.42), Q.colour(of: space).opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
                    .opacity(space.id == sync.currentSpaceID ? 1 : 0)
            }
        }
        .animation(.easeOut(duration: 0.25), value: sync.currentSpaceID)
    }

    /// Pulled down, it follows the finger; let go far enough or fast
    /// enough and it goes on down, otherwise it springs back.
    private var closing: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($drag) { value, state, _ in
                let t = value.translation
                guard abs(t.height) > abs(t.width) else { return }
                state = t.height > 0 ? t.height : t.height / 6
            }
            .onEnded { value in
                let t = value.translation
                guard abs(t.height) > abs(t.width) else { return }
                if t.height > 120 || (t.height > 30 && value.predictedEndTranslation.height > 320) {
                    released = t.height
                    dismiss()
                }
            }
    }

    private var foot: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(sync.spaces) { space in
                        let on = space.id == sync.currentSpaceID
                        Button { withAnimation(Q.snap) { sync.currentSpaceID = space.id } } label: {
                            SpaceIcon(space: space, size: 19)
                                .foregroundStyle(.white)
                                .opacity(on ? 1 : 0.45)
                                .frame(width: 48, height: 44)
                                .background(on ? Color.white.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(PressStyle())
                        .accessibilityLabel(space.name)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .frame(minWidth: stripWidth)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            .padding(.vertical, 10)
            if !sync.on || sync.macs.isEmpty {
                Text(sync.on ? "Turn on iCloud sync in Quo on your Mac to see its spaces here." : "Sync with your Mac is off in Settings.")
                    .font(Q.caption)
                    .foregroundStyle(Q.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }
        }
    }
}

/// A space's icon: its symbol, or an emoji, or a house for the first.
struct SpaceIcon: View {
    let space: Space
    var size: CGFloat = 17

    var body: some View {
        if let icon = space.icon, !icon.isEmpty, UIImage(systemName: icon) == nil {
            Text(icon).font(.system(size: size + 2))
        } else {
            Image(systemName: space.icon.flatMap { UIImage(systemName: $0) != nil ? $0 : nil } ?? (space.isFirst ? "house" : "briefcase"))
                .font(.system(size: size, weight: .medium))
        }
    }
}

private struct SpacePage: View {
    let space: Space
    @ObservedObject var browser: Browser
    @ObservedObject private var sync = MacSync.shared
    @State private var open: Set<UUID> = []

    /// Each device's tabs open in this space. The first space also has a
    /// device's tabs in no space it knows, an iPhone's among them.
    private var onDevices: [(device: DeviceTabs, tabs: [SyncedTab])] {
        let known = Set(sync.spaces.map(\.id.uuidString))
        let home = space.id == sync.spaces.first?.id
        return sync.elsewhere.compactMap { device in
            let tabs = device.tabs(in: space.id.uuidString, known: known, orHome: home)
            return tabs.isEmpty ? nil : (device, tabs)
        }
    }

    var body: some View {
        let pins = sync.pins(in: space.id)
        let elsewhere = onDevices
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if pins.isEmpty && elsewhere.isEmpty && sync.bookmarks.isEmpty {
                    Text("Nothing pinned in this space yet. Pin a page from its toolbar, or on your Mac.")
                        .font(Q.footnote)
                        .foregroundStyle(Q.muted)
                        .padding(.horizontal, 22)
                        .padding(.top, 18)
                }
                ForEach(pins) { pin in
                    PinRow(pin: pin, browser: browser)
                }
                ForEach(elsewhere, id: \.device.id) { item in
                    OpenOnDevice(device: item.device, tabs: item.tabs, browser: browser)
                        .padding(.top, pins.isEmpty && item.device.id == elsewhere.first?.device.id ? 4 : 12)
                }
                if !(pins.isEmpty && elsewhere.isEmpty) && !sync.bookmarks.isEmpty {
                    Rectangle().fill(Q.hairline).frame(height: 1)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                }
                ForEach(sync.bookmarks) { mark in
                    BookmarkRows(mark: mark, depth: 0, open: $open, browser: browser)
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct PinRow: View {
    let pin: PinDef
    @ObservedObject var browser: Browser
    @ObservedObject private var sync = MacSync.shared

    var body: some View {
        Button { if let url = URL(string: pin.home) { browser.open(url) } } label: {
            HStack(spacing: 14) {
                SiteMark(host: URL(string: pin.home)?.host(), size: 24)
                Text(pin.name ?? pin.title)
                    .font(.body)
                    .foregroundStyle(Q.ink)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButton())
        .contextMenu {
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = pin.home }
            Button("Unpin", systemImage: "pin.slash", role: .destructive) { sync.unpin(pin) }
        }
    }
}

/// The tabs open in a space on one of your devices, under its name: a tap
/// opens the page here, in a tab of its own.
private struct OpenOnDevice: View {
    let device: DeviceTabs
    let tabs: [SyncedTab]
    @ObservedObject var browser: Browser
    @State private var all = false

    /// How many show before More.
    private static let first = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: device.phone ? "iphone" : "laptopcomputer")
                    .font(.system(size: 12, weight: .medium))
                Text("Open on \(device.name)")
                    .font(Q.footnote.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(OpenOnDevice.when(device.written))
                    .font(Q.caption)
            }
            .foregroundStyle(Q.muted)
            .padding(.horizontal, 22)
            .padding(.bottom, 2)

            ForEach(all ? tabs : Array(tabs.prefix(OpenOnDevice.first)), id: \.self) { tab in
                OpenTabRow(tab: tab, browser: browser)
            }
            if !all && tabs.count > OpenOnDevice.first {
                Button { withAnimation(Q.snap) { all = true } } label: {
                    Text("\(tabs.count - OpenOnDevice.first) More")
                        .font(Q.footnote.weight(.medium))
                        .foregroundStyle(Q.muted)
                        .padding(.horizontal, 22)
                        .frame(height: 40)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowButton())
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// When the device last said what it had open, in a few words.
    static func when(_ written: Double) -> String {
        let date = Date(timeIntervalSince1970: written)
        if Date().timeIntervalSince(date) < 60 { return "Now" }
        let format = RelativeDateTimeFormatter()
        format.unitsStyle = .short
        return format.localizedString(for: date, relativeTo: Date())
    }
}

private struct OpenTabRow: View {
    let tab: SyncedTab
    @ObservedObject var browser: Browser

    var body: some View {
        let url = URL(string: tab.url)
        Button { if let url { browser.open(url) } } label: {
            HStack(spacing: 14) {
                SiteMark(host: url?.host(), size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.title.isEmpty ? Address.shown(url) : tab.title)
                        .font(.body)
                        .foregroundStyle(Q.ink)
                        .lineLimit(1)
                    Text(Address.shown(url))
                        .font(Q.caption)
                        .foregroundStyle(Q.muted)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButton())
        .contextMenu {
            Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = tab.url }
        }
    }
}

private struct BookmarkRows: View {
    let mark: Bookmark
    let depth: Int
    @Binding var open: Set<UUID>
    @ObservedObject var browser: Browser

    var body: some View {
        if mark.isFolder {
            Button { withAnimation(Q.snap) { if open.contains(mark.id) { open.remove(mark.id) } else { open.insert(mark.id) } } } label: {
                HStack(spacing: 14) {
                    Image(systemName: open.contains(mark.id) ? "folder" : "folder.fill")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(Q.ink)
                        .frame(width: 24)
                    Text(mark.title).font(.body).foregroundStyle(Q.ink).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Q.faint)
                        .rotationEffect(.degrees(open.contains(mark.id) ? 90 : 0))
                }
                .padding(.leading, 22 + CGFloat(depth) * 18)
                .padding(.trailing, 22)
                .frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButton())
            if open.contains(mark.id) {
                ForEach(mark.children ?? []) { child in
                    BookmarkRows(mark: child, depth: depth + 1, open: $open, browser: browser)
                }
            }
        } else {
            Button { if let url = mark.url.flatMap(URL.init(string:)) { browser.open(url) } } label: {
                HStack(spacing: 14) {
                    SiteMark(host: mark.url.flatMap(URL.init(string:))?.host(), size: 22)
                    Text(mark.title.isEmpty ? (mark.url ?? "") : mark.title)
                        .font(.body).foregroundStyle(Q.ink).lineLimit(1)
                    Spacer()
                }
                .padding(.leading, 22 + CGFloat(depth) * 18)
                .padding(.trailing, 22)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowButton())
            .contextMenu {
                Button("Copy Link", systemImage: "link") { UIPasteboard.general.string = mark.url }
            }
        }
    }
}
