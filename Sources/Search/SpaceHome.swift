import AppKit
import SwiftUI

// An empty tab is the space's home: the card wears the space's colour and
// grain, and a column the field's own width runs through it. Above the
// field, the space's glyph and name and today's date; below it, the sites
// you visit most, two to a row, and the tabs you closed last. What you type
// takes the room: the lists step aside for the field's suggestions. Nothing
// here is sent anywhere or kept: the lists are History's and the window's
// own, worked out when the tab is shown.
//
// Quiet on purpose. The colour is the space's and the sites' own icons; the
// rest is the column's ink, on the 4-point grid, with one fade as it comes.
// The parts above and below the field hang from the field itself (see
// Omnibox), so they are always where it is, whatever the window's chrome.

/// The ground of an empty tab: the space's colour or gradient, as the
/// chrome wears it but a step stronger, with its grain.
struct SpaceHomeGround: View {
    @ObservedObject var browser: Browser

    var body: some View {
        ZStack {
            Palette.ground
            SpaceWash(look: browser.wash)
                .environment(\.washStrength, browser.washStrength == .subtle ? .rich : browser.washStrength)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One fade and a short rise for whatever comes with an empty tab, and
/// nothing with Reduce Motion.
private struct HomeEntrance: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || Motion.reduced ? 0 : 4)
            .onAppear {
                guard !Motion.reduced else { return shown = true }
                withAnimation(.easeOut(duration: 0.22)) { shown = true }
            }
    }
}

/// Above the field, at its left edge: the space's glyph in its colour and
/// its name, and today's date. Without spaces, the date alone is the title.
struct SpaceHomeHeader: View {
    @ObservedObject var browser: Browser
    let width: CGFloat

    /// Today as the title's line under it says it: "Friday, 20 November".
    static func day(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if browser.prefs.usesSpaces {
                // The glyph over the rows' icons, the name over their names.
                HStack(spacing: 12) {
                    Image(systemName: browser.space.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(browser.space.tint ?? Palette.muted)
                        .frame(width: 16)
                    Text(browser.space.name)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                }
                Text(SpaceHomeHeader.day())
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, 28)
            } else {
                Text(SpaceHomeHeader.day())
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Palette.ink)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: width, alignment: .leading)
        .modifier(HomeEntrance())
        .accessibilityElement(children: .combine)
    }
}

/// Below the field: the sites you visit most, two to a row, and the tabs
/// you closed last, each a row of the column's kind. A click loads the site
/// in this tab, or brings the tab back.
struct SpaceHomeBelow: View {
    @ObservedObject var browser: Browser
    let width: CGFloat
    /// The row under the pointer: one ground for all of them, which travels
    /// from row to row as the tab column's does (HomeRow).
    @State private var hovered: String?
    @Namespace private var ground

    private var sites: [History.Site] { browser.history.mostVisited(limit: 8) }
    private var closed: [Browser.Ghost] { Array(browser.recentlyClosed.prefix(3)) }

    var body: some View {
        let sites = self.sites, closed = self.closed
        let half = (width - 8) / 2
        VStack(alignment: .leading, spacing: 24) {
            if !sites.isEmpty {
                Section("Most visited") {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                        ForEach(0..<((sites.count + 1) / 2), id: \.self) { row in
                            GridRow {
                                ForEach(sites[(row * 2)..<min(row * 2 + 2, sites.count)]) { site in
                                    HomeRow(id: "site:" + site.host, hovered: $hovered, ground: ground,
                                            icon: Favicons.shared.cached(for: site.url), letter: site.name,
                                            title: site.name, note: site.host) { go(site.url) }
                                        .frame(width: half)
                                        .help(site.url.absoluteString)
                                }
                            }
                        }
                    }
                }
            }
            if !closed.isEmpty {
                Section("Recently closed") {
                    VStack(spacing: 0) {
                        ForEach(closed) { ghost in
                            let batch = browser.closedTitle(for: ghost)
                            let title = batch == "Closed Tab" ? ghost.title : batch
                            HomeRow(id: "closed:" + ghost.id.uuidString, hovered: $hovered, ground: ground,
                                    icon: Favicons.shared.cached(for: ghost.url), letter: nil,
                                    title: title.isEmpty ? (ghost.url.host() ?? ghost.url.absoluteString) : title,
                                    note: ghost.url.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? "") {
                                browser.reopen(ghost)
                            }
                            .help("Reopen \(ghost.url.absoluteString)")
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .modifier(HomeEntrance())
    }

    private func go(_ url: URL) {
        guard let tab = browser.active, tab.isBlank else {
            browser.open(url, foreground: true)
            return
        }
        browser.dismiss()
        tab.go(to: url)
    }
}

/// A list's name, in the column's secondary ink, close to its rows.
private struct Section<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 12)
                .frame(height: 20, alignment: .bottom)
            content
        }
    }
}

/// One row: the page's icon, or its first letter on a quiet tile, its name,
/// and its address dimmed after it. Hovered, the list's one ground comes to
/// it from the row it was behind, as in the tab column.
private struct HomeRow: View {
    let id: String
    @Binding var hovered: String?
    let ground: Namespace.ID
    let icon: NSImage?
    /// The name its letter comes from when it has no icon; nil for a mark.
    let letter: String?
    let title: String
    let note: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                mark
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if !note.isEmpty, note.lowercased() != title.lowercased() {
                        Text(note)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background {
                if hovered == id {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Palette.ink.opacity(0.07))
                        .matchedGeometryEffect(id: "hover", in: ground)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { on in
            if on {
                withAnimation(Motion.glide) { hovered = id }
            } else {
                // Leaving for the next row: that row takes the ground before
                // this lets go, so it travels rather than fading out and in.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                    guard hovered == id else { return }
                    withAnimation(Motion.quick) { hovered = nil }
                }
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else if let letter, let first = letter.first {
            Text(String(first).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 16, height: 16)
                .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 16, height: 16)
        }
    }
}
