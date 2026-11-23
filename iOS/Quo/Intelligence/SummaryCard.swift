import SwiftUI
import WebKit

/// A page's summary as it's made: the site, the title, lines shimmering
/// while it's read, then two or three sentences coming into focus. Under a
/// held link's preview, and over a held card in the tab switcher.
@MainActor
final class PageSummary: ObservableObject {
    @Published private(set) var title: String
    let site: String
    @Published private(set) var summary: String?
    @Published private(set) var failed: String?
    @Published private(set) var reading = true
    private var job: Task<Void, Never>?

    /// Summaries already made, by address, while Quo is open.
    private static var known: [URL: (title: String, summary: String?, failed: String?)] = [:]

    init(url: URL, title: String? = nil) {
        let host = url.host() ?? ""
        site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        self.title = title ?? site
    }

    /// A link's page, read as PageReader reads it.
    func read(_ url: URL, store: WKWebsiteDataStore?) {
        if let had = Self.known[url] { return settle(had.title, had.summary, had.failed) }
        job = Task { [weak self] in
            let read = await PageReader.readForSummary(url, store: store)
            guard !Task.isCancelled, let self else { return }
            let title = read.title ?? self.title
            withAnimation(Q.quick) { self.title = title }
            guard read.failed == nil else { return self.settle(title, nil, read.failed, url: url) }
            var said = await OnDevice.summary(title: title, host: self.site, text: read.text)
            if said == nil { said = read.description }
            guard !Task.isCancelled else { return }
            self.settle(title, said, said == nil ? "Nothing to say about this page" : nil, url: url)
        }
    }

    /// A page already open in a tab: its own text, as you see it.
    func read(text: String, title: String) {
        self.title = title
        job = Task { [weak self] in
            guard let self else { return }
            let said = await OnDevice.summary(title: title, host: self.site, text: text)
            guard !Task.isCancelled else { return }
            self.settle(title, said, said == nil ? "Nothing to say about this page" : nil)
        }
    }

    func cancel() { job?.cancel() }

    private func settle(_ title: String, _ summary: String?, _ failed: String?, url: URL? = nil) {
        if let url { Self.known[url] = (title, summary, failed); if Self.known.count > 40 { Self.known.removeAll() } }
        withAnimation(Q.settle) {
            self.title = title
            self.summary = summary
            self.failed = failed
            reading = false
        }
    }
}

struct SummaryCard: View {
    @ObservedObject var page: PageSummary
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SiteMark(host: page.site, size: 16)
                Text(page.site)
                    .font(Q.footnote.weight(.medium))
                    .foregroundStyle(Q.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(page.reading ? AnyShapeStyle(Glow.gradient(angle: .degrees(30))) : AnyShapeStyle(Q.muted))
                    .symbolEffect(.pulse, options: .repeating, isActive: page.reading)
            }
            if showsTitle {
                Text(page.title)
                    .font(Q.bodyEmphasis)
                    .foregroundStyle(Q.ink)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
            Group {
                if let failed = page.failed {
                    Text(failed).font(Q.footnote).foregroundStyle(Q.muted).transition(.unblur)
                } else if page.reading {
                    Shimmer().transition(.opacity)
                } else if let summary = page.summary {
                    Text(summary)
                        .font(Q.footnote)
                        .foregroundStyle(Q.ink.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.unblur)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Q.sheet, in: RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Q.radiusLG, style: .continuous).strokeBorder(Q.hairline))
        .overlay { Glow(on: page.reading, radius: Q.radiusLG) }
        .accessibilityElement(children: .combine)
    }
}

/// Lines where the summary will be, a light running across them.
struct Shimmer: View {
    var body: some View {
        TimelineView(.animation) { time in
            let phase = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            GeometryReader { space in
                let band = space.size.width * 0.55
                Rectangle()
                    .fill(Q.ink.opacity(0.08))
                    .overlay {
                        LinearGradient(colors: [.clear, Glow.colours[1].opacity(0.5), Glow.colours[3].opacity(0.5), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: band)
                            .offset(x: -band + (space.size.width + band) * phase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .mask(lines(space.size.width))
            }
        }
        .frame(height: 8 * 3 + 7 * 2)
    }

    private func lines(_ width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach([1.0, 0.92, 0.58], id: \.self) { part in
                Capsule().frame(width: width * part, height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Apple Intelligence's colours running round the edge while it reads.
struct Glow: View {
    let on: Bool
    var radius: CGFloat = 16
    static let colours: [Color] = [
        Color(red: 1.00, green: 0.62, blue: 0.36), Color(red: 1.00, green: 0.42, blue: 0.62),
        Color(red: 0.74, green: 0.45, blue: 1.00), Color(red: 0.36, green: 0.62, blue: 1.00),
        Color(red: 1.00, green: 0.62, blue: 0.36),
    ]

    static func gradient(angle: Angle) -> AngularGradient {
        AngularGradient(colors: colours, center: .center, angle: angle)
    }

    var body: some View {
        TimelineView(.animation(paused: !on)) { time in
            let angle = Angle.degrees(time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3) / 3 * 360)
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.strokeBorder(Self.gradient(angle: angle), lineWidth: 1.5)
                shape.stroke(Self.gradient(angle: angle), lineWidth: 6).blur(radius: 10).opacity(0.5)
            }
        }
        .opacity(on ? 1 : 0)
        .animation(Q.settle, value: on)
        .allowsHitTesting(false)
    }
}

private struct Unblur: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    func body(content: Content) -> some View { content.blur(radius: radius).opacity(opacity) }
}

extension AnyTransition {
    /// Coming into focus: from a blur and nothing to sharp and there.
    static var unblur: AnyTransition {
        .modifier(active: Unblur(radius: 6, opacity: 0), identity: Unblur(radius: 0, opacity: 1))
    }
}
