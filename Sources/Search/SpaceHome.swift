import AppKit
import SwiftUI

// An empty tab is the space's home, laid out as today: the time large and
// the date under it, the space's name at the right; the field; and under
// it, in cards on the space's colour, the sites you visit most, what's next
// on your calendar, and the tabs you closed last. Each card is there only
// when it has something to say: no meeting, no card; nothing closed, no
// card; with nothing for the right, the sites take the whole width. A
// space with nothing yet says so once, and offers Bring Things Over. What
// you type takes the room: the cards step aside for the field's list.
// Nothing here is sent anywhere or kept: the lists are History's, the
// window's own and the Mac's calendar, worked out when the tab is shown.
//
// Quiet on purpose. The colour is the space's and the sites' own icons; the
// rest is ink, on the 4-point grid, with one fade as it comes. The parts
// above and below the field hang from the field itself (see Omnibox), so
// they are always where it is, whatever the window's chrome.

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

/// Above the field: the time, large, with today's date under it, and the
/// space's glyph and name at the right. Without spaces, the time and date.
struct SpaceHomeHeader: View {
    @ObservedObject var browser: Browser
    let width: CGFloat

    /// Today as the line under the time says it: "Friday, 20 November".
    static func day(_ date: Date = Date()) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    private var roomy: Bool { browser.prefs.roomyTabs }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            // The minute, as the menu bar has it (24-hour or not), moved on
            // as it turns.
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: roomy ? 68 : 64, weight: .medium).monospacedDigit())
                        .kerning(-1.9)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .fixedSize()
                    Text(SpaceHomeHeader.day(context.date))
                        .font(.system(size: roomy ? 16 : 15))
                        .foregroundStyle(Palette.muted)
                }
            }
            Spacer(minLength: 12)
            if browser.prefs.usesSpaces {
                HStack(spacing: 8) {
                    Image(systemName: browser.space.symbol)
                        .font(.system(size: roomy ? 14 : 13, weight: .medium))
                    Text(browser.space.name)
                        .font(.system(size: roomy ? 14 : 13))
                        .lineLimit(1)
                }
                .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 4)
        .frame(width: width, alignment: .leading)
        .modifier(HomeEntrance())
        .accessibilityElement(children: .combine)
    }
}

/// Below the field, in cards: the sites you visit most, the next thing on
/// your calendar, and the tabs you closed last, each only when it has
/// something; or, for a space with nothing yet, a line saying so.
struct SpaceHomeBelow: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var meetings = Meetings.shared
    let width: CGFloat
    /// What to show instead of looking it up: the bench's pictures.
    var sample: Sample?
    /// The row under the pointer: one ground for all of them, which travels
    /// from row to row as the tab column's does (HomeRow).
    @State private var hovered: String?
    @Namespace private var ground

    /// A home's contents given rather than looked up.
    struct Sample {
        var sites: [History.Site] = []
        var closed: [Browser.Ghost] = []
        var meeting: Meetings.Meeting?
        var now = Date()
        var calendar = true
    }

    init(browser: Browser, width: CGFloat, sample: Sample? = nil) {
        self.browser = browser
        self.width = width
        self.sample = sample
    }

    private var sites: [History.Site] { sample?.sites ?? browser.history.mostVisited(limit: 8) }
    private var closed: [Browser.Ghost] { sample?.closed ?? Array(browser.recentlyClosed.prefix(3)) }
    private var now: Date { sample?.now ?? meetings.now }
    private var calendar: Bool { sample?.calendar ?? (meetings.access == .granted) }
    /// The next meeting today, on now or to come and not put away; only
    /// with the calendar already shared (a pinned calendar's Show My
    /// Meetings), never asked for from here.
    private var meeting: Meetings.Meeting? {
        if let sample { return sample.meeting }
        guard meetings.access == .granted, let next = meetings.next, !meetings.dismissed.contains(next.id) else { return nil }
        let live = next.start <= meetings.now
        return live || Calendar.current.isDate(next.start, inSameDayAs: meetings.now) ? next : nil
    }

    var body: some View {
        let sites = self.sites, closed = self.closed, meeting = self.meeting
        let right = meeting != nil || !closed.isEmpty
        let half = (width - 16) / 2
        Group {
            if sites.isEmpty, !right {
                fresh
            } else {
                HStack(alignment: .top, spacing: 16) {
                    HomeCard("Most visited") {
                        if sites.isEmpty {
                            Text("Sites you come back to show up here after a day or two.")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        } else {
                            siteRows(sites, columns: right ? 1 : 2, width: right ? half - 20 : width - 20)
                        }
                    }
                    .frame(width: right ? half : width)
                    if right {
                        VStack(spacing: 16) {
                            if let meeting { MeetingCard(meeting: meeting, now: now, browser: browser) }
                            if !closed.isEmpty {
                                HomeCard("Pick up where you left off") {
                                    VStack(spacing: 0) {
                                        ForEach(closed) { ghost in closedRow(ghost) }
                                    }
                                }
                            }
                        }
                        .frame(width: half)
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
        .modifier(HomeEntrance())
        .onAppear { if sample == nil, meetings.access == .granted { meetings.watch() } }
    }

    /// A space with nothing yet: what will show up here, and the way to
    /// bring things from another browser.
    private var fresh: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Nothing here yet")
                    .font(.system(size: 17, weight: .semibold))
                    .kerning(-0.1)
                    .foregroundStyle(Palette.ink)
                Text(freshLine)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HomeButton("Bring Your Things", filled: true) { browser.bringingIn = "" }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .modifier(HomeCardGround(lit: false))
    }

    private var freshLine: String {
        let space = browser.prefs.usesSpaces ? " in \(browser.space.name)" : ""
        let calendar = self.calendar ? ", with the tabs you close and what's next on your calendar" : ", with the tabs you close"
        return "The sites you visit most\(space) show up here\(calendar)."
    }

    private func siteRows(_ sites: [History.Site], columns: Int, width: CGFloat) -> some View {
        let each = columns == 1 ? width : (width - 8) / 2
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
            ForEach(0..<((sites.count + columns - 1) / columns), id: \.self) { row in
                GridRow {
                    ForEach(sites[(row * columns)..<min(row * columns + columns, sites.count)]) { site in
                        HomeRow(id: "site:" + site.host, hovered: $hovered, ground: ground,
                                icon: Favicons.shared.cached(for: site.url), letter: site.name,
                                title: site.name, note: site.host, roomy: browser.prefs.roomyTabs) { go(site.url) }
                            .frame(width: each)
                            .help(site.url.absoluteString)
                    }
                }
            }
        }
    }

    private func closedRow(_ ghost: Browser.Ghost) -> some View {
        // One tab is named as itself; a bulk close by what went.
        let batch = browser.closedTitle(for: ghost)
        let title = batch.hasSuffix(" Tab") ? ghost.label : batch
        return HomeRow(id: "closed:" + ghost.id.uuidString, hovered: $hovered, ground: ground,
                       icon: Favicons.shared.cached(for: ghost.url), letter: nil,
                       title: title,
                       note: SpaceHomeBelow.ago(ghost.at, now: now), roomy: browser.prefs.roomyTabs) {
            browser.reopen(ghost)
        }
        .help("Reopen \(ghost.url.absoluteString)")
    }

    /// How long ago, as briefly as it can be said: "now", "12m", "3h", "2d".
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
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

/// A card's ground on the space's colour: dark glass in Dark, frosted white
/// in Light, a hairline round it, brighter when it is the thing happening now.
private struct HomeCardGround: ViewModifier {
    let lit: Bool
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(scheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(lit ? 0.26 : 0.08), lineWidth: 1)
            )
    }
}

/// A titled card of rows.
private struct HomeCard<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 10)
                .frame(height: 20, alignment: .bottom)
            content
        }
        .padding(.top, 14)
        .padding([.horizontal, .bottom], 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HomeCardGround(lit: false))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The next meeting: the day on a small tile, what it is and when, and
/// Join when it has a call: outlined while it is to come, filled once on.
private struct MeetingCard: View {
    let meeting: Meetings.Meeting
    let now: Date
    let browser: Browser

    private var live: Bool { meeting.start <= now && meeting.end > now }

    private var when: String {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        if live { return "Now · until \(time(meeting.end))" }
        let left = meeting.start.timeIntervalSince(now)
        if left <= 3600 {
            let minutes = max(1, Int((left / 60).rounded(.up)))
            return "\(time(meeting.start)) · in \(minutes) minute\(minutes == 1 ? "" : "s")"
        }
        return time(meeting.start)
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(meeting.start.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .medium))
                    .kerning(0.4)
                    .foregroundStyle(Palette.muted)
                Text(meeting.start.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
            }
            .frame(width: 40, height: 40)
            .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(when)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let join = meeting.join {
                HomeButton("Join", filled: live) { browser.open(join, foreground: true) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .modifier(HomeCardGround(lit: live))
        .accessibilityElement(children: .contain)
    }
}

/// A button on the home's cards: filled in ink for the one thing to press,
/// outlined otherwise.
private struct HomeButton: View {
    let title: String
    let filled: Bool
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, filled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(filled ? Palette.ground : Palette.ink)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background {
                    ZStack {
                        Capsule().fill(filled ? Palette.ink.opacity(hovering ? 1 : 0.92) : Palette.ink.opacity(hovering ? 0.08 : 0))
                        if !filled { Capsule().strokeBorder(Palette.ink.opacity(0.24), lineWidth: 1) }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .fixedSize()
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// One row: the page's icon, or its first letter on a quiet tile, its name,
/// and, at the row's end, its address or how long ago it closed. Hovered,
/// the list's one ground comes to it from the row it was behind, as in the
/// tab column.
private struct HomeRow: View {
    let id: String
    @Binding var hovered: String?
    let ground: Namespace.ID
    let icon: NSImage?
    /// The name its letter comes from when it has no icon; nil for a mark.
    let letter: String?
    let title: String
    let note: String
    var roomy = false
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                mark
                Text(title)
                    .font(.system(size: roomy ? 14.5 : 14, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if !note.isEmpty, note.lowercased() != title.lowercased() {
                    Text(note)
                        .font(.system(size: roomy ? 13 : 12.5).monospacedDigit())
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: roomy ? 42 : 40)
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
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        } else if let letter, let first = letter.first {
            Text(String(first).uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 18, height: 18)
                .background(Palette.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        } else {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 18, height: 18)
        }
    }
}
