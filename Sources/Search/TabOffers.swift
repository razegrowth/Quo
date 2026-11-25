import AppKit
import Combine
import SwiftUI

// What the field in the tab offers as you type (#534): the same places, search
// and command as ⌘L's field, in a list under the tab, where the site card
// stands before anything is typed. The card is about the page you are on and
// goes as soon as you type; the list comes as it goes.
//
// Its own small window, as the card's is: under the field, whether the tabs
// are in the column or across the top, and never taking the keys — the caret
// stays in the tab, the arrow keys walk the list from there, and a click on a
// row is only a click.

@MainActor
enum TabOffersPanel {
    private static var panel: Panel?
    private static var host: Host?
    private static weak var anchor: NSView?
    private static var watching: [ObjectIdentifier: AnyCancellable] = [:]

    /// The field the address is being typed in. SwiftUI can make it more
    /// than once as the edit begins, so the list follows the latest one.
    static func follow(_ browser: Browser, anchor field: NSView) {
        anchor = field
        let key = ObjectIdentifier(browser)
        guard watching[key] == nil else { return }
        watching[key] = browser.$tabOffers
            .map(\.isEmpty)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak browser] empty in
                MainActor.assumeIsolated {
                    guard let browser else { return }
                    if empty || browser.editingTab == nil { hide() } else { show(browser, tries: 0) }
                }
            }
    }

    static var isShown: Bool { panel != nil }
    /// The address bar's own box (AddressBar.Field), for the list to hang
    /// from: under the bar, the two are one card, as Dia's is.
    static var barBox: ViewAnchor.Box?
    /// Where the list is, in screen points, while it is shown: for the bench.
    static var frame: NSRect? { panel?.frame }

    /// The list as drawn, for the bench: never on a screen it wasn't already on.
    static func picture(to path: String) -> Bool {
        guard let view = panel?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? data.write(to: URL(fileURLWithPath: path))) != nil
    }

    private static func show(_ browser: Browser, tries: Int) {
        guard panel == nil, !browser.tabOffers.isEmpty, browser.editingTab != nil else { return }
        // The field with the caret in it is the one on screen; failing that,
        // the latest one made, once it is in its window.
        let focused = (browser.window?.firstResponder as? NSTextView)?.delegate as? NSTextField
        guard let field = focused ?? anchor, let window = field.window else {
            if tries < 15 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { show(browser, tries: tries + 1) }
            }
            return
        }
        let spot = window.convertToScreen(field.convert(field.bounds, to: nil))
        // The address bar over the page: the list is the field's width,
        // its edges on the field's, as Safari, Chrome and Dia have it. Held
        // to the tab's size there, it sat short at the left under a field
        // the width of the window. (8 points of shadow room either side.)
        let barBox = browser.prefs.addressBar && browser.prefs.sidebar && spot.width > 460
            ? barBox?.view.flatMap { view in view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) } }
            : nil
        let bar = barBox != nil
        // Under a tab: as wide as the field and the card's margin either
        // side, within reason. Under the bar: the box's own width, its
        // sides on the box's, and 8 points of shadow room either side.
        let width = barBox.map { $0.width + 16 } ?? min(max(spot.width + 24, 320), 460)
        let host = Host(rootView: AnyView(TabOffersList(browser: browser, attached: bar).frame(width: width)))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        let panel = Panel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        // Under the address, lined up with the tab's own edge, as the card
        // is; over it for a tab too near the bottom of the screen. The list
        // has 8 points of clear room around it for its shadow.
        // Under the bar, its top on the box's bottom: one card.
        var origin = barBox.map { NSPoint(x: $0.minX - 8, y: $0.minY - size.height) }
            ?? NSPoint(x: spot.minX - 20, y: spot.minY + 2 - size.height)
        var above = false
        if let screen = window.screen?.visibleFrame {
            origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
            if origin.y < screen.minY + 8 {
                above = true
                origin.y = min(spot.maxY - 2, screen.maxY - size.height - 8)
            }
        }
        panel.setFrameOrigin(origin)
        // Fewer rows or more as you type, the edge nearest the field kept.
        host.onResize = { [weak panel] fitted in
            guard let panel, fitted.height > 0, panel.frame.size != fitted else { return }
            var frame = panel.frame
            if !above { frame.origin.y += frame.height - fitted.height }
            frame.size = fitted
            panel.setFrame(frame, display: true)
        }
        window.addChildWindow(panel, ordered: .above)
        self.panel = panel
        self.host = host
    }

    static func hide() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        self.panel = nil
        host = nil
    }

    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Takes the first click though its window never becomes key, and says
    /// when the list changes size.
    private final class Host: NSHostingView<AnyView> {
        var onResize: ((NSSize) -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func layout() {
            super.layout()
            let fitted = fittingSize
            let size = NSSize(width: ceil(fitted.width), height: ceil(fitted.height))
            guard size != frame.size else { return }
            DispatchQueue.main.async { [weak self] in self?.onResize?(size) }
        }
    }
}

/// The list itself, drawn as ⌘L's is.
private struct TabOffersList: View {
    @ObservedObject var browser: Browser
    /// Under the address bar: the lower part of one card with the field,
    /// square at the top, its line there the field's.
    var attached = false
    /// The list's travelling grounds (Omnibox.Row), and the row under the pointer.
    @Namespace private var rowGround
    @State private var hoveredRow: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(browser.tabOffers.enumerated()), id: \.element.id) { index, offer in
                Omnibox.Row(offer: offer, picked: browser.tabPicked == index, ground: rowGround, hovered: $hoveredRow)
                    .contentShape(Rectangle())
                    .onTapGesture { browser.takeTabOffer(offer) }
            }
        }
        .animation(Motion.glide, value: browser.tabPicked)
        .padding(m.listAir)
        .background(Palette.ground, in: shape)
        .overlay(
            shape.strokeBorder(Palette.hairline, lineWidth: 1)
                // Attached, the line between it and the field is the field's.
                .mask(VStack(spacing: 0) {
                    Color.clear.frame(height: attached ? 1 : 0)
                    Color.black
                })
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .padding(.top, attached ? 0 : 8)
        .shadow(color: .black.opacity(attached ? 0.16 : 0.1), radius: attached ? 14 : 10, y: attached ? 8 : 4)
        .environment(\.fieldMeasures, m)
    }

    private var shape: UnevenRoundedRectangle {
        let corner = attached ? AddressBar.openCorner : m.corner
        return UnevenRoundedRectangle(cornerRadii: .init(topLeading: attached ? 0 : corner, bottomLeading: corner,
                                                         bottomTrailing: corner, topTrailing: attached ? 0 : corner),
                                      style: .continuous)
    }

    /// A size up with Roomier tabs, as ⌘L's list is.
    private var m: FieldMeasures { FieldMeasures(roomy: browser.prefs.roomyTabs) }
}
