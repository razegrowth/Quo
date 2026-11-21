import AppKit
import EventKit
import SwiftUI
import WebKit

// A pinned calendar and a pinned inbox say what's coming without being
// opened, as Arc's did.
//
// The calendar: Google Calendar, Outlook's or Notion's pinned. Its square
// counts down to the next meeting ("30m", then "now"), a row over the
// column's foot offers Join a few minutes before one with a call link, and
// a hover over the pin shows the rest of today. The meetings come from the
// calendars on this Mac (EventKit) — the Google account added in System
// Settings › Internet Accounts — asked for only when Show My Meetings is
// pressed in the preview, never on its own. Nothing is sent anywhere.
//
// The inbox: Gmail pinned. Its square wears the unread count its title
// gives, and a hover shows the latest unread: the inbox's own feed, fetched
// by the pinned tab itself, signed in as it is, so nothing new is signed in
// to and nothing leaves for anywhere but Gmail.

enum GlanceKind {
    case calendar, mail

    /// For the bench: pages that stand in for a calendar or an inbox, by
    /// path, on a test run's own server. Empty otherwise.
    nonisolated(unsafe) static var standIn: [String: GlanceKind] = [:]

    static func of(_ url: URL?) -> GlanceKind? {
        guard let url, let host = url.host()?.lowercased() else { return nil }
        if !standIn.isEmpty, let kind = standIn[url.path] { return kind }
        if host == "calendar.google.com" || host == "calendar.notion.so" { return .calendar }
        if host == "outlook.office.com" || host == "outlook.live.com" || host == "outlook.office365.com" {
            return url.path.lowercased().contains("/calendar") ? .calendar : nil
        }
        if host == "mail.google.com" { return .mail }
        return nil
    }
}

// MARK: - meetings

@MainActor
final class Meetings: ObservableObject {
    static let shared = Meetings()

    struct Meeting: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        /// The call to join, when the event has one (Meet, Zoom, Teams…).
        let join: URL?
        let colour: Color?
    }

    enum Access { case unasked, granted, refused }

    /// What is left of today and the morning after: on now or to come.
    @Published private(set) var upcoming: [Meeting] = []
    /// The clock the countdowns read, moved on every half minute.
    @Published private(set) var now = Date()
    @Published private(set) var access: Access
    /// Join rows put away, by meeting.
    @Published private(set) var dismissed: Set<String> = []

    /// How long before a meeting with a call its Join row comes up.
    static let joinAhead: TimeInterval = 5 * 60
    /// The pin counts down within the hour.
    static let countsFrom: TimeInterval = 60 * 60

    private let store = EKEventStore()
    private var started = false
    private var timer: Timer?
    /// Meetings given by the bench, in place of the Mac's.
    private var injected: [Meeting]?

    init() {
        access = Store.testing ? .unasked : Meetings.status()
    }

    private static func status() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .unasked
        default: return .refused
        }
    }

    /// A pinned calendar is on screen: keep the clock and the meetings fresh.
    func watch() {
        guard !started else { return }
        started = true
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            MainActor.assumeIsolated { Meetings.shared.tick() }
        }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { Meetings.shared.refresh() }
        }
        refresh()
    }

    /// Show My Meetings: macOS asks, once.
    func ask() {
        guard !Store.testing else { return }
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                Meetings.shared.access = granted ? .granted : .refused
                Meetings.shared.refresh()
            }
        }
    }

    func dismiss(_ meeting: Meeting) { dismissed.insert(meeting.id) }

    private func tick() {
        now = Date()
        // Past midnight, or an hour on: read again, in case.
        refresh()
    }

    func refresh() {
        now = Date()
        if let injected {
            upcoming = injected.filter { $0.end > now }
            return
        }
        guard access == .granted else { upcoming = []; return }
        let from = Calendar.current.date(byAdding: .hour, value: -4, to: now) ?? now
        let to = Calendar.current.date(byAdding: .hour, value: 24, to: now) ?? now
        let events = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
        upcoming = events
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled && !Meetings.declined($0) }
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
            .map { event in
                Meeting(id: event.calendarItemIdentifier + "\(event.startDate.timeIntervalSince1970)",
                        title: event.title?.isEmpty == false ? event.title : "Busy",
                        start: event.startDate, end: event.endDate, join: Meetings.joinLink(event),
                        colour: event.calendar.map { Color(cgColor: $0.cgColor) })
            }
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    /// For the bench: meetings as given, `start`s in minutes from now.
    func inject(_ meetings: [(title: String, inMinutes: Double, minutes: Double, link: String?)]) {
        let now = Date()
        injected = meetings.enumerated().map { index, given in
            let start = now.addingTimeInterval(given.inMinutes * 60)
            return Meeting(id: "bench-\(index)", title: given.title, start: start, end: start.addingTimeInterval(given.minutes * 60),
                           join: given.link.flatMap(URL.init(string:)), colour: nil)
        }
        access = .granted
        dismissed = []
        refresh()
    }

    // MARK: what they say

    /// On now, or the next to come.
    var next: Meeting? { upcoming.first { $0.end > now } }

    /// The pin's countdown: "now" while one is on, "12m" within the hour.
    static func countdown(to meeting: Meeting, now: Date) -> String? {
        if meeting.start <= now, meeting.end > now { return "now" }
        let left = meeting.start.timeIntervalSince(now)
        guard left > 0, left <= countsFrom else { return nil }
        return "\(Int((left / 60).rounded(.up)))m"
    }

    /// The meeting to offer Join for: with a call, about to start or on,
    /// and not put away.
    var joinable: Meeting? {
        guard let next, next.join != nil, !dismissed.contains(next.id) else { return nil }
        return next.start.timeIntervalSince(now) <= Meetings.joinAhead ? next : nil
    }

    /// The call in an event: its own address, or one in where or what.
    static func joinLink(_ event: EKEvent) -> URL? {
        if let url = event.url, isCall(url) { return url }
        return joinLink(in: [event.location, event.notes].compactMap { $0 }.joined(separator: "\n"))
    }

    static func joinLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url).first(where: isCall)
    }

    static func isCall(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else { return false }
        let calls = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "webex.com", "whereby.com",
                     "around.co", "meet.jit.si", "app.cal.com", "facetime.apple.com", "slack.com"]
        return calls.contains { host == $0 || host.hasSuffix("." + $0) }
            && !(host.hasSuffix("slack.com") && !url.path.contains("/huddle"))
    }

    /// "10:30 – 11:00", as the Mac writes times.
    static func span(_ meeting: Meeting) -> String {
        let style = Date.FormatStyle.dateTime.hour().minute()
        return "\(meeting.start.formatted(style)) – \(meeting.end.formatted(style))"
    }
}

// MARK: - the inbox

@MainActor
final class Inbox: ObservableObject {
    static let shared = Inbox()

    struct Mail: Identifiable, Equatable {
        let id: String
        let from: String
        let subject: String
        let summary: String
        let when: Date?
        let link: URL?
        /// Read from the inbox on the page rather than the feed: its row
        /// there, which a click opens; and the time as the page wrote it.
        var row: String? = nil
        var said: String? = nil
    }

    /// The latest unread, by pinned tab; nil until fetched, empty when the
    /// feed answered nothing unread.
    @Published private(set) var mail: [UUID: [Mail]] = [:]
    /// Tabs whose inbox has no feed (Google gives one to Workspace accounts):
    /// the count is all there is to say.
    @Published private(set) var feedless: Set<UUID> = []
    private var fetched: [UUID: Date] = [:]

    /// "Inbox (12) - you@example.com - Gmail" → 12.
    static func unread(in title: String) -> Int? {
        guard let range = title.range(of: #"\(\d[\d.,]*\)"#, options: .regularExpression) else { return nil }
        return Int(title[range].filter(\.isNumber))
    }

    /// The tab's account: mail.google.com/mail/u/1/… → 1.
    static func account(_ url: URL?) -> Int {
        guard let path = url?.path, let range = path.range(of: #"/mail/u/\d+"#, options: .regularExpression) else { return 0 }
        return Int(path[range].filter(\.isNumber)) ?? 0
    }

    /// Gmail's own notifications, the latest by tab (and the last from no
    /// tab in particular): as Arc's card showed it. Kept in memory only.
    @Published private(set) var notes: [UUID: Mail] = [:]
    private var lastNote: Mail?

    /// A notification from Gmail: its title is who it's from, its body the
    /// subject and then a line of the mail.
    func noted(origin: String, title: String, body: String, tab: UUID?) {
        guard URL(string: origin)?.host()?.lowercased() == "mail.google.com" else { return }
        let lines = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let mail = Mail(id: "note-\(UUID().uuidString)", from: title, subject: lines.first ?? "",
                        summary: lines.count > 1 ? lines[1] : "", when: Date(), link: nil)
        if let tab { notes[tab] = mail } else { lastNote = mail }
        objectWillChange.send()
    }

    /// What the card shows: the newer of its last notification and the
    /// first unread mail read from the inbox.
    func latest(for tab: Tab) -> Mail? {
        let note = notes[tab.id] ?? lastNote
        let first = mail[tab.id]?.first
        guard let note else { return first }
        guard let first, let when = first.when else { return note }
        return (note.when ?? .distantPast) >= when ? note : first
    }

    /// For the bench: as if never read.
    func forget(_ tab: UUID) {
        notes[tab] = nil
        lastNote = nil
        fetched[tab] = nil
        mail[tab] = nil
    }

    /// For the bench: an inbox as given.
    func inject(_ mails: [Mail], for tab: UUID) {
        mail[tab] = mails
        fetched[tab] = Date()
    }

    /// The latest unread, read by the tab's own page as it is signed in:
    /// the inbox's feed, or, where Google gives no feed or the page won't
    /// fetch it, the unread rows of the inbox the page is showing. Again
    /// only after half a minute.
    func refresh(_ tab: Tab) async {
        if let last = fetched[tab.id], Date().timeIntervalSince(last) < 30 { return }
        guard let page = tab.built else { return }
        fetched[tab.id] = Date()
        let path = "/mail/u/\(Inbox.account(tab.address))/feed/atom"
        let feed = """
        try {
          const answer = await fetch(path, { credentials: 'include' });
          if (!answer.ok) return null;
          const text = await answer.text();
          return text.trimStart().startsWith('<') && text.includes('<feed') ? text : null;
        } catch (e) { return null; }
        """
        if let text = try? await page.callAsyncJavaScript(feed, arguments: ["path": path], in: nil, contentWorld: .defaultClient) as? String,
           let data = text.data(using: .utf8) {
            feedless.remove(tab.id)
            mail[tab.id] = Array(InboxFeed.read(data).prefix(6))
            return
        }
        // The rows Gmail draws for unread mail in the list on screen.
        let rows = """
        const rows = [...document.querySelectorAll('tr.zA.zE')].slice(0, 6);
        return rows.map(r => {
          const who = r.querySelector('.yX [email], .yW [email]');
          const time = r.querySelector('.xW span[title], .xW span');
          return {
            row: r.id || '',
            from: ((who && (who.getAttribute('name') || who.textContent)) || '').trim(),
            subject: ((r.querySelector('.bog') || {}).textContent || '').trim(),
            summary: ((r.querySelector('.y2') || {}).textContent || '').replace(/^[\\s\\-–—]+/, '').trim(),
            said: ((time && time.textContent) || '').trim(),
          };
        });
        """
        let found = (try? await page.callAsyncJavaScript(rows, arguments: [:], in: nil, contentWorld: .defaultClient)) as? [[String: Any]]
        guard let found, !found.isEmpty else {
            feedless.insert(tab.id)
            mail[tab.id] = mail[tab.id] ?? []
            return
        }
        feedless.remove(tab.id)
        mail[tab.id] = found.enumerated().map { index, row in
            Mail(id: (row["row"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "row-\(index)",
                 from: row["from"] as? String ?? "", subject: (row["subject"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)",
                 summary: row["summary"] as? String ?? "", when: nil, link: nil,
                 row: (row["row"] as? String).flatMap { $0.isEmpty ? nil : $0 }, said: row["said"] as? String)
        }
    }

    /// A row read from the page, opened as a click on it there opens it.
    func open(_ mail: Mail, in tab: Tab) {
        guard let row = mail.row, let page = tab.built else { return }
        Task {
            _ = try? await page.callAsyncJavaScript("const r = document.getElementById(id); if (r) r.click();",
                                                    arguments: ["id": row], in: nil, contentWorld: .defaultClient)
        }
    }
}

/// Gmail's Atom feed, read to its entries.
final class InboxFeed: NSObject, XMLParserDelegate {
    private var entries: [Inbox.Mail] = []
    private var field: [String: String] = [:]
    private var link: URL?
    private var inEntry = false
    private var inAuthor = false
    private var text = ""

    static func read(_ data: Data) -> [Inbox.Mail] {
        let reader = InboxFeed()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.entries
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "entry": inEntry = true; field = [:]; link = nil
        case "author": inAuthor = true
        case "link" where inEntry: link = attributes["href"].flatMap(URL.init(string:))
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inEntry else { return }
        switch name {
        case "name" where inAuthor: field["from"] = value
        case "email" where inAuthor: if field["from"]?.isEmpty ?? true { field["from"] = value }
        case "author": inAuthor = false
        case "title", "summary", "id", "issued", "modified": field[name] = value
        case "entry":
            inEntry = false
            let when = (field["issued"] ?? field["modified"]).flatMap { try? Date($0, strategy: .iso8601) }
            entries.append(Inbox.Mail(id: field["id"] ?? UUID().uuidString, from: field["from"] ?? "",
                                      subject: field["title"]?.isEmpty == false ? field["title"]! : "(no subject)",
                                      summary: field["summary"] ?? "", when: when, link: link))
        default: break
        }
        text = ""
    }
}

// MARK: - on the pin

/// What a pinned calendar or inbox wears in its square's corner, as Arc's
/// pins did: the countdown to the next meeting in small type ("30m", then
/// "now"), or a red dot while mail is unread. Nothing on any other pin, and
/// nothing when there's nothing to say.
struct GlanceCorner: View {
    @ObservedObject var tab: Tab
    let scale: CGFloat
    @ObservedObject private var meetings = Meetings.shared

    /// Gmail's red, a touch softer on the grey squares.
    static let unreadRed = Color(red: 0.96, green: 0.27, blue: 0.23)

    var body: some View {
        Group {
            switch GlanceKind.of(tab.address) {
            case .calendar?:
                if let next = meetings.next, let left = Meetings.countdown(to: next, now: meetings.now) {
                    let urgent = left == "now" || next.start.timeIntervalSince(meetings.now) <= Meetings.joinAhead
                    Text(left)
                        // Small and quiet, a note on the pin rather than a
                        // badge; a touch less quiet once it's close.
                        .font(.system(size: max(7, scale * 7 / 34), weight: urgent ? .semibold : .medium).monospacedDigit())
                        .foregroundStyle(Palette.ink.opacity(urgent ? 0.6 : 0.45))
                        .fixedSize()
                        .padding(.trailing, scale * 5 / 34)
                        .padding(.bottom, scale * 4 / 34)
                        .accessibilityLabel(left == "now" ? "\(next.title), now" : "\(next.title) in \(left)")
                        .transition(.opacity)
                }
            case .mail?:
                if let unread = Inbox.unread(in: tab.title), unread > 0 {
                    let size = max(4.5, scale * 4.3 / 34)
                    Circle()
                        .fill(GlanceCorner.unreadRed)
                        .frame(width: size, height: size)
                        // The same gap from the corner as the calendar's
                        // countdown leaves: about 7 points each way.
                        .padding(.trailing, scale * 5.4 / 34)
                        .padding(.bottom, scale * 5.4 / 34)
                        .accessibilityLabel("\(unread) unread")
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            case nil:
                EmptyView()
            }
        }
        .allowsHitTesting(false)
        .animation(Motion.settle, value: tab.title)
        .animation(Motion.settle, value: meetings.now)
    }
}

/// A pinned calendar or inbox, told where it is and when the pointer is
/// on it, for its card (GlanceFloat); the calendar's clock started while
/// one is pinned. Nothing on any other pin.
struct PinGlance: ViewModifier {
    let browser: Browser
    @ObservedObject var tab: Tab
    let hovering: Bool
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        if let kind = GlanceKind.of(tab.address) {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    frame = $0
                    GlanceHover.shared.frames[tab.id] = $0
                }
                .onChange(of: hovering) { _, on in GlanceHover.shared.pin(browser, tab, at: frame, hovering: on) }
                .onAppear { if kind == .calendar { Meetings.shared.watch() } }
                .onDisappear { GlanceHover.shared.gone(tab) }
        } else {
            content
        }
    }
}

/// Which pin's card is up, if any: it comes a moment after the pointer
/// rests on a pin, moves at once to another pin the pointer goes on to,
/// and goes a moment after the pointer has left both the pin and the card.
@MainActor
final class GlanceHover: ObservableObject {
    static let shared = GlanceHover()

    struct Shown: Equatable {
        let browser: ObjectIdentifier
        let tab: UUID
        let pin: CGRect
    }

    @Published private(set) var shown: Shown?
    /// Where each glancing pin is, for the bench to bring its card.
    var frames: [UUID: CGRect] = [:]
    private var onPin: Shown?
    private var onCard = false
    private var turn = 0

    func pin(_ browser: Browser, _ tab: Tab, at frame: CGRect, hovering: Bool) {
        if hovering {
            onPin = Shown(browser: ObjectIdentifier(browser), tab: tab.id, pin: frame)
            settle(after: shown == nil ? 0.45 : 0.08)
        } else if onPin?.tab == tab.id {
            onPin = nil
            settle(after: 0.3)
        }
    }

    func card(_ on: Bool) {
        onCard = on
        if !on { settle(after: 0.3) }
    }

    /// Gone from the column (unpinned, its space left): its card with it.
    func gone(_ tab: Tab) {
        guard shown?.tab == tab.id || onPin?.tab == tab.id else { return }
        if onPin?.tab == tab.id { onPin = nil }
        onCard = false
        settle(after: 0)
    }

    /// Put away now: a click in it, or on its pin.
    func dismiss() {
        onPin = nil
        onCard = false
        settle(after: 0)
    }

    private func settle(after delay: Double) {
        turn += 1
        let mine = turn
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, mine == self.turn else { return }
            let next = self.onPin ?? (self.onCard ? self.shown : nil)
            guard next != self.shown else { return }
            withAnimation(Motion.reduced ? nil : Motion.settle) { self.shown = next }
        }
    }
}

// MARK: - the card

/// The card beside a pinned calendar or inbox while the pointer is on it,
/// as Arc's: over the page, hung from the pin's far corner, no arrow.
struct GlanceFloat: View {
    @ObservedObject var browser: Browser
    let onRight: Bool
    @ObservedObject private var hover = GlanceHover.shared

    static let width: CGFloat = 264

    var body: some View {
        GeometryReader { geo in
            let room = geo.frame(in: .global)
            ZStack(alignment: .topLeading) {
                if let shown = hover.shown, shown.browser == ObjectIdentifier(browser),
                   let tab = browser.tabs.first(where: { $0.id == shown.tab }),
                   let kind = GlanceKind.of(tab.address) {
                    let wanted = onRight ? shown.pin.minX - room.minX - GlanceFloat.width + 8 : shown.pin.maxX - room.minX - 8
                    let x = min(max(8, wanted), room.width - GlanceFloat.width - 8)
                    let y = shown.pin.maxY - room.minY - 2
                    GlanceCardFrame {
                        switch kind {
                        case .mail: MailCard(browser: browser, tab: tab)
                        case .calendar: CalendarCard(browser: browser)
                        }
                    }
                    .onHover { GlanceHover.shared.card($0) }
                    .offset(x: x, y: y)
                    .id(shown.tab)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: onRight ? .topTrailing : .topLeading))
                            .combined(with: .offset(y: -4)),
                        removal: .opacity.combined(with: .scale(scale: 0.98, anchor: onRight ? .topTrailing : .topLeading))))
                }
            }
            .frame(width: room.width, height: room.height, alignment: .topLeading)
        }
    }
}

/// The card itself: the window's ground, a light edge and a soft shadow,
/// as the bookmarks' card is.
private struct GlanceCardFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: GlanceFloat.width, alignment: .leading)
            .background(Palette.ground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.ink.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 20, y: 8)
    }
}

/// How long ago, as a notification says it: "55s", "4m", "2h", "3d".
enum GlanceTime {
    static func ago(_ date: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }
}

/// A round button in the card's corner, as Arc's compose.
private struct CardButton: View {
    let symbol: String
    let help: String
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 30, height: 30)
                .background(Palette.ink.opacity(hovering ? 0.14 : 0.08), in: Circle())
                .overlay(Circle().strokeBorder(Palette.ink.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
        .onHover { on in withAnimation(Motion.quick) { hovering = on } }
        .help(help)
    }
}

/// The inbox: the latest mail, as its notification said it, or the first
/// unread one; a click opens it in the pin, + writes a new one.
private struct MailCard: View {
    let browser: Browser
    @ObservedObject var tab: Tab
    @ObservedObject private var inbox = Inbox.shared

    var body: some View {
        let unread = Inbox.unread(in: tab.title) ?? 0
        let latest = inbox.latest(for: tab)
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 3) {
                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(latest.from.isEmpty ? "Gmail" : latest.from)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(latest.when.map { GlanceTime.ago($0, now: context.date) } ?? latest.said ?? "")
                        }
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(Palette.muted)
                    }
                    Group {
                        Text(latest.subject)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink.opacity(0.9))
                            .lineLimit(1)
                        if !latest.summary.isEmpty {
                            Text(latest.summary)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    // Clear of the + in the corner.
                    .padding(.trailing, 40)
                } else {
                    Text("Inbox")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Group {
                        Text(unread > 0 ? "\(unread) unread" : "Nothing unread")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.muted)
                        if unread > 0, inbox.mail[tab.id] != nil {
                            Text(tab.built == nil ? "Open Gmail once and they'll show here." : "Show your inbox in the pin and they'll show here.")
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.trailing, 40)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { if let latest { open(latest) } else { show() } }
            CardButton(symbol: "plus", help: "New Email", act: compose)
                .offset(x: 2, y: 2)
        }
        .task { await inbox.refresh(tab) }
    }

    private func show() {
        GlanceHover.shared.dismiss()
        browser.select(tab)
    }

    /// In the pinned tab, which is Gmail's already.
    private func open(_ mail: Inbox.Mail) {
        show()
        if let link = mail.link { tab.go(to: link) } else if mail.row != nil { inbox.open(mail, in: tab) }
    }

    /// Gmail's own compose, over the inbox, in the pin.
    private func compose() {
        show()
        if let url = URL(string: "https://mail.google.com/mail/u/\(Inbox.account(tab.address))/#inbox?compose=new") {
            tab.go(to: url)
        }
    }
}

/// The calendar: the next meeting, how soon, Join if it has a call; then
/// the rest of today.
private struct CalendarCard: View {
    let browser: Browser
    @ObservedObject private var meetings = Meetings.shared

    var body: some View {
        switch meetings.access {
        case .unasked:
            VStack(alignment: .leading, spacing: 8) {
                Text("Your next meeting, here")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("And how soon it is, on the pin. Read from the calendars on this Mac; nothing leaves it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Pill("Show My Meetings", filled: true) { meetings.ask() }
                    .padding(.top, 2)
            }
        case .refused:
            VStack(alignment: .leading, spacing: 8) {
                Text("Calendars are off")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Allow \(Store.name) in System Settings › Privacy & Security › Calendars.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Pill("Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .padding(.top, 2)
            }
        case .granted:
            if let next = meetings.next {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(next.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if let left = Meetings.countdown(to: next, now: meetings.now) {
                                Text(left == "now" ? "now" : "in \(left)")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(Palette.muted)
                            }
                        }
                        HStack(alignment: .center, spacing: 8) {
                            Text(Meetings.span(next))
                                .font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(Palette.muted)
                            Spacer(minLength: 0)
                            if let join = next.join {
                                Pill("Join", filled: next.start.timeIntervalSince(meetings.now) <= Meetings.joinAhead) {
                                    GlanceHover.shared.dismiss()
                                    browser.open(join, foreground: true)
                                }
                                .fixedSize()
                            }
                        }
                    }
                    let later = Array(meetings.upcoming.filter { $0.id != next.id }.prefix(3))
                    if !later.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(later) { meeting in
                                HStack(spacing: 8) {
                                    Text(meeting.start, format: .dateTime.hour().minute())
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(Palette.muted)
                                        .frame(width: 44, alignment: .leading)
                                    Text(meeting.title)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(Palette.ink.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 9)
                        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing else today")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(meetings.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted)
                }
            }
        }
    }
}

// MARK: - Join

/// Over the column's foot, a few minutes before a meeting with a call, and
/// while it's on: what it is, how soon, and Join. Only with a calendar
/// pinned in the window, as the countdown is.
struct MeetingRow: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var meetings = Meetings.shared
    @State private var hovering = false

    static func shows(_ browser: Browser) -> Bool {
        Meetings.shared.joinable != nil && browser.tabs.contains { $0.pin != nil && GlanceKind.of($0.address) == .calendar }
    }

    var body: some View {
        if MeetingRow.shows(browser), let meeting = meetings.joinable, let join = meeting.join {
            HStack(spacing: 10) {
                Image(systemName: "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(meeting.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(Meetings.countdown(to: meeting, now: meetings.now).map { $0 == "now" ? "Now" : "In \($0)" } ?? "Soon")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 4)
                if hovering {
                    Button { withAnimation(Motion.settle) { meetings.dismiss(meeting) } } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(PressStyle())
                    .help("Not this one")
                    .transition(.opacity)
                }
                Pill("Join", filled: true) { browser.open(join, foreground: true) }
            }
            .padding(.horizontal, 10)
            .frame(height: MeetingRow.height)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.ink.opacity(0.07)))
            .onHover { on in withAnimation(Motion.quick) { hovering = on } }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    static let height: CGFloat = 44
}
