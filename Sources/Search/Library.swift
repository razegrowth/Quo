import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

// The Library, as Arc's: past the first space, two fingers to the right, a
// place of its own for what you've kept. A rail of sections down the left
// (Media, Downloads, Spaces, Bookmarks, Archived Tabs) and the one picked
// beside it, Downloads first. It comes in with the fingers, the column
// widening by the rail as it does and the page beside it giving way, and
// carries on, or goes back, on a spring that takes the fingers' speed when
// they let go. Two fingers back to the left, the arrow at its foot, or the
// Library button at the column's foot put it away.
//
// Only in the column on the left, at its own width: the column of icons and
// the column on the right keep the bookmarks button where the Library's is.

enum LibrarySection: String, CaseIterable, Identifiable {
    case media, downloads, spaces, bookmarks, archive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Media"
        case .downloads: return "Downloads"
        case .spaces: return "Spaces"
        case .bookmarks: return "Bookmarks"
        case .archive: return "Archived Tabs"
        }
    }

    var icon: String {
        switch self {
        case .media: return "photo.on.rectangle"
        case .downloads: return "arrow.down.circle"
        case .spaces: return "square.on.square"
        case .bookmarks: return "bookmark"
        case .archive: return "archivebox"
        }
    }
}

/// How far the Library has come in, in points of the fingers' travel: 0 put
/// away, `total` all the way in, past it a little give. Its own object, so
/// only what moves with it redraws as the fingers go. After a swipe it runs a
/// spring of its own, a step each frame, so the page beside it is laid out
/// at every step the same way it is while the fingers are on it.
@MainActor
final class LibraryReveal: ObservableObject {
    @Published private(set) var value: CGFloat = 0
    private var velocity: CGFloat = 0
    private var target: CGFloat = 0
    private var ticking: Timer?
    private var samples: [(time: TimeInterval, value: CGFloat)] = []
    private var settled: (() -> Void)?

    /// Where the fingers have it.
    func follow(_ value: CGFloat) {
        stop()
        self.value = value
        let now = ProcessInfo.processInfo.systemUptime
        samples.append((now, value))
        samples.removeAll { now - $0.time > 0.1 }
    }

    /// The fingers' speed as they let go, in points a second.
    var release: CGFloat {
        guard let first = samples.first, let last = samples.last, last.time - first.time > 0.008 else { return 0 }
        return (last.value - first.value) / CGFloat(last.time - first.time)
    }

    /// On to `target`: critically damped, so it lands without overshooting,
    /// starting at `speed`. At once under Reduce Motion.
    func settle(to target: CGFloat, speed: CGFloat = 0, then done: (() -> Void)? = nil) {
        stop()
        samples.removeAll()
        self.target = target
        settled = done
        guard !Motion.reduced, abs(value - target) > 0.5 else {
            value = target
            finish()
            return
        }
        velocity = speed
        var last = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                // Small steps, however late the frame: the spring stays true.
                var left = min(now - last, 0.05)
                last = now
                while left > 0 {
                    let dt = CGFloat(min(left, 1.0 / 240))
                    left -= Double(dt)
                    let force = -LibraryReveal.stiffness * (self.value - self.target) - LibraryReveal.damping * self.velocity
                    self.velocity += force * dt
                    self.value += self.velocity * dt
                }
                if abs(self.value - self.target) < 0.5, abs(self.velocity) < 8 {
                    self.value = self.target
                    self.finish()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticking = timer
    }

    /// A response of about 0.3 s, critically damped: Arc's, measured from a
    /// recording of its Library coming in.
    private static let response: CGFloat = 0.3
    private static var omega: CGFloat { 2 * .pi / response }
    private static var stiffness: CGFloat { omega * omega }
    private static var damping: CGFloat { 2 * omega }

    private func finish() {
        stop()
        let done = settled
        settled = nil
        done?()
    }

    private func stop() {
        ticking?.invalidate()
        ticking = nil
    }
}

enum Library {
    /// The rail of sections: what the column widens by. The window's lights
    /// sit at its top, with room to spare before the list.
    static let rail: CGFloat = 92

    /// Whether this window has a Library: the column on the left, at its own
    /// width, not folded away.
    @MainActor static func available(_ browser: Browser) -> Bool {
        let prefs = browser.prefs
        return prefs.sidebar && !prefs.iconColumn && prefs.sidePosition == .left
    }

    /// The Library's whole width: the column and the rail.
    @MainActor static func total(_ browser: Browser) -> CGFloat {
        browser.prefs.columnWidth + rail
    }

    /// Past all the way in, the fingers meet a give of this much at most.
    static let give: CGFloat = 24
}

extension Browser {
    /// The Library, from its button or the menu: Downloads unless asked.
    func openLibrary(_ section: LibrarySection = .downloads) {
        guard Library.available(self) else { return }
        librarySection = section
        libraryShown = true
        libraryReveal.settle(to: Library.total(self))
    }

    func closeLibrary() {
        libraryShown = false
        libraryReveal.settle(to: 0)
    }

    func toggleLibrary() {
        libraryShown ? closeLibrary() : openLibrary()
    }
}

/// The column with the Library beside it: the column's own content moves
/// over and fades as the Library comes in from the left, the whole as wide
/// as the column and as much of the rail as has come. Tells the window how
/// wide that is at every step, so the page gives way in step.
struct LibraryStage<Column: View>: View {
    @ObservedObject var browser: Browser
    @ObservedObject var reveal: LibraryReveal
    let width: CGFloat
    let onFrame: Bool
    let onDrag: (CGFloat?) -> Void
    @ViewBuilder let column: () -> Column

    private var total: CGFloat { width + Library.rail }
    /// How much of the way in, 0 to 1.
    private var share: CGFloat { min(1, max(0, reveal.value / total)) }
    /// What the column widens by: the rail as it comes, then the give.
    private var extra: CGFloat { Library.rail * share + max(0, reveal.value - total) }

    var body: some View {
        let shown = reveal.value > 0.5 && Library.available(browser)
        ZStack(alignment: .topLeading) {
            column()
                .opacity(1 - share)
                .offset(x: extra)
                .allowsHitTesting(!shown)
            if shown {
                LibraryPanel(browser: browser, onFrame: onFrame)
                    .frame(width: total + max(0, reveal.value - total))
                    .offset(x: -(total - min(reveal.value, total)))
                    .allowsHitTesting(browser.libraryShown)
            }
        }
        .frame(width: width + extra, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .background(onFrame ? Palette.frame : Palette.ground)
        .onChange(of: extra) { old, now in
            if now > 0.01 { onDrag(width + now) } else if old > 0.01 { onDrag(nil) }
        }
        // The Library gone from under it (the column moved, or made icons
        // only) or the column itself gone: the page back to the column's
        // width, and the Library put away.
        .onChange(of: Library.available(browser)) { _, available in
            guard !available, reveal.value > 0 else { return }
            putAway()
        }
        .onDisappear {
            guard reveal.value > 0 else { return }
            putAway()
        }
    }

    private func putAway() {
        onDrag(nil)
        browser.libraryShown = false
        browser.libraryReveal.follow(0)
    }
}

/// The Library itself: the rail, and the section picked.
struct LibraryPanel: View {
    @ObservedObject var browser: Browser
    let onFrame: Bool

    var body: some View {
        HStack(spacing: 0) {
            rail
                .frame(width: Library.rail)
            section
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                // The section's title line in the lights' row, centred on
                // them: the card starts 6 points down, so its line is 12
                // shorter than the band.
                .environment(\.libraryBand, onFrame ? browser.topBand - 12 : browser.topBand)
                .background(Palette.ground.opacity(onFrame ? 1 : 0))
                .clipShape(RoundedRectangle(cornerRadius: onFrame ? Metrics.cardRadius : 0, style: .continuous))
                .padding(.vertical, onFrame ? 6 : 0)
                .overlay(alignment: .leading) {
                    if !onFrame { Rectangle().fill(Palette.hairline).frame(width: 1) }
                }
        }
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                onFrame ? Palette.frame : Palette.ground
                SpaceWash(look: browser.wash, space: browser.washSpace)
            }
        }
    }

    private var rail: some View {
        VStack(spacing: 6) {
            Spacer(minLength: browser.topBand)
            ForEach(LibrarySection.allCases) { section in
                RailButton(section: section, on: browser.librarySection == section) {
                    withAnimation(Motion.settle) { browser.librarySection = section }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Door(icon: "arrow.left", help: "Back to Your Tabs") { browser.closeLibrary() }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var section: some View {
        switch browser.librarySection {
        case .media: LibraryMedia(browser: browser, loot: browser.loot)
        case .downloads: LibraryDownloads(browser: browser, loot: browser.loot, fetches: browser.fetches)
        case .spaces: LibrarySpaces(browser: browser)
        case .bookmarks: LibraryBookmarks(browser: browser, bookmarks: browser.bookmarks)
        case .archive: LibraryArchive(browser: browser, archive: browser.archive)
        }
    }

    private struct RailButton: View {
        @Environment(\.greys) private var greys
        let section: LibrarySection
        let on: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                VStack(spacing: 5) {
                    Image(systemName: on ? section.icon + ".fill" : section.icon)
                        .font(.system(size: 17, weight: .medium))
                        .frame(height: 20)
                    Text(section.title)
                        .font(.system(size: 10.5, weight: on ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(on ? Palette.ink : Palette.muted)
                .frame(width: Library.rail - 14, height: 58)
                .background(on ? greys.wash : hovering ? greys.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .onHover { hovering = $0 }
            .help(section.title)
            .animation(Motion.quick, value: hovering)
        }
    }
}

/// How tall a section's title line is: the band the window's lights sit
/// in, so the title and the lights are one row.
private struct LibraryBandKey: EnvironmentKey {
    static let defaultValue: CGFloat = 42
}

extension EnvironmentValues {
    var libraryBand: CGFloat {
        get { self[LibraryBandKey.self] }
        set { self[LibraryBandKey.self] = newValue }
    }
}

/// A section's title line, in the lights' row.
private struct LibraryTitle<Trailing: View>: View {
    @Environment(\.libraryBand) private var band
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, 12)
            .frame(height: max(30, band))
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}

extension LibraryTitle where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Nothing yet, said quietly in the middle.
private struct LibraryEmpty: View {
    let icon: String
    let title: String
    let line: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Palette.muted)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text(line)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Downloads

/// The Downloads list, as under the downloads button; with nothing in it,
/// said in the middle as the other sections say it.
private struct LibraryDownloads: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot
    @ObservedObject var fetches: Fetches

    var body: some View {
        if loot.kept.isEmpty && fetches.entries.isEmpty {
            VStack(spacing: 0) {
                LibraryTitle(title: "Downloads") {
                    Door(icon: "folder", help: "Open the Downloads Folder") { NSWorkspace.shared.open(browser.downloadsFolder) }
                }
                LibraryEmpty(icon: "arrow.down.circle", title: "Nothing downloaded yet",
                             line: "Files you download show up here, a click from opening.")
            }
        } else {
            VStack(spacing: 0) {
                LibraryTitle(title: "Downloads") {
                    Door(icon: "folder", help: "Open the Downloads Folder") { NSWorkspace.shared.open(browser.downloadsFolder) }
                }
                DownloadsPanel(browser: browser, loot: loot, compact: true, titled: false)
                    .environment(\.asTab, true)
            }
        }
    }
}

// MARK: - Media

/// Pictures and videos among what you've downloaded, as a grid of their own
/// thumbnails, newest first. A click opens one.
private struct LibraryMedia: View {
    @ObservedObject var browser: Browser
    @ObservedObject var loot: Loot

    private var media: [Keep] {
        loot.kept.filter { keep in
            guard let type = UTType(filenameExtension: (keep.path as NSString).pathExtension) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie) || type.conforms(to: .video)
        }
    }

    var body: some View {
        let media = self.media
        VStack(spacing: 0) {
            LibraryTitle(title: "Media")
            if media.isEmpty {
                LibraryEmpty(icon: "photo.on.rectangle", title: "No pictures or videos yet",
                             line: "Images and videos you download show up here.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(media) { keep in
                            Thumb(keep: keep) { loot.open(keep) }
                                // Dragged out onto a page's upload box, the Desktop or another app.
                                .onDrag { keep.stillThere ? Loot.dragged(keep.url) : NSItemProvider() }
                                .contextMenu {
                                    Button("Show in Finder") { loot.reveal(keep) }
                                    Button("Remove from List") { loot.forget(keep) }
                                }
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private struct Thumb: View {
        let keep: Keep
        let open: () -> Void
        @State private var image: NSImage?
        @State private var hovering = false

        var body: some View {
            Button(action: open) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.hairline)
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(Palette.muted)
                    }
                }
                .frame(height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
                .overlay(alignment: .bottomLeading) {
                    if hovering {
                        Text(keep.name)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(5)
                    }
                }
                .opacity(keep.stillThere ? 1 : 0.4)
            }
            .buttonStyle(PressStyle())
            .onHover { hovering = $0 }
            .help(keep.name)
            .task(id: keep.path) { image = await Self.thumbnail(keep.url) }
        }

        static func thumbnail(_ url: URL) async -> NSImage? {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 200, height: 200),
                                                       scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            guard let made = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
            return made.nsImage
        }
    }
}

// MARK: - Spaces

/// Every space, the one you're in marked: a click goes to it, and the
/// Library goes with it.
private struct LibrarySpaces: View {
    @ObservedObject var browser: Browser
    @Environment(\.greys) private var greys

    var body: some View {
        VStack(spacing: 0) {
            LibraryTitle(title: "Spaces") {
                Door(icon: "plus", help: "New Space") {
                    browser.closeLibrary()
                    browser.askForSpace()
                }
            }
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(browser.spaces) { space in
                        Row(space: space, here: space.id == browser.spaceID) {
                            browser.closeLibrary()
                            if space.id != browser.spaceID { browser.switchSpace(to: space.id) }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private struct Row: View {
        @Environment(\.greys) private var greys
        let space: Space
        let here: Bool
        let act: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: act) {
                HStack(spacing: 10) {
                    Image(systemName: space.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 20)
                    Text(space.name)
                        .font(.system(size: 13, weight: here ? .semibold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if here {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.muted)
                    }
                }
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(here ? greys.wash : hovering ? greys.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

// MARK: - Bookmarks

/// The bookmarks, as the list under the bookmark button had them, with
/// adding this page and managing them at the foot.
private struct LibraryBookmarks: View {
    @ObservedObject var browser: Browser
    let bookmarks: Bookmarks
    @State private var expanded: Set<Bookmark.ID>

    init(browser: Browser, bookmarks: Bookmarks) {
        self.browser = browser
        self.bookmarks = bookmarks
        _expanded = State(initialValue: BookmarksDropdown.opening(bookmarks.roots))
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryTitle(title: "Bookmarks") {
                Door(icon: browser.pageKept ? "bookmark.fill" : "plus",
                     help: browser.pageKept ? "Edit This Bookmark" : "Bookmark This Page") {
                    browser.bookmarkCurrent()
                }
                Door(icon: "slider.horizontal.3", help: "Manage Bookmarks") { browser.bookmarking = true }
            }
            if bookmarks.isEmpty {
                LibraryEmpty(icon: "bookmark", title: "No bookmarks yet",
                             line: "Bookmark a page with ⌘D, or bring yours over from another browser.")
            } else {
                ScrollView(showsIndicators: false) {
                    BookmarkOutline(bookmarks: bookmarks, expanded: $expanded) { url in
                        browser.pickBookmark(url)
                    } openInNewTab: { url in
                        browser.pickBookmark(url, inNewTab: true)
                    }
                    .padding(6)
                }
            }
        }
    }
}

// MARK: - Archived Tabs

/// The tabs closed by themselves, newest first: a click opens one again.
private struct LibraryArchive: View {
    @ObservedObject var browser: Browser
    @ObservedObject var archive: Archive

    var body: some View {
        let listed = archive.listed()
        VStack(spacing: 0) {
            LibraryTitle(title: "Archived Tabs") {
                if !listed.isEmpty { Pill("Clear") { archive.clear() } }
            }
            if listed.isEmpty {
                LibraryEmpty(icon: "archivebox", title: "Nothing archived",
                             line: browser.prefs.tabLife.interval == nil
                                ? "Tabs close themselves only if you ask them to, in Settings › Tabs."
                                : "Tabs that close themselves land here, a click from coming back.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(listed) { tab in
                            Row(tab: tab, open: { browser.reopen(tab) }, remove: { archive.remove(tab.id) })
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private struct Row: View {
        @Environment(\.greys) private var greys
        let tab: Archived
        let open: () -> Void
        let remove: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: open) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tab.label)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text(tab.site + " · " + tab.closed.formatted(.relative(presentation: .named)))
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if hovering {
                        Door(icon: "xmark", help: "Remove", side: 22, act: remove)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(hovering ? greys.hover : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}
