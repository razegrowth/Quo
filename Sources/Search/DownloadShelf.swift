import AppKit
import SwiftUI
import UniformTypeIdentifiers

// A download's card in the column, as Arc has one: it rises over the foot
// as the file starts coming in, says how far it is, and once it is in says
// so — then waits a moment for you to open it, show it in Finder or drag it
// out to the Desktop or another app, and goes back down into the foot's
// Downloads button. The button stays where it was for the whole list.
//
// What is shown: this window's downloads still running (paused and failed
// ones too, with Resume or Retry), then the ones that just came in. Three at
// most, then a line for the rest, which opens the list.
//
// The cards wear the column's own translucent greys, so a space's colour
// shows through them, and move on the app's springs (Motion).

struct DownloadShelf: View {
    @ObservedObject var browser: Browser
    @ObservedObject var fetches: Fetches
    @ObservedObject var prefs: Preferences

    static let gap: CGFloat = 6
    static let most = 3

    @MainActor static func cardHeight(_ prefs: Preferences) -> CGFloat { prefs.roomyTabs ? 52 : 44 }

    /// One card each, running ones first.
    enum Card: Identifiable, Equatable {
        case running(FetchEntry)
        case arrived(Fetches.Arrival)

        var id: UUID {
            switch self {
            case .running(let entry): return entry.id
            case .arrived(let arrival): return arrival.id
            }
        }

        static func == (a: Card, b: Card) -> Bool {
            switch (a, b) {
            case (.running(let x), .running(let y)): return x === y
            case (.arrived(let x), .arrived(let y)): return x == y
            default: return false
            }
        }
    }

    @MainActor static func cards(_ browser: Browser, _ fetches: Fetches) -> [Card] {
        let mine = ObjectIdentifier(browser)
        // Only once it has somewhere to go: while the save panel asks where,
        // nothing is coming in yet, and its name is only a guess.
        let running = fetches.entries.filter { ($0.owner === browser || $0.owner == nil) && $0.destination != nil }
            .map(Card.running)
        let arrived = fetches.arrivals.filter { $0.owner == mine }.reversed().map(Card.arrived)
        return running + arrived
    }

    /// How tall it stands over the foot, for the rows to stop short of.
    @MainActor static func height(_ browser: Browser, _ fetches: Fetches) -> CGFloat {
        let all = cards(browser, fetches)
        guard !all.isEmpty else { return 0 }
        let shown = min(all.count, most)
        var height = CGFloat(shown) * (cardHeight(browser.prefs) + gap)
        if all.count > most { height += 22 + gap }
        return height + gap + 2
    }

    var body: some View {
        let all = DownloadShelf.cards(browser, fetches)
        VStack(spacing: DownloadShelf.gap) {
            ForEach(all.prefix(DownloadShelf.most)) { card in
                Group {
                    switch card {
                    case .running(let entry):
                        RunningCard(browser: browser, entry: entry, height: DownloadShelf.cardHeight(prefs))
                    case .arrived(let arrival):
                        ArrivedCard(browser: browser, fetches: fetches, arrival: arrival, height: DownloadShelf.cardHeight(prefs))
                    }
                }
                .transition(DownloadShelf.coming)
            }
            if all.count > DownloadShelf.most {
                Button { browser.showDownloads(toggles: false) } label: {
                    Text("\(all.count - DownloadShelf.most) more")
                        .font(.system(size: prefs.roomyTabs ? 12 : 11, weight: .medium))
                        .foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .transition(.opacity)
            }
        }
        // Clear of the foot's buttons, as the rows are.
        .padding(.bottom, all.isEmpty ? 0 : DownloadShelf.gap + 2)
        .animation(Motion.settle, value: all)
    }

    /// In from just under itself, a touch small, as the foot gives it up;
    /// out down into the foot, smaller and fading, as if back into the
    /// Downloads button.
    static let coming: AnyTransition = .asymmetric(
        insertion: .offset(y: 14).combined(with: .scale(scale: 0.94, anchor: .bottom)).combined(with: .opacity),
        removal: .offset(y: 18).combined(with: .scale(scale: 0.9, anchor: .bottom)).combined(with: .opacity)
    )
}

/// The card's plate: the column's live grey under it, a step stronger under
/// the pointer, its corners the tabs'.
private struct CardPlate: ViewModifier {
    let hovering: Bool
    @Environment(\.greys) private var greys

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? greys.pinLive : greys.wash)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.05), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(Motion.quick, value: hovering)
    }
}

/// The file's own icon, as Finder draws it: the file itself once it is in,
/// its kind before.
private struct FileIcon: View {
    let file: URL?
    let name: String
    let side: CGFloat

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
    }

    private var image: NSImage {
        if let file, FileManager.default.fileExists(atPath: file.path) {
            return NSWorkspace.shared.icon(forFile: file.path)
        }
        let ending = (name as NSString).pathExtension
        let type = UTType(filenameExtension: ending) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

private struct RunningCard: View {
    @ObservedObject var browser: Browser
    @ObservedObject var entry: FetchEntry
    let height: CGFloat
    @State private var hovering = false
    /// When it began, and how much was in then, for the time left.
    @State private var began = Date()
    /// Three seconds in with nothing yet.
    @State private var waited = false

    private var roomy: Bool { browser.prefs.roomyTabs }

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(file: nil, name: entry.name, side: roomy ? 30 : 26)
                .opacity(entry.state == .failed ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.system(size: roomy ? 13.5 : 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if entry.state == .downloading || entry.state == .resuming {
                    Bar(fraction: entry.fraction)
                }
                Text(line)
                    .font(.system(size: roomy ? 11.5 : 10.5).monospacedDigit())
                    .foregroundStyle(entry.state == .failed ? Palette.unsafe : Palette.muted)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
            if hovering || entry.state != .downloading {
                action
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .modifier(CardPlate(hovering: hovering))
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.settle, value: entry.state)
        .onTapGesture { browser.showDownloads(toggles: false) }
        .contextMenu {
            if entry.canPause { Button("Pause") { browser.pauseDownload(entry) } }
            if entry.canResume { Button("Resume") { browser.resumeDownload(entry) } }
            Button("Cancel") { browser.cancelDownload(entry) }
            Divider()
            Button("Show All Downloads") { browser.showDownloads(toggles: false) }
        }
        .help(entry.name)
        .task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation(Motion.quick) { waited = true }
        }
    }

    @ViewBuilder
    private var action: some View {
        switch entry.state {
        case .paused:
            if entry.canResume { Round(icon: "play.fill", help: "Resume") { browser.resumeDownload(entry) } }
        case .failed:
            if entry.canResume { Round(icon: "arrow.clockwise", help: "Resume") { browser.resumeDownload(entry) } }
            else if entry.canRetry { Round(icon: "arrow.clockwise", help: "Try again") { browser.retryDownload(entry) } }
        default:
            Round(icon: "xmark", help: "Cancel") { browser.cancelDownload(entry) }
        }
    }

    /// "12.3 of 48 MB · 2 min left", or as much of it as is known.
    private var line: String {
        switch entry.state {
        case .paused: return "Paused · " + size(entry.completedBytes)
        case .pausing: return entry.stopping
        case .failed: return entry.errorDescription ?? "Failed"
        case .resuming: return "Resuming…"
        case .downloading:
            guard entry.totalBytes > 0 else {
                if entry.completedBytes > 0 { return size(entry.completedBytes) + " so far" }
                // Nothing in yet: a site still making the file (a folder
                // zipped on the server) says so after a moment.
                return waited ? "Waiting for the site…" : "Starting…"
            }
            var text = "\(number(entry.completedBytes, like: entry.totalBytes)) of \(size(entry.totalBytes))"
            let spent = Date().timeIntervalSince(began)
            if entry.completedBytes > 0, spent > 2 {
                let rate = Double(entry.completedBytes) / spent
                let left = Double(entry.totalBytes - entry.completedBytes) / max(rate, 1)
                text += " · " + remaining(left)
            }
            return text
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// The count alone, in the total's unit: "12.3 of 48 MB".
    private func number(_ bytes: Int64, like total: Int64) -> String {
        let style = ByteCountFormatter()
        style.countStyle = .file
        style.includesUnit = false
        let whole = ByteCountFormatter()
        whole.countStyle = .file
        style.allowedUnits = whole.string(fromByteCount: total).hasSuffix("GB") ? .useGB
            : whole.string(fromByteCount: total).hasSuffix("MB") ? .useMB : .useKB
        return style.string(fromByteCount: bytes)
    }

    private func remaining(_ seconds: Double) -> String {
        if seconds < 60 { return "\(max(1, Int(seconds.rounded()))) s left" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded())) min left" }
        return "\(Int((seconds / 3600).rounded())) h left"
    }
}

/// The thin bar under the name: how far it is, or a sweep when the size
/// isn't known.
private struct Bar: View {
    let fraction: Double?
    @State private var sweep = false

    var body: some View {
        GeometryReader { box in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.1))
                if let fraction {
                    Capsule()
                        .fill(Palette.ink.opacity(0.7))
                        .frame(width: max(4, box.size.width * min(1, max(0, fraction))))
                        .animation(.easeOut(duration: 0.25), value: fraction)
                } else {
                    Capsule()
                        .fill(Palette.ink.opacity(0.5))
                        .frame(width: box.size.width * 0.3)
                        .offset(x: sweep ? box.size.width * 0.7 : 0)
                        .onAppear {
                            guard !Motion.reduced else { return }
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sweep = true }
                        }
                }
            }
        }
        .frame(height: 3)
    }
}

private struct ArrivedCard: View {
    @ObservedObject var browser: Browser
    let fetches: Fetches
    let arrival: Fetches.Arrival
    let height: CGFloat
    @State private var hovering = false
    /// The icon's little hop as it lands, and the tick coming in after it.
    @State private var landed = false
    /// Its time on show, held while the pointer is on it.
    @State private var going: DispatchWorkItem?
    /// How long it has waited for a clearer name.
    @State private var waited: TimeInterval = 0

    /// How long a card stays once its file is in, the pointer away.
    static let stays: TimeInterval = 6
    /// And once a clearer name is offered on it.
    static let staysWithName: TimeInterval = 12

    @ObservedObject private var watching: Fetches
    private var suggested: String? { watching.suggestions[arrival.id] }

    init(browser: Browser, fetches: Fetches, arrival: Fetches.Arrival, height: CGFloat) {
        self.browser = browser
        self.fetches = fetches
        self.arrival = arrival
        self.height = height
        self.watching = fetches
    }

    private var roomy: Bool { browser.prefs.roomyTabs }

    var body: some View {
        HStack(spacing: 10) {
            FileIcon(file: arrival.file, name: arrival.name, side: roomy ? 30 : 26)
                .scaleEffect(landed ? 1 : 0.8)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: roomy ? 13 : 11, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.safe)
                        .background(Circle().fill(Palette.ground).padding(1))
                        .offset(x: 3, y: 3)
                        .scaleEffect(landed ? 1 : 0.2)
                        .opacity(landed ? 1 : 0)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(arrival.name)
                    .font(.system(size: roomy ? 13.5 : 12.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let suggested {
                    // A clearer name, by Apple Intelligence: offered, never taken
                    // on its own (DownloadNames).
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles").font(.system(size: roomy ? 9.5 : 8.5, weight: .medium))
                        Text("Rename to “\(suggested)”")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.system(size: roomy ? 11.5 : 10.5))
                    .foregroundStyle(Palette.muted)
                    .transition(.opacity)
                } else {
                    Text(hovering ? "Open, or drag it out" : "Downloaded · " + ByteCountFormatter.string(fromByteCount: arrival.bytes, countStyle: .file))
                        .font(.system(size: roomy ? 11.5 : 10.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            }
            Spacer(minLength: 0)
            if suggested != nil {
                Round(icon: "checkmark", help: "Rename it") { rename() }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            if hovering {
                HStack(spacing: 2) {
                    Round(icon: "magnifyingglass", help: "Show in Finder") { reveal() }
                    Round(icon: "xmark", help: "Put away") { fetches.putAway(arrival.id) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .modifier(CardPlate(hovering: hovering))
        .onHover { on in
            hovering = on
            on ? going?.cancel() : leave(after: 2.5)
        }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: suggested)
        // A name offered: a little longer on show, to be read.
        .onChange(of: suggested) { _, now in if now != nil, !hovering { leave(after: ArrivedCard.staysWithName) } }
        .onTapGesture { open() }
        // Dragged out like a file in Finder: to the Desktop, Mail, Slack.
        .onDrag { NSItemProvider(contentsOf: arrival.file) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { open() }
            Button("Show in Finder") { reveal() }
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([arrival.file as NSURL])
            }
            if let suggested { Button("Rename to “\(suggested)”") { rename() } }
            Divider()
            Button("Show All Downloads") { browser.showDownloads(toggles: false) }
            Button("Put Away") { fetches.putAway(arrival.id) }
        }
        .help(arrival.file.path)
        .onAppear {
            // The icon settles a beat after the card, the tick after it.
            withAnimation(Motion.reduced ? nil : .spring(response: 0.38, dampingFraction: 1).delay(0.08)) { landed = true }
            leave(after: ArrivedCard.stays)
        }
        .onDisappear { going?.cancel() }
    }

    private func leave(after seconds: TimeInterval) {
        going?.cancel()
        let work = DispatchWorkItem { [fetches, id = arrival.id] in
            MainActor.assumeIsolated {
                // Still reading the file for a clearer name: a little longer,
                // or the name would come to a card already gone.
                if fetches.naming.contains(id), waited < 20 {
                    waited += 2
                    leave(after: 2)
                    return
                }
                withAnimation(Motion.settle) { fetches.putAway(id) }
            }
        }
        going = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func open() {
        NSWorkspace.shared.open(arrival.file)
        withAnimation(Motion.settle) { fetches.putAway(arrival.id) }
    }

    private func reveal() {
        NSWorkspace.shared.activateFileViewerSelecting([arrival.file])
    }

    private func rename() {
        if fetches.takeSuggestion(arrival.id, loot: browser.loot) != nil {
            browser.announce("Renamed")
            leave(after: 2.5)
        } else {
            browser.announce("Couldn't rename it")
        }
    }
}

/// A small round button on a card.
private struct Round: View {
    let icon: String
    let help: String
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.ink.opacity(hovering ? 0.1 : 0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
        .help(help)
        .accessibilityLabel(help)
    }
}
