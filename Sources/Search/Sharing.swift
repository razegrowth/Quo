import AppKit
import SwiftUI

// File › Share…: the page, wherever the Mac would send it — Mail, Messages,
// AirDrop, Notes, anything else registered. Safari has a button for this on
// its toolbar; this app has no toolbar, so it lives in the File menu instead.

extension Browser {
    /// With no button to open under, the picker opens from the top right
    /// corner of the page, about where Safari keeps its Share button: just
    /// under the row when the tabs are across the top, and beside the
    /// column's page otherwise. The window's own corner is the fallback.
    func share() {
        guard let url = active?.address, let window = self.window ?? Links.window,
              let view = active?.built.flatMap({ $0.window === window ? $0 : nil }) ?? window.contentView
        else { return }
        // A few points in from the corner, so the arrow points at the page
        // rather than at its edge. Flipped or not, the picker hangs below.
        let inset: CGFloat = 12
        let y = view.isFlipped ? inset : view.bounds.maxY - inset
        let anchor = NSRect(x: view.bounds.maxX - inset, y: y, width: 1, height: 1)
        let picker = NSSharingServicePicker(items: [url])
        let delegate = SendPicker(extra: sharingServices(for: active))
        SendPicker.current = delegate
        picker.delegate = delegate
        picker.show(relativeTo: anchor, of: view, preferredEdge: view.isFlipped ? .maxY : .minY)
    }
}

// Send to your iPhone (or another Mac): the page, through sync, to open
// there (SyncTabs.swift). In the tab menu, File › Share… and its own File
// menu item, and the command bar.

extension Browser {
    /// A tab's page as it can be sent: a web page, never a private tab's,
    /// a pin's own, nor one a script or an agent opened or works in, as
    /// open-tab sync leaves those out (Sync.openTabs).
    func sendable(_ tab: Tab) -> URL? {
        guard !tab.shy, !tab.bench, !tab.agent, !tab.popup, !isPopup,
              let url = tab.address, SyncTabs.handed(url.absoluteString) else { return nil }
        if let group = tab.groupID, tabGroups.contains(where: { $0.id == group && $0.agent != nil }) { return nil }
        return url
    }

    /// The devices this window's pages can go to.
    var sendTargets: [TabTarget] { Sync.shared.targets(profileID) }

    func send(_ tab: Tab, to target: TabTarget) {
        guard let url = sendable(tab) else { return }
        Sync.shared.send(url, title: tab.label, to: target, profile: profileID)
        announce("Sent to \(target.name)")
    }

    /// The command bar's: the page in front, to the device heard from last.
    func sendFront() {
        guard let tab = active, sendable(tab) != nil else { return announce("This page can\u{2019}t be sent") }
        guard let target = sendTargets.first else { return announce("No other device to send to") }
        send(tab, to: target)
    }

    /// File › Share…'s picker with Send to each device at its top.
    func sharingServices(for tab: Tab?) -> [NSSharingService] {
        guard let tab, sendable(tab) != nil else { return [] }
        return sendTargets.map { target in
            let symbol = NSImage(systemSymbolName: target.phone ? "iphone" : "laptopcomputer", accessibilityDescription: nil) ?? NSImage()
            return NSSharingService(title: "Send to \(target.label)", image: symbol, alternateImage: nil) { [weak self, weak tab] in
                guard let self, let tab else { return }
                self.send(tab, to: target)
            }
        }
    }
}

/// Adds Send to each device to the system's Share picker.
final class SendPicker: NSObject, NSSharingServicePickerDelegate {
    /// Kept while a picker is open: the picker holds its delegate weakly.
    @MainActor static var current: SendPicker?
    let extra: [NSSharingService]
    init(extra: [NSSharingService]) { self.extra = extra }

    func sharingServicePicker(_ picker: NSSharingServicePicker, sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        extra + proposed
    }
}

/// File's Send to: one device a button, more a menu.
struct SendMenuItems: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var sync = Sync.shared

    var body: some View {
        let targets = browser.sendTargets
        let tab = browser.active
        let can = tab.flatMap { browser.sendable($0) } != nil
        if targets.count > 1 {
            Menu("Send to Device") {
                ForEach(targets) { target in
                    Button(target.label) { if let tab { browser.send(tab, to: target) } }
                }
            }
            .disabled(!can)
        } else {
            Button(targets.first.map { "Send to \($0.name)" } ?? "Send to Device") {
                if let tab, let target = targets.first { browser.send(tab, to: target) }
            }
            .shortcut("file.sendToDevice")
            .disabled(!can || targets.isEmpty)
        }
    }
}
