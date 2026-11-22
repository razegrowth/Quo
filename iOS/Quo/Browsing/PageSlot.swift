import Combine
import SwiftUI
import UIKit
import WebKit

/// One tab's place on the screen: its page, live, with the strip under the
/// status bar in the page's colour, a thin line while it loads, and its
/// picture laid over it until the page has drawn something of its own.
///
/// A tab keeps its slot while it's one of the last few you've looked at,
/// so going back to it is moving a view that's already drawn, never
/// putting a page on screen in the middle of a motion.
@MainActor
final class PageSlot: UIView {
    let tab: Tab
    private(set) var web: WKWebView?
    /// The tab's picture, over the page until the page has drawn.
    private let cover = UIImageView()
    private let line = UIView()
    private var failure: UIHostingController<PageFailure>?
    private var watching: Set<AnyCancellable> = []
    /// Pull the page down from its top to load it again.
    private let refresh = PullRefresh()
    private var pullWatch: NSKeyValueObservation?
    /// A reload a pull asked for, and whether the page has started it yet.
    private var reloading = false
    private var reloadStarted = false

    /// The status bar's height: the page starts under it.
    var strip: CGFloat = 0 { didSet { if strip != oldValue { setNeedsLayout() } } }

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerCurve = .continuous
        backgroundColor = tab.topColor
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.isHidden = true
        line.backgroundColor = UIColor(Q.ink).withAlphaComponent(0.55)
        line.alpha = 0
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The page in it, made now if it wasn't. Until it has drawn, its
    /// picture stands in, so a tab not opened since Quo started never
    /// shows as a blank page.
    func wake(scrolled: @escaping (CGFloat, Bool, Tab) -> Void) {
        guard web == nil else { return }
        let web = tab.webView(store: Tabs.shared.store(for: tab))
        web.removeFromSuperview()
        // The page sets its own insets: a slot is moved and scaled as a
        // card, and the page mustn't lay itself out again as it goes.
        web.scrollView.contentInsetAdjustmentBehavior = .never
        insertSubview(web, at: 0)
        addSubview(cover)
        addSubview(line)
        addSubview(refresh)
        self.web = web
        web.scrollView.panGestureRecognizer.addTarget(self, action: #selector(scrollPanned(_:)))
        pullWatch = web.scrollView.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
            MainActor.assumeIsolated { self?.scrolled(scroll) }
        }
        tab.onScroll = { [weak tab] delta, dragging in
            guard let tab else { return }
            scrolled(delta, dragging, tab)
        }
        cover.image = tab.thumbnail
        cover.isHidden = tab.hasDrawn || tab.thumbnail == nil
        cover.alpha = 1
        watch()
        setNeedsLayout()
    }

    /// Back on screen after being put away: WebKit may take a moment to
    /// draw it again, so its picture covers it for that moment.
    func returned() {
        guard let image = tab.thumbnail else { return }
        cover.image = image
        cover.alpha = 1
        cover.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.uncover() }
    }

    private func watch() {
        watching = []
        tab.$themeColor.merge(with: tab.$pageColor)
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.map { $0.backgroundColor = $0.tab.topColor } } }
            }
            .store(in: &watching)
        tab.$progress
            .sink { [weak self] value in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.progressChanged(value)
                }
            }
            .store(in: &watching)
        tab.$loading
            .sink { [weak self] loading in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // While the pull's own disc says it's loading, the line keeps out of it.
                    UIView.animate(withDuration: 0.2) { self.line.alpha = loading && !self.reloading ? 1 : 0 }
                    if !loading { DispatchQueue.main.async { self.checkDrawn() } }
                    if loading, self.reloading { self.reloadStarted = true }
                    if !loading, self.reloading, self.reloadStarted { self.reloaded() }
                }
            }
            .store(in: &watching)
        tab.$thumbnail
            .sink { [weak self] image in
                MainActor.assumeIsolated {
                    guard let self, let image, !self.cover.isHidden else { return }
                    self.cover.image = image
                }
            }
            .store(in: &watching)
        tab.$failure
            .sink { [weak self] failure in
                MainActor.assumeIsolated { self?.showFailure(failure) }
            }
            .store(in: &watching)
    }

    private var progress: Double = 0

    /// How far the page is pulled down past its top.
    private func pull(_ scroll: UIScrollView) -> CGFloat {
        max(0, -(scroll.contentOffset.y + scroll.adjustedContentInset.top))
    }

    private func scrolled(_ scroll: UIScrollView) {
        refresh.pulled(pull(scroll), dragging: scroll.isTracking)
    }

    @objc private func scrollPanned(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended || pan.state == .cancelled, let scroll = web?.scrollView else { return }
        guard pan.state == .ended, refresh.released() else { return }
        reloading = true
        reloadStarted = false
        web?.reload()
        // A page that never says it's loading (or never stops): the disc
        // goes after a while all the same.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.reloading, !self.reloadStarted, !self.tab.loading else { return }
            self.reloaded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, self.reloading else { return }
            self.reloaded()
        }
    }

    private func reloaded() {
        reloading = false
        reloadStarted = false
        refresh.finished()
    }

    private func progressChanged(_ value: Double) {
        progress = value
        UIView.animate(withDuration: 0.14, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.layoutLine()
        }
        DispatchQueue.main.async { self.checkDrawn() }
    }

    private func checkDrawn() {
        if tab.hasDrawn { uncover() }
    }

    private func uncover() {
        guard !cover.isHidden, cover.alpha == 1 else { return }
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut]) {
            self.cover.alpha = 0
        } completion: { _ in
            if self.cover.alpha == 0 { self.cover.isHidden = true }
        }
    }

    private func showFailure(_ text: String?) {
        if let text {
            let view = PageFailure(host: Address.shown(tab.url), text: text) { [weak self] in self?.tab.retry() }
            if let failure {
                failure.rootView = view
            } else {
                let host = UIHostingController(rootView: view)
                host.view.backgroundColor = .clear
                addSubview(host.view)
                failure = host
                setNeedsLayout()
            }
        } else if let failure {
            failure.view.removeFromSuperview()
            self.failure = nil
        }
    }

    private var page: CGRect { CGRect(x: 0, y: strip, width: bounds.width, height: max(0, bounds.height - strip)) }

    override func layoutSubviews() {
        super.layoutSubviews()
        let page = self.page
        if web?.frame != page {
            web?.frame = page
            // Room under the page for the bar, so its foot can be scrolled
            // to, and the home indicator's strip.
            let bottom = 64 + (window?.safeAreaInsets.bottom ?? 34)
            if let scroll = web?.scrollView, scroll.contentInset.bottom != bottom {
                scroll.contentInset.bottom = bottom
                scroll.verticalScrollIndicatorInsets.bottom = bottom
            }
        }
        cover.frame = page
        failure?.view.frame = page
        refresh.top = strip
        layoutLine()
    }

    private func layoutLine() {
        line.frame = CGRect(x: 0, y: strip, width: bounds.width * max(0.06, progress), height: 2)
    }
}

/// A page that couldn't be opened, in its place.
struct PageFailure: View {
    let host: String
    let text: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Q.muted)
            Text("Can\u{2019}t open \(host)")
                .font(Q.callout)
                .foregroundStyle(Q.ink)
                .multilineTextAlignment(.center)
            Text(text)
                .font(Q.footnote)
                .foregroundStyle(Q.muted)
                .multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Try Again")
                    .font(Q.bodyEmphasis)
                    .foregroundStyle(Q.ground)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(Q.ink, in: Capsule())
            }
            .buttonStyle(PressStyle())
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Q.ground)
    }
}
