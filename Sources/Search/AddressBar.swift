import SwiftUI

// The address bar: with the tabs down the side, a row above the page with
// back, forward and reload, the whole address of the page you're on, and the
// extensions' buttons at its far end, as Chrome and Dia have one.
//
// Off unless asked for (Settings › Tabs › Address bar above the page): the
// page gives up a strip of its height to it, and the address is otherwise a
// click on the tab you're on away. With it on, the three doors leave the
// column's top and the extensions leave its foot, so nothing is in two
// places. It goes with the column when it folds away (⌘S) and when a video
// takes the screen, as the bookmarks bar does.
//
// The field is the tab's own (TabAddressField): the same draft, the same
// list of places under it, the same site card. Only where it is drawn moves.

struct AddressBar: View {
    @ObservedObject var browser: Browser
    /// On the window's ground, above the page's card: the ground's colour and
    /// no line of its own, the card's edge being the line (see CardEdge).
    var onFrame = false

    /// The bar's height: the field as tall as a row of the column, with
    /// Roomier tabs as with the others, and 6 points above and below it.
    /// Beside the column of icons, a little tighter: 5 points, over tiles
    /// rather than rows.
    @MainActor static func height(_ prefs: Preferences) -> CGFloat { field(prefs) + (prefs.iconColumn ? 10 : 12) }
    /// The field's own height, a row of the column's (Preferences.sideRow),
    /// and a little shorter beside the column of icons, which has no rows.
    @MainActor static func field(_ prefs: Preferences) -> CGFloat {
        prefs.iconColumn ? (prefs.roomyTabs ? 32 : 26) : prefs.roomyTabs ? 36 : 28
    }
    /// Its text, a little larger with Roomier tabs, as the titles are.
    /// A touch under the titles' size: in a field on its own, the same size
    /// reads larger than it does in a row.
    @MainActor static func text(_ prefs: Preferences) -> CGFloat { prefs.roomyTabs ? 13.5 : 12.5 }
    /// The bar's buttons, back to the extensions: the column's 26 points,
    /// or 30 beside the roomier field.
    @MainActor static func door(_ prefs: Preferences) -> CGFloat { prefs.roomyTabs ? 30 : 26 }

    var body: some View {
        HStack(spacing: 8) {
            Helm(browser: browser, side: AddressBar.door(browser.prefs))
            // The bar turned off, with the column on the right: the row
            // only holds the window's buttons and the three doors, and the
            // window is dragged by the rest of it.
            if browser.bareRow {
                DragStrip()
            } else {
                if let tab = browser.active {
                    Field(browser: browser, tab: tab)
                } else {
                    Spacer(minLength: 0)
                }
                // A coding agent allowed in this window: its pill and Stop, at
                // the far end as across the top (AgentBanner).
                AgentStatus(browser: browser, style: .door)
                ExtensionSlot(browser: browser, edge: .bottom, side: AddressBar.door(browser.prefs))
            }
        }
        // The window's buttons at its start, with the column on the right.
        .padding(.leading, browser.lightsInAddressBar && !browser.fullScreen ? Metrics.sideLights : 8)
        .padding(.trailing, browser.lightsInAddressBar && browser.prefs.sidePosition == .right ? 10 : onFrame ? 0 : 8)
        .frame(height: AddressBar.height(browser.prefs))
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                onFrame ? Palette.frame : Palette.ground
                // The column's wash carried on under the bar, or the colour
                // stopped at its edge.
                SpaceWash(look: browser.wash, space: browser.washSpace)
            }
        }
        .overlay(alignment: .bottom) {
            if !onFrame { Rectangle().fill(Palette.hairline).frame(height: 1) }
        }
    }

    /// The address itself: at rest, the whole of it, the site in ink and the
    /// rest dim; clicked, or with ⌘L, the field.
    private struct Field: View {
        @ObservedObject var browser: Browser
        @ObservedObject var tab: Tab
        @State private var hovering = false
        @State private var shake: CGFloat = 0

        private var editing: Bool { browser.editingTab == tab.id && !browser.renamingTab }

        /// What the bar says: one of Search's own pages by its address, a
        /// web page by the document that arrived (Tab.restAddress), never by
        /// one only on its way, which the page that opened it could write
        /// into first.
        private var shown: URL? { tab.page?.url ?? tab.restAddress }

        private static let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        private var size: CGFloat { AddressBar.text(browser.prefs) }

        var body: some View {
            ZStack(alignment: .leading) {
                ground
                if editing {
                    TabAddressField(browser: browser, size: size)
                        .frame(height: size + 4)
                        .padding(.horizontal, 10)
                } else {
                    resting
                }
            }
            .frame(height: AddressBar.field(browser.prefs))
            .contentShape(Field.shape)
            .onHover { hovering = $0 }
            .onTapGesture(perform: begin)
            .contextMenu { menu }
            .offset(x: wobble)
            // An address that leads nowhere: the field shivers and stays.
            .onChange(of: browser.refusals) { _, _ in
                guard editing else { return }
                shake = 0
                withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
            }
            .help(shown?.absoluteString ?? "")
        }

        /// White over whatever the bar lies on, never a grey of its own: on
        /// the plain ground it lands a step lighter, as the opaque grey did,
        /// and on a space's colour or gradient it takes the tint, where the
        /// grey sat on it as a slab (as the column's rows do, see Greys).
        /// Typing, it is the page's own ground, nearly solid, so the text
        /// sits on something steady, with the colour just showing through.
        private var ground: some View {
            let fill: Color = editing ? Palette.ground.opacity(0.88) : hovering ? Field.lifted : Field.lift
            return Field.shape
                .fill(fill)
                .overlay {
                    Field.shape.strokeBorder(editing ? Palette.faint : Field.rim, lineWidth: editing ? 1 : 0.5)
                }
        }

        static let lift = shade(light: 0.55, dark: 0.07)
        static let lifted = shade(light: 0.8, dark: 0.11)
        /// A rim just short of seen, so the field has an edge on a colour
        /// close to its own.
        static let rim = Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 0, alpha: 0.05)
        })

        private static func shade(light: CGFloat, dark: CGFloat) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                NSColor(white: 1, alpha: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
            })
        }

        /// The address at rest, read out as one button: the whole address,
        /// pressed to edit it.
        private var resting: some View {
            line
                .padding(.horizontal, 10)
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(shown?.absoluteString ?? "Address")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { begin() }
        }

        private var wobble: CGFloat {
            guard shake != 0 else { return 0 }
            let swing: CGFloat = sin(shake * .pi * 6)
            return swing * 6 * (1 - shake)
        }

        @ViewBuilder
        private var menu: some View {
            if let url = shown {
                Button("Copy Address") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
                Button("Edit Address") { browser.beginTabEdit(tab) }
            }
        }

        private func begin() {
            guard !editing else { return }
            // A new tab has its field over the page already.
            if tab.isBlank || tab.shownURL == nil { browser.edit() } else { browser.beginTabEdit(tab) }
        }

        @ViewBuilder
        private var line: some View {
            if let url = shown, let rest = AtRest.of(url), rest.kind == .secure || rest.kind == .notSecure {
                HStack(spacing: 0) {
                    AtRestLine(rest: rest, size: size)
                        .layoutPriority(1)
                    Text(AddressBar.after(url))
                        .font(.system(size: size))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else if let url = shown, !tab.isBlank {
                Text(url.absoluteString)
                    .font(.system(size: size))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Search or enter address")
                    .font(.system(size: size))
                    .foregroundStyle(Palette.faint)
            }
        }
    }

    /// What follows the site and its port: the path, the query and the
    /// fragment, as they are written. A bare "/" alone is nothing to say.
    static func after(_ url: URL) -> String {
        var rest = url.path(percentEncoded: true)
        if let query = url.query(percentEncoded: true) { rest += "?" + query }
        if let fragment = url.fragment(percentEncoded: true) { rest += "#" + fragment }
        return rest == "/" ? "" : rest
    }
}
