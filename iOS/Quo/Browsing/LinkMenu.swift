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
/// the tab's own sign-ins. Tapping it opens the page in the tab.
final class LinkPreview: UIViewController {
    let web: WKWebView

    init(url: URL, store: WKWebsiteDataStore, desktop: Bool) {
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
        view = web
        let bounds = UIScreen.main.bounds
        preferredContentSize = CGSize(width: bounds.width, height: bounds.height * 0.48)
    }
}
