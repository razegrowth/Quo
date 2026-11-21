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

    // MARK: - the page

    /// The page, made now if it wasn't: the address, or where it left off.
    func webView(store: WKWebsiteDataStore) -> WKWebView {
        if let web { return web }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: TabHelper.reportScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        controller.add(helper, name: "quo")
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
        guard let web, web.bounds.width > 0 else { return }
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Double(min(web.bounds.width, 430)))
        if let image = try? await web.takeSnapshot(configuration: config) {
            thumbnail = image
            if !incognito, let data = image.jpegData(compressionQuality: 0.6) {
                try? data.write(to: Tab.thumbnailURL(id))
            }
        }
    }

    static func thumbnailURL(_ id: UUID) -> URL {
        let folder = Store.folder.appendingPathComponent("thumbs", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(id.uuidString + ".jpg")
    }

    func loadThumbnail() {
        guard thumbnail == nil, let data = try? Data(contentsOf: Tab.thumbnailURL(id)) else { return }
        thumbnail = UIImage(data: data)
    }

    /// Put away: the page closed, its place kept.
    func unload() {
        guard let web else { return }
        interactionState = web.interactionState as? Data
        web.configuration.userContentController.removeScriptMessageHandler(forName: "quo")
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
        guard let url else { return }
        if !incognito { History.shared.record(url, title: web?.title) }
        web?.allowsBackForwardNavigationGestures = Sites.shared.settings(for: url.host()).swipe == .edges
    }

    /// Opens another tab (a link with target=_blank, window.open).
    var openTab: ((URL, Bool) -> WKWebView?)?
    var onDownload: ((WKDownload) -> Void)?
}

/// The page's delegate, kept apart so the tab isn't retained by WebKit.
@MainActor
private final class TabHelper: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    weak var tab: Tab?
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
        guard let body = message.body as? [String: Any] else { return }
        tab?.pageReported(addresses: body["urls"] as? [String] ?? [], icon: body["icon"] as? String)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        guard let tab, let url = action.request.url else { return (.allow, preferences) }
        if action.targetFrame?.isMainFrame ?? true { Trace.mark("decide \(url.host() ?? "")") }
        preferences.preferredContentMode = tab.desktop ? .desktop : .mobile
        if action.shouldPerformDownload { return (.download, preferences) }
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
        response.canShowMIMEType ? .allow : .download
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
