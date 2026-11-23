import SwiftUI

// What rises from the window's foot to say something or ask something:
// "Password saved", "Save the password for…?", a site wanting the camera,
// an update that's ready. They were a small capsule of 12-point grey-on-white
// that was easy to miss, a password offer most of all. Now they share one
// card: larger words, an icon that says what kind of thing it is, buttons
// that look like buttons, and a shadow that lifts it off the page.

/// The card itself.
struct NoticeCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .padding(.vertical, 10)
            .background(NoticeCard.ground(scheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(scheme == .dark ? 0.16 : 0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.18), radius: 28, y: 12)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    /// A step lighter than a dark page, so it stands off it; white in Light.
    static func ground(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(white: 0.17) : Palette.ground
    }

    /// In from the foot, settling from just under its size.
    static var arrival: AnyTransition {
        .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .bottom))
    }
}

extension View {
    func noticeCard() -> some View { modifier(NoticeCard()) }
}

/// What kind of thing a notice is, at a glance, in a soft round tile.
struct NoticeIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .frame(width: 30, height: 30)
            .background(Palette.ink.opacity(0.08), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The words of a notice: a size up from the rest of the window's small
/// print, and medium, so they read before the page around them does.
struct NoticeText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        // As wide as the words, on one line where the window has room;
        // wrapped at 440 where it doesn't.
        ViewThatFits(in: .horizontal) {
            words.fixedSize()
            words
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440, alignment: .leading)
        }
    }

    private var words: some View {
        Text(text)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(Palette.ink)
    }
}

/// A notice's button: filled in ink for what it's there to offer, quiet
/// for the way out.
struct NoticeButton: View {
    let title: String
    var filled = false
    let action: () -> Void
    @State private var hovering = false

    init(_ title: String, filled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.filled = filled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: filled ? .semibold : .regular))
                .foregroundStyle(filled ? Palette.ground : Palette.ink.opacity(hovering ? 1 : 0.72))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(filled ? Palette.ink : (hovering ? Palette.hover : .clear), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Motion.quick, value: hovering)
    }
}

/// The line at the window's foot that says one thing and goes
/// (Browser.announce): its icon, its words, and a button when it has one
/// thing to offer, Show in Finder for a file or Restart for an update.
struct AnnouncementLine: View {
    let browser: Browser
    let text: String
    let symbol: String
    var file: URL? = nil
    var action: Browser.AnnouncedAction? = nil

    var body: some View {
        HStack(spacing: 12) {
            NoticeIcon(symbol: symbol)
            NoticeText(text)
            if let file {
                NoticeButton("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            if let action {
                NoticeButton("Later") { browser.dismissAnnouncement() }
                NoticeButton(action.title, filled: true) { action.run() }
            }
        }
        .padding(.trailing, file == nil && action == nil ? 6 : 0)
        .noticeCard()
        // Held up while the pointer is on it, so it can be read.
        .onHover { browser.holdAnnouncement($0) }
    }
}
