import SwiftUI
import UIKit
import WebKit

/// What a long press on a link offers: open it in a new tab, behind the
/// page, or in Incognito; copy, share, or send it to your Mac. What WebKit
/// offers for an image under the link (save, copy) stays, below.
@MainActor
enum LinkMenu {
    static func menu(for url: URL, in tab: Tab, suggested: [UIMenuElement]) -> UIMenu {
        var open: [UIMenuElement] = [
            UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                tab.openLink?(url, true, tab.incognito)
            },
            UIAction(title: "Open in Background", image: UIImage(systemName: "square.on.square")) { _ in
                tab.openLink?(url, false, tab.incognito)
                Haptics.tap()
                Browser.shared.say(tab.incognito ? "Opened in a new Incognito tab" : "Opened in a new tab")
            },
        ]
        if !tab.incognito {
            open.append(UIAction(title: "Open in Incognito", image: UIImage(systemName: "eyeglasses")) { _ in
                tab.openLink?(url, true, true)
            })
        }

        var keep: [UIMenuElement] = [
            UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                UIPasteboard.general.url = url
                Haptics.tap()
            },
            UIAction(title: "Share\u{2026}", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                share(url)
            },
        ]
        if ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            keep.append(UIAction(title: "Download Linked File", image: UIImage(systemName: "arrow.down.circle")) { _ in
                Downloads.shared.start(url, in: tab)
            })
        }
        let sync = MacSync.shared
        let targets = sync.on ? sync.targets : []
        if !tab.incognito, !targets.isEmpty {
            let send = { (target: TabTarget) in
                sync.send(url, title: "", to: target)
                Haptics.done()
                Browser.shared.say("Sent to \(target.name)")
            }
            if targets.count == 1, let only = targets.first {
                keep.append(UIAction(title: "Send to \(only.name)", image: UIImage(systemName: "laptopcomputer.and.arrow.down")) { _ in send(only) })
            } else {
                keep.append(UIMenu(title: "Send to Mac", image: UIImage(systemName: "laptopcomputer.and.arrow.down"),
                                   children: targets.map { target in
                                       UIAction(title: target.name, image: UIImage(systemName: target.phone ? "iphone" : "laptopcomputer")) { _ in send(target) }
                                   }))
            }
        }

        var children: [UIMenuElement] = [
            UIMenu(options: .displayInline, children: open),
            UIMenu(options: .displayInline, children: keep),
        ]
        let image = suggested.filter(isImageAction)
        if !image.isEmpty { children.append(UIMenu(options: .displayInline, children: image)) }
        return UIMenu(title: Address.shown(url), children: children)
    }

    /// WebKit's own actions for an image: kept. Its link ones are Quo's here.
    private static func isImageAction(_ element: UIMenuElement) -> Bool {
        guard let action = element as? UIAction else { return false }
        let id = action.identifier.rawValue.lowercased()
        return id.contains("image") || id.contains("photo") || id.contains("savetophotos")
    }

    private static func share(_ url: URL) {
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        Dialogs.top?.present(sheet, animated: true)
    }
}

/// The page behind a long-pressed link, loading live in the preview, with
/// the tab's own sign-ins. Tapping it opens the page in the tab. Where
/// Apple Intelligence is, two or three sentences of what it says sit under
/// it (PageSummary: read without your cookies, as the Mac's does).
final class LinkPreview: UIViewController {
    let web: WKWebView
    private let url: URL
    private let store: WKWebsiteDataStore
    private var summary: PageSummary?
    /// The room the held page has: its window, so the preview is sized to
    /// where Quo is shown, not the whole display.
    private let room: CGSize

    init(url: URL, store: WKWebsiteDataStore, desktop: Bool, room: CGSize) {
        self.url = url
        self.store = store
        self.room = room
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.preferredContentMode = desktop ? .desktop : .mobile
        web = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
        Blocker.shared.tune(config.userContentController, for: url.host())
        web.load(URLRequest(url: url))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        web.backgroundColor = .systemBackground
        web.isOpaque = false
        let bounds = room
        guard AppSettings.shared.linkSummaries, OnDevice.available else {
            view = web
            preferredContentSize = CGSize(width: bounds.width, height: bounds.height * 0.48)
            return
        }
        let page = PageSummary(url: url)
        summary = page
        page.read(url, store: store)
        let holder = UIView()
        holder.backgroundColor = .systemBackground
        let card = UIHostingController(rootView: SummaryCard(page: page, showsTitle: false).padding(10))
        card.view.backgroundColor = .clear
        card.sizingOptions = .intrinsicContentSize
        addChild(card)
        for part in [web, card.view!] {
            part.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(part)
        }
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: holder.topAnchor),
            web.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: card.view.topAnchor),
            card.view.leadingAnchor.constraint(equalTo: holder.leadingAnchor),
            card.view.trailingAnchor.constraint(equalTo: holder.trailingAnchor),
            card.view.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
        ])
        card.didMove(toParent: self)
        view = holder
        preferredContentSize = CGSize(width: bounds.width, height: bounds.height * 0.52)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        summary?.cancel()
    }
}
