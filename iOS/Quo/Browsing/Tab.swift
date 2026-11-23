import Combine
import SwiftUI
import UIKit
import WebKit

/// One tab: its page, made when it's first shown, and what it's kept as
/// while it isn't.
@MainActor
final class Tab: ObservableObject, Identifiable {
    let id: UUID
    let incognito: Bool
    @Published var url: URL?
    @Published var title: String
    @Published var lastActive: Date
    @Published var thumbnail: UIImage?
    @Published private(set) var loading = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    /// What the page asked for that was blocked: ads and trackers in its
    /// markup, and click IDs taken off its address.
    @Published private(set) var blocked = 0
    @Published private(set) var scrubbed = 0
    /// Showing the page as it came, nothing blocked, until the next site.
    @Published private(set) var bare = false
    @Published var desktop = false
    @Published private(set) var themeColor: UIColor?
    @Published private(set) var pageColor: UIColor?
    /// What colours the strip under the status bar: the page's own.
    var topColor: UIColor { themeColor ?? pageColor ?? .systemBackground }
    /// Why the page couldn't be opened, shown in its place.
    @Published var failure: String?
    /// The page has a video of its own: Picture in Picture is offered.
    @Published private(set) var hasVideo = false
    /// What the page in front is, as its server said: a PDF or another file
    /// shown as it is can be downloaded from the toolbar.
    @Published private(set) var mimeType: String?
    /// The type of the page about to be shown, until it is.
    fileprivate var arriving: (url: URL?, type: String?)?
    var isDocument: Bool {
        guard let mimeType else { return false }
        return !["text/html", "application/xhtml+xml"].contains(mimeType)
    }

    /// Back and forward as WebKit keeps them, for a tab restored.
    var interactionState: Data?
    private(set) var web: WKWebView?
    private var watchers: [NSKeyValueObservation] = []
    private lazy var helper = TabHelper(tab: self)
    /// Told when the page scrolls, for the bottom bar.
    var onScroll: ((CGFloat, Bool) -> Void)?
    var lastOffset: CGFloat = 0

    init(id: UUID = UUID(), url: URL?, title: String = "", incognito: Bool = false, lastActive: Date = Date()) {
        self.id = id
        self.url = url
        self.title = title
        self.incognito = incognito
        self.lastActive = lastActive
    }

    var host: String? { url?.host() }
    var shownTitle: String { title.isEmpty ? Address.shown(url) : title }
    /// A shorter name from Apple's model, for the tab switcher (TabTitles).
    @Published var short: String?
    /// What the tab switcher calls it: the shorter name when there is one.
    var deckTitle: String { short ?? shownTitle }

    // MARK: - the page

    /// The page, made now if it wasn't: the address, or where it left off.
    func webView(store: WKWebsiteDataStore) -> WKWebView {
        if let web { return web }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: TabHelper.reportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: Media.script(keepPlaying: AppSettings.shared.playsInBackground),
                                              injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(helper, name: "quo")
        controller.add(helper, name: "quoMedia")
        config.userContentController = controller
        Blocker.shared.tune(controller, for: url?.host())

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = helper
        web.uiDelegate = helper
        web.isFindInteractionEnabled = true
        web.allowsLinkPreview = true
        web.isInspectable = true
        web.scrollView.contentInsetAdjustmentBehavior = .automatic
        web.allowsBackForwardNavigationGestures = Sites.shared.settings(for: url?.host()).swipe == .edges
        web.backgroundColor = .systemBackground
        self.web = web
        watch(web)
        if let state = interactionState {
            web.interactionState = state
            interactionState = nil
        } else if let url {
            web.load(URLRequest(url: url))
        }
        return web
    }

    private func watch(_ web: WKWebView) {
        watchers = [
            web.observe(\.title) { [weak self] web, _ in MainActor.assumeIsolated {
                guard let self, let title = web.title, !title.isEmpty else { return }
                self.title = title
                TabTitles.changed(self)
                if let url = web.url, !self.incognito {
                    History.shared.retitle(url, title)
                    Tabs.shared.saveSoon()
                }
            } },
            web.observe(\.url) { [weak self] web, _ in MainActor.assumeIsolated {
                guard let self, let url = web.url else { return }
                if Sites.key(url.host()) != Sites.key(self.url?.host()) { self.bare = false; self.blocked = 0 }
                self.url = url
                if !self.incognito { Tabs.shared.saveSoon() }
            } },
            web.observe(\.estimatedProgress) { [weak self] web, _ in MainActor.assumeIsolated { self?.progress = web.estimatedProgress } },
            web.observe(\.isLoading) { [weak self] web, _ in MainActor.assumeIsolated { self?.loading = web.isLoading } },
            web.observe(\.canGoBack) { [weak self] web, _ in MainActor.assumeIsolated { self?.canGoBack = web.canGoBack } },
            web.observe(\.canGoForward) { [weak self] web, _ in MainActor.assumeIsolated { self?.canGoForward = web.canGoForward } },
            web.observe(\.themeColor) { [weak self] web, _ in MainActor.assumeIsolated { self?.themeColor = web.themeColor } },
            web.observe(\.underPageBackgroundColor) { [weak self] web, _ in MainActor.assumeIsolated { self?.pageColor = web.underPageBackgroundColor } },
            web.scrollView.observe(\.contentOffset) { [weak self] scroll, _ in MainActor.assumeIsolated {
                guard let self else { return }
                let y = scroll.contentOffset.y + scroll.adjustedContentInset.top
                let delta = y - self.lastOffset
                self.lastOffset = y
                self.onScroll?(delta, scroll.isTracking || scroll.isDecelerating)
            } },
        ]
    }

    var isBuilt: Bool { web != nil }
    var webViewIfBuilt: WKWebView? { web }

    func load(_ url: URL) {
        self.url = url
        failure = nil
        if let web { web.load(URLRequest(url: url)) }
    }

    func goBack() { web?.goBack() }
    func goForward() { web?.goForward() }
    func reload() { if loading { web?.stopLoading() } else { web?.reload() } }

    /// The page as it came: nothing blocked, until it leaves this site.
    func showOriginal() {
        guard let web else { return }
        bare = true
        blocked = 0
        scrubbed = 0
        Blocker.shared.tune(web.configuration.userContentController, for: url?.host(), bare: true)
        web.reload()
    }

    func setDesktop(_ on: Bool) {
        desktop = on
        web?.customUserAgent = on ? Tab.desktopAgent : nil
        web?.reload()
    }

    static let desktopAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    var zoom: CGFloat {
        get { web?.pageZoom ?? 1 }
        set { web?.pageZoom = min(max(newValue, 0.5), 3) }
    }

    /// A picture of the page for the tab switcher.
    func snapshot() async {
        // Only of a page on screen: one already taken off it can come out
        // laid out at another size, and its card would then show it zoomed.
        guard let web, web.bounds.width > 0, web.window != nil else { return }
        let config = WKSnapshotConfiguration()
        // Half the page's width in points: at the screen's scale that's one
        // and a half pixels a point, sharp on a card, a quarter of the
        // memory of a full-size picture and quick to put on screen.
        config.snapshotWidth = NSNumber(value: Double(min(web.bounds.width, 430) / 2))
        if let image = try? await web.takeSnapshot(configuration: config) {
            thumbnail = image
            guard !incognito else { return }
            // Kept for next time, encoded and written off the main thread:
            // a JPEG takes long enough to cost the screen several frames.
            let url = Tab.thumbnailURL(id)
            nonisolated(unsafe) let shot = image
            Task.detached(priority: .utility) {
                if let data = shot.jpegData(compressionQuality: 0.6) { try? data.write(to: url) }
            }
        }
    }

    private static let thumbs: URL = {
        let folder = Store.folder.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static func thumbnailURL(_ id: UUID) -> URL {
        thumbs.appendingPathComponent(id.uuidString + ".jpg")
    }

    /// The picture from disk, read and decoded off the main thread, so
    /// opening the tab switcher never waits on it.
    func loadThumbnail() {
        guard thumbnail == nil, !loadingThumbnail else { return }
        loadingThumbnail = true
        let url = Tab.thumbnailURL(id)
        Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: url)).flatMap(UIImage.init(data:))?.preparingForDisplay()
            }.value
            guard let self else { return }
            loadingThumbnail = false
            if thumbnail == nil, let image { thumbnail = image }
        }
    }
    private var loadingThumbnail = false

    /// Whether the page has something to show yet: a tab not opened since
    /// Quo started has to load first.
    var hasDrawn: Bool {
        guard let web else { return false }
        return (web.estimatedProgress > 0 && !web.isLoading) || web.estimatedProgress > 0.5
    }

    /// Loaded: a fresh picture for its card while it's still on screen.
    fileprivate func finished() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            Task { await self?.snapshot() }
        }
    }

    /// Put away: the page closed, its place kept.
    func unload() {
        guard let web else { return }
        interactionState = web.interactionState as? Data
        web.configuration.userContentController.removeScriptMessageHandler(forName: "quo")
        web.configuration.userContentController.removeScriptMessageHandler(forName: "quoMedia")
        web.removeFromSuperview()
        watchers = []
        self.web = nil
    }

    func close() {
        unload()
        try? FileManager.default.removeItem(at: Tab.thumbnailURL(id))
    }

    // MARK: - from the helper

    fileprivate func pageReported(addresses: [String], icon: String?) {
        if !bare { blocked = Blocker.shared.count(addresses, on: url?.host()) }
        if let icon, let iconURL = URL(string: icon), let host = url?.host() {
            Favicons.shared.offer(iconURL, for: host)
        } else if let host = url?.host() {
            Favicons.shared.want(host)
        }
    }

    fileprivate func noteScrubbed(_ count: Int) { scrubbed += count }

    fileprivate func noteVideo(mainFrame: Bool) {
        if mainFrame, !hasVideo { hasVideo = true }
    }

    // MARK: - video and sound

    /// The page's video into Picture in Picture, or back out of it: the
    /// one playing, else the largest. Run from a tap, as a script the app
    /// runs counts as the person's own gesture.
    func pictureInPicture() {
        web?.evaluateJavaScript(Media.pictureInPicture) { result, error in
            MainActor.assumeIsolated {
                Trace.mark("pip \(String(describing: result)) \(String(describing: error))")
                if (result as? String)?.hasPrefix("no") == true { Browser.shared.say("This video can\u{2019}t play in picture in picture") }
            }
        }
    }

    /// Leaving Quo: which of the page's videos and sounds are playing.
    func noteMedia() { web?.evaluateJavaScript(Media.note, completionHandler: nil) }

    /// Left: those that were playing and were paused on the way out go on.
    func resumeMedia() { web?.evaluateJavaScript(Media.resume, completionHandler: nil) }

    fileprivate func failed(_ error: Error) {
        let error = error as NSError
        // A page left before it loaded, or a download taking over, isn't a failure.
        if error.code == NSURLErrorCancelled || error.domain == "WebKitErrorDomain" && error.code == 102 { return }
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL { self.url = url }
        failure = Tab.words(for: error)
    }

    static func words(for error: NSError) -> String {
        switch error.code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "There\u{2019}s no site at this address."
        case NSURLErrorNotConnectedToInternet: return "You\u{2019}re offline."
        case NSURLErrorTimedOut: return "The site took too long to answer."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateNotYetValid, NSURLErrorServerCertificateHasUnknownRoot:
            return "This site\u{2019}s connection isn\u{2019}t private."
        case NSURLErrorCannotConnectToHost: return "The site isn\u{2019}t answering."
        default: return error.localizedDescription
        }
    }

    func retry() {
        failure = nil
        if let url { webViewIfBuilt?.load(URLRequest(url: url)) }
    }

    fileprivate func committed(_ url: URL?) {
        failure = nil
        hasVideo = false
        // Back to a page kept in memory brings no response: a .pdf is a PDF.
        if let arriving, arriving.url == url { mimeType = arriving.type }
        else { mimeType = url?.pathExtension.lowercased() == "pdf" ? "application/pdf" : nil }
        arriving = nil
        guard let url else { return }
        if !incognito { History.shared.record(url, title: web?.title) }
        web?.allowsBackForwardNavigationGestures = Sites.shared.settings(for: url.host()).swipe == .edges
    }

    /// Opens another tab (a link with target=_blank, window.open).
    var openTab: ((URL, Bool) -> WKWebView?)?
    /// A long-pressed link opened in another tab: in front or behind, and
    /// whether in Incognito.
    var openLink: ((URL, _ front: Bool, _ incognito: Bool) -> Void)?
    var onDownload: ((WKDownload) -> Void)?
    /// A file the page asked for, to download with this tab's sign-ins.
    var onStartDownload: ((URLRequest) -> Void)?
}

/// The page's delegate, kept apart so the tab isn't retained by WebKit.
@MainActor
private final class TabHelper: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var tab: Tab?
    /// The last page asked for, to download from as it was asked.
    private var lastRequest: URLRequest?
    init(tab: Tab) { self.tab = tab }

    static let reportScript = """
    (function(){
      function report(){
        try {
          var urls = [];
          document.querySelectorAll('script[src],iframe[src],img[src]').forEach(function(e){ if (urls.length < 800) urls.push(e.src); });
          var icon = document.querySelector('link[rel~="apple-touch-icon"]') || document.querySelector('link[rel~="icon"]');
          window.webkit.messageHandlers.quo.postMessage({urls: urls, icon: icon ? icon.href : null});
        } catch (e) {}
      }
      report();
      setTimeout(report, 2500);
    })();
    """

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "quoMedia" {
            tab?.noteVideo(mainFrame: message.frameInfo.isMainFrame)
            return
        }
        guard let body = message.body as? [String: Any] else { return }
        tab?.pageReported(addresses: body["urls"] as? [String] ?? [], icon: body["icon"] as? String)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let tab, let url = action.request.url else { return (.allow, preferences) }
        if action.targetFrame?.isMainFrame ?? true { Trace.mark("decide \(url.host() ?? "")") }
        preferences.preferredContentMode = tab.desktop ? .desktop : .mobile
        // <a download>: started here, as WebKit's own hand-over to a
        // download never arrives (iOS 27), leaving the tab loading.
        if action.shouldPerformDownload {
            tab.onStartDownload?(action.request)
            return (.cancel, preferences)
        }
        if action.targetFrame?.isMainFrame ?? true { lastRequest = action.request }
        let scheme = url.scheme?.lowercased() ?? ""
        // Mail, phone, maps and the App Store: their own apps.
        if !["http", "https", "about", "data", "blob", "file", "javascript"].contains(scheme) {
            await UIApplication.shared.open(url)
            return (.cancel, preferences)
        }
        guard action.targetFrame?.isMainFrame ?? true else { return (.allow, preferences) }
        // Before each page, the site's blocking, as the Mac's Shield does.
        let site = Sites.shared.settings(for: url.host())
        let bare = tab.bare && Sites.key(url.host()) == Sites.key(tab.url?.host())
        Blocker.shared.tune(webView.configuration.userContentController, for: url.host(), bare: bare)
        if site.blockTrackers, !bare, let (clean, count) = Blocker.scrub(url) {
            tab.noteScrubbed(count)
            webView.load(URLRequest(url: clean))
            return (.cancel, preferences)
        }
        // A link to a site with an app of its own opens there when asked to.
        if action.navigationType == .linkActivated, AppSettings.shared.appLinks == .app,
           Sites.key(url.host()) != Sites.key(webView.url?.host()) {
            let opened = await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
            if opened { return (.cancel, preferences) }
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let attachment = (response.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased().hasPrefix("attachment") ?? false
        // A file to save, not show: what the page can't show, or what its
        // server sent as an attachment. Downloaded again from the request
        // that asked for it (its form and method kept), as WebKit's own
        // hand-over never arrives.
        if !response.canShowMIMEType || attachment {
            guard response.isForMainFrame, let url = response.response.url ?? lastRequest?.url else { return .cancel }
            let request = lastRequest?.url == url ? lastRequest! : URLRequest(url: url)
            tab?.onStartDownload?(request)
            return .cancel
        }
        if response.isForMainFrame { tab?.arriving = (response.response.url, response.response.mimeType?.lowercased()) }
        return .allow
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        tab?.onDownload?(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        tab?.onDownload?(download)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Trace.mark("commit \(webView.url?.host() ?? "")")
        tab?.committed(webView.url)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Trace.mark("start \(webView.url?.host() ?? "")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Trace.mark("finish \(webView.url?.host() ?? "")")
        tab?.finished()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url else { return nil }
        _ = tab?.openTab?(url, true)
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        tab?.failed(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    // A long press on a link: WebKit's own preview of it, and what Quo
    // does with links, above what WebKit offers for an image under it.
    func webView(_ webView: WKWebView, contextMenuConfigurationFor element: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let tab, let url = element.linkURL else { return nil }
        let web = ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        guard web else { return nil }
        let store = webView.configuration.websiteDataStore
        let desktop = tab.desktop
        return UIContextMenuConfiguration(identifier: nil, previewProvider: {
            MainActor.assumeIsolated { LinkPreview(url: url, store: store, desktop: desktop) }
        }) { [weak tab] suggested in
            MainActor.assumeIsolated {
                guard let tab else { return UIMenu(children: suggested) }
                return LinkMenu.menu(for: url, in: tab, suggested: suggested)
            }
        }
    }

    // The preview tapped: the link, in this tab.
    func webView(_ webView: WKWebView, contextMenuForElement element: WKContextMenuElementInfo,
                 willCommitWithAnimator animator: UIContextMenuInteractionCommitAnimating) {
        guard let url = element.linkURL else { return }
        animator.preferredCommitStyle = .pop
        // Where the preview got to, if it went on from the link.
        let shown = (animator.previewViewController as? LinkPreview)?.web.url ?? url
        animator.addCompletion { webView.load(URLRequest(url: shown)) }
    }

    // Alerts, confirms and prompts, as sheets of the system's.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await Dialogs.alert(message, host: frame.request.url?.host())
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await Dialogs.confirm(message, host: frame.request.url?.host())
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await Dialogs.prompt(prompt, text: defaultText, host: frame.request.url?.host())
    }
}

/// The page's own dialogs, over whatever is on top.
@MainActor
enum Dialogs {
    static var top: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }

    static func alert(_ message: String, host: String?) async {
        await withCheckedContinuation { done in
            let alert = UIAlertController(title: host, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume() })
            guard let top else { return done.resume() }
            top.present(alert, animated: true)
        }
    }

    static func confirm(_ message: String, host: String?) async -> Bool {
        await withCheckedContinuation { done in
            let alert = UIAlertController(title: host, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume(returning: true) })
            guard let top else { return done.resume(returning: false) }
            top.present(alert, animated: true)
        }
    }

    static func prompt(_ message: String, text: String?, host: String?) async -> String? {
        await withCheckedContinuation { done in
            let alert = UIAlertController(title: host, message: message, preferredStyle: .alert)
            alert.addTextField { $0.text = text }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume(returning: alert.textFields?.first?.text) })
            guard let top else { return done.resume(returning: nil) }
            top.present(alert, animated: true)
        }
    }
}

/// Timings for a page's load, logged when QUO_TRACE is set.
enum Trace {
    static let on = ProcessInfo.processInfo.environment["QUO_TRACE"] != nil
    static var last = Date()
    static func mark(_ what: String) {
        guard on else { return }
        let now = Date()
        NSLog("QUOTRACE %@ +%.0fms", what, now.timeIntervalSince(last) * 1000)
        last = now
    }
}
