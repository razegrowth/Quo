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
// list of places under it. Only where it is drawn moves.
//
// As Dia has it: at rest, just the site, on nothing; under the pointer, a
// ground comes up under it with four buttons at its end — bookmark, split,
// copy the link, and the site menu, which holds what the site card did
// (the connection, print, zoom, the blocker, permissions and the rest); a
// click is to type, the whole address selected, with no card in the way.

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
    /// The corners of the field and its list while typed in: one card, as
    /// Dia's opens.
    static let openCorner: CGFloat = 10

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
                    Field(browser: browser, prefs: browser.prefs, tab: tab)
                } else {
                    Spacer(minLength: 0)
                }
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
        /// For Show the full address, which redraws the bar as it's switched.
        @ObservedObject var prefs: Preferences
        @ObservedObject var tab: Tab
        @State private var hovering = false
        @State private var shake: CGFloat = 0
        /// The site menu button, for the menu to hang from.
        @State private var menuAnchor = ViewAnchor.Box()
        /// The field's box, for the list to hang from (TabOffersPanel).
        @State private var boxAnchor = ViewAnchor.Box()
        @ObservedObject private var siteMenu = SiteCardPanel.state

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
            // The whole address, under the pointer: on the field alone, not
            // over its buttons, whose own tooltips it hid.
            .help(shown?.absoluteString ?? "")
            // The bar sits in the window's title bar: a press there that
            // SwiftUI didn't claim on the way down moved the window, so
            // holding and dragging over the address carried the window off.
            // The press is the bar's, to type in; the buttons keep theirs.
            .overlay {
                if !editing {
                    BarPress(trailing: tab.isWeb && (hovering || siteMenu.open || siteMenu.testHover) ? 112 : 0, press: begin)
                }
            }
            .overlay(alignment: .trailing) {
                // Dia's four, at the end of the field under the pointer, or
                // while the site menu hangs from it.
                if !editing, tab.isWeb, hovering || siteMenu.open || siteMenu.testHover {
                    tools.transition(.opacity)
                }
            }
            .animation(Motion.quick, value: hovering)
            .frame(height: AddressBar.field(browser.prefs))
            .background(ViewAnchor(box: boxAnchor))
            .onAppear { TabOffersPanel.barBox = boxAnchor }
            .contentShape(Field.shape)
            .onHover { hovering = $0 }
            // Over the address, a press and drag is to select it, never to
            // carry the window off: the bar lies in the title bar.
            .background(StillWindow(on: hovering || siteMenu.testHover))
            .onTapGesture(perform: begin)
            .contextMenu { menu }
            .offset(x: wobble)
            // An address that leads nowhere: the field shivers and stays.
            .onChange(of: browser.refusals) { _, _ in
                guard editing else { return }
                shake = 0
                withAnimation(.easeOut(duration: 0.5)) { shake = 1 }
            }
        }

        /// White over whatever the bar lies on, never a grey of its own: on
        /// the plain ground it lands a step lighter, as the opaque grey did,
        /// and on a space's colour or gradient it takes the tint, where the
        /// grey sat on it as a slab (as the column's rows do, see Greys).
        /// Typing, it is the page's own ground, nearly solid, so the text
        /// sits on something steady, with the colour just showing through.
        /// At rest, nothing under the site but the bar; the ground comes up
        /// under the pointer, as Dia's does.
        @ViewBuilder
        private var ground: some View {
            let up = editing || hovering || siteMenu.open || siteMenu.testHover
            if editing && !browser.tabOffers.isEmpty {
                // Its list open under it: the top of one card with it, the
                // page's ground, square at the bottom, the line under it
                // the one between the two.
                let open = UnevenRoundedRectangle(cornerRadii: .init(topLeading: AddressBar.openCorner, bottomLeading: 0,
                                                                     bottomTrailing: 0, topTrailing: AddressBar.openCorner),
                                                  style: .continuous)
                open.fill(Palette.ground)
                    .overlay { open.strokeBorder(Palette.hairline, lineWidth: 1) }
            } else {
                let fill: Color = editing ? Palette.ground.opacity(0.88) : up ? Field.lifted : .clear
                Field.shape
                    .fill(fill)
                    .overlay {
                        Field.shape.strokeBorder(editing ? Palette.faint : up ? Field.rim : .clear, lineWidth: editing ? 1 : 0.5)
                    }
            }
        }

        /// Bookmark the page, split it, copy its link, and the site menu.
        private var tools: some View {
            HStack(spacing: 2) {
                BarTool(symbol: browser.pageKept ? "bookmark.fill" : "bookmark",
                        help: browser.pageKept ? "Edit This Bookmark" : "Bookmark This Page") {
                    browser.bookmarkCurrent()
                }
                if browser.prefs.splitView {
                    BarTool(symbol: "rectangle.split.2x1", help: browser.split(for: tab) == nil ? "Open in Split View" : "Add to Split View") {
                        browser.openInSplit(tab)
                    }
                }
                BarTool(symbol: "link", help: "Copy Link") { browser.copyAddress() }
                BarTool(symbol: "slider.horizontal.3", help: "Site Menu", lit: siteMenu.open) {
                    guard let button = menuAnchor.view else { return }
                    SiteCardPanel.toggleMenu(for: tab, in: browser, under: button)
                }
                .background(ViewAnchor(box: menuAnchor))
                .onAppear { if Store.testing { SiteCardPanel.state.anchor = menuAnchor } }
            }
            .padding(.trailing, 4)
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
            SiteCardPanel.hide()
            // A new tab has its field over the page already.
            if tab.isBlank || tab.shownURL == nil { browser.edit() } else {
                // To type, the whole address selected: the site's things are
                // behind the site menu button, not in a card in the way.
                SiteCardPanel.quietNext = true
                browser.beginTabEdit(tab)
            }
        }

        @ViewBuilder
        private var line: some View {
            if let url = shown, let rest = AtRest.of(url), rest.kind == .secure || rest.kind == .notSecure {
                // The whole address, the site in ink and the rest dim; or,
                // with Show the full address off, the site alone, as Dia has
                // it, the rest a click away and in the tooltip.
                HStack(spacing: 0) {
                    AtRestLine(rest: rest, size: size)
                        .layoutPriority(1)
                    if prefs.barFullAddress {
                        Text(AddressBar.after(url))
                            .font(.system(size: size))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
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

/// One of the address bar's buttons under the pointer: a mark, a ground
/// under the pointer or while what it opened is up.
private struct BarTool: View {
    let symbol: String
    let help: String
    var lit = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(hovering || lit ? Palette.ink : Palette.muted)
                .frame(width: 24, height: 22)
                .background(Palette.ink.opacity(hovering || lit ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The AppKit view under a SwiftUI one, for a window to hang from it.
struct ViewAnchor: NSViewRepresentable {
    final class Box { weak var view: NSView? }
    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}

/// The address bar's press: begins the edit on the way down, and never lets
/// the window be dragged from the bar (it lies in the title bar). Only a
/// plain left press is taken; hovering, right-clicks and the buttons at the
/// bar's end (`trailing`) go on to what's under it.
struct BarPress: NSViewRepresentable {
    var trailing: CGFloat
    let press: () -> Void

    func makeNSView(context: Context) -> Press { Press() }

    func updateNSView(_ view: Press, context: Context) {
        view.trailing = trailing
        view.press = press
    }

    final class Press: NSView {
        var trailing: CGFloat = 0
        var press: () -> Void = {}

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// A press asked about by the bench (`hit` … `press`), with no event.
        @MainActor static var probing = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            let pressed = Press.probing || NSApp.currentEvent.map {
                $0.type == .leftMouseDown && $0.modifierFlags.intersection([.command, .control, .option]).isEmpty
            } == true
            guard pressed else { return nil }
            let inside = convert(point, from: superview)
            guard inside.x <= bounds.width - trailing else { return nil }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) { press() }
    }
}

/// Under something in the title bar that takes its own presses (an
/// extension's button, the address bar): the window held still while the
/// pointer is over it, so a drag there is the thing's, not the window's —
/// the window server starts moving a window before the app sees the
/// press. Takes no clicks itself, and is told of the pointer by the thing's
/// own hover: a tracking area of its own took the hover from the button,
/// which then never lit up.
struct StillWindow: NSViewRepresentable {
    let on: Bool
    func makeNSView(context: Context) -> Still { Still() }
    func updateNSView(_ view: Still, context: Context) { view.hold(on) }

    final class Still: NSView {
        private var over: NSWindow?

        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            hold(false)
            super.viewWillMove(toWindow: newWindow)
        }

        func hold(_ on: Bool) {
            if on, over == nil, let window {
                over = window
                DragStrip.hold(window, true)
            } else if !on, let window = over {
                over = nil
                DragStrip.hold(window, false)
            }
        }
    }
}

