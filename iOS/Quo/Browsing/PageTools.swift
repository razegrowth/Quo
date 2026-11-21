import SwiftUI
import Translation
import WebKit

// MARK: - Translate

/// A page translated where it is, on this iPhone, by Apple's Translation:
/// its text read out of the page, translated in batches, and put back in
/// place. Show original loads it again.
enum Translator {
    enum State: Equatable { case idle, working(Int, Int), done, failed(String) }

    static let collect = """
    (function(){
      var skip = {SCRIPT:1, STYLE:1, NOSCRIPT:1, CODE:1, PRE:1, TEXTAREA:1, INPUT:1, SVG:1, MATH:1};
      var nodes = [], texts = [];
      var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(n) {
          var p = n.parentElement;
          if (!p || skip[p.tagName] || p.closest('[translate="no"],.notranslate')) return NodeFilter.FILTER_REJECT;
          return n.nodeValue.trim().length > 1 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
        }
      });
      while (walker.nextNode() && nodes.length < 1500) { nodes.push(walker.currentNode); texts.push(walker.currentNode.nodeValue.trim()); }
      window.__quoNodes = nodes;
      return texts;
    })();
    """

    static func put(_ index: Int, _ text: String) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: [text], options: [.fragmentsAllowed]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return """
        (function(){ var n = (window.__quoNodes || [])[\(index)]; if (!n) return;
          var v = n.nodeValue, lead = v.match(/^\\s*/)[0], tail = v.match(/\\s*$/)[0];
          n.nodeValue = lead + \(json)[0] + tail; })();
        """
    }
}

extension Browser {
    func translate(_ tab: Tab) {
        if translating == .done {
            translating = .idle
            tab.reload()
            return
        }
        guard let web = tab.webViewIfBuilt else { return }
        web.evaluateJavaScript(Translator.collect) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, let texts = result as? [String], !texts.isEmpty else {
                    self?.say("Nothing on this page to translate")
                    return
                }
                self.translationTexts = texts
                self.translationTab = tab
                self.translating = .working(0, texts.count)
                let target = Locale.Language(identifier: AppSettings.shared.translateTo)
                if self.translationConfig == nil {
                    self.translationConfig = TranslationSession.Configuration(source: nil, target: target)
                } else {
                    self.translationConfig?.target = target
                    self.translationConfig?.invalidate()
                }
            }
        }
    }

    func runTranslation(_ session: TranslationSession) async {
        guard let tab = translationTab, let web = tab.webViewIfBuilt else { return }
        let texts = translationTexts
        var done = 0
        do {
            for start in stride(from: 0, to: texts.count, by: 80) {
                let batch = (start..<min(start + 80, texts.count)).map {
                    TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0))
                }
                let answers = try await session.translations(from: batch)
                for answer in answers {
                    guard let id = answer.clientIdentifier, let index = Int(id) else { continue }
                    _ = try? await web.evaluateJavaScript(Translator.put(index, answer.targetText))
                }
                done += batch.count
                translating = .working(done, texts.count)
            }
            translating = .done
        } catch {
            translating = .failed("Couldn\u{2019}t translate this page")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                MainActor.assumeIsolated { if case .failed = self?.translating { self?.translating = .idle } }
            }
        }
    }
}

private struct TranslatorHost: ViewModifier {
    @ObservedObject var browser: Browser
    func body(content: Content) -> some View {
        content.translationTask(browser.translationConfig) { session in
            await browser.runTranslation(session)
        }
    }
}

extension View {
    func translator(browser: Browser) -> some View { modifier(TranslatorHost(browser: browser)) }
}

/// While a page is being translated, and once it is.
struct TranslateBadge: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Group {
            switch browser.translating {
            case .idle: EmptyView()
            case let .working(done, all):
                badge("Translating\u{2026} \(all == 0 ? 0 : done * 100 / all)%", action: nil)
            case .done:
                badge("Translated to \(Locale.current.localizedString(forLanguageCode: settings.translateTo) ?? settings.translateTo) \u{00B7} Show original") {
                    if let tab = browser.translationTab { browser.translate(tab) }
                }
            case .failed(let why):
                badge(why, action: nil)
            }
        }
        .animation(Q.snap, value: browser.translating)
    }

    private func badge(_ text: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            Text(text)
                .font(Q.footnote.weight(.medium))
                .foregroundStyle(Q.ink)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Q.hairline))
        }
        .buttonStyle(PressStyle())
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Reader

/// The page's words on their own, in Quo's type.
enum Reader {
    struct Article: Equatable {
        var title: String
        var site: String
        var html: String
    }

    static let extract = """
    (function(){
      // Each paragraph counts for the box holding it, and less for the
      // boxes around that: the article is the box with the most words.
      var scores = new Map();
      document.querySelectorAll('p').forEach(function(p){
        if (p.closest('nav, aside, footer, header, form')) return;
        var len = (p.textContent || '').trim().length;
        if (len < 25) return;
        var el = p.parentElement, weight = 1;
        for (var i = 0; i < 3 && el; i++) {
          scores.set(el, (scores.get(el) || 0) + len * weight);
          el = el.parentElement; weight = weight * 0.75;
        }
      });
      var best = null, bestScore = 0;
      scores.forEach(function(score, el){ if (score > bestScore) { bestScore = score; best = el; } });
      if (!best || bestScore < 300) return null;
      var blocks = [];
      best.querySelectorAll('h1,h2,h3,h4,p,li,blockquote,pre,img,figcaption').forEach(function(el){
        if (blocks.length > 600) return;
        var tag = el.tagName.toLowerCase();
        if (tag === 'img') {
          var src = el.currentSrc || el.src || el.getAttribute('data-src');
          var wide = el.naturalWidth || parseInt(el.getAttribute('width') || '0', 10);
          if (src && wide > 120 && !src.startsWith('data:')) blocks.push({t: 'img', x: src});
          return;
        }
        if (el.closest('nav, aside, footer, form, table, .reference, .mw-editsection, .toc, #toc, .references')) return;
        if (tag === 'li' && el.querySelector('p, li')) return;
        var copy = el.cloneNode(true);
        copy.querySelectorAll('sup.reference, .mw-editsection, style, script').forEach(function(x){ x.remove(); });
        var text = (copy.textContent || '').replace(/\\s+/g, ' ').trim();
        if (text.length > 1) blocks.push({t: tag, x: text});
      });
      return {title: document.title, site: location.hostname.replace(/^www\\./, ''), blocks: blocks};
    })();
    """

    @MainActor
    static func extract(from tab: Tab) async -> Article? {
        guard let web = tab.webViewIfBuilt else { return nil }
        let raw: Any?
        do { raw = try await web.callAsyncJavaScript("return " + extract, contentWorld: .defaultClient) } catch {
            Trace.mark("reader failed: \(error)")
            return nil
        }
        guard let result = raw as? [String: Any], let blocks = result["blocks"] as? [[String: String]], blocks.count > 2 else {
            Trace.mark("reader found nothing: \(String(describing: raw).prefix(200))")
            return nil
        }
        var html = ""
        for block in blocks {
            let tag = block["t"] ?? "p", text = escape(block["x"] ?? "")
            switch tag {
            case "img": html += "<img src=\"\(text)\" alt=\"\">"
            case "h1", "h2", "h3", "h4", "blockquote", "pre", "figcaption": html += "<\(tag)>\(text)</\(tag)>"
            case "li": html += "<p class=\"li\">\u{2022} \(text)</p>"
            default: html += "<p>\(text)</p>"
            }
        }
        return Article(title: result["title"] as? String ?? tab.shownTitle, site: result["site"] as? String ?? "", html: html)
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func page(_ article: Article) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; --ink: #171717; --muted: #8C8C8C; --ground: #FFFFFF; --hairline: #E8E8E8; }
        @media (prefers-color-scheme: dark) { :root { --ink: #EDEDED; --muted: #949494; --ground: #1C1C1C; --hairline: #333333; } }
        body { font: 18px/1.6 -apple-system, system-ui; color: var(--ink); background: var(--ground); margin: 0; padding: 28px 22px 80px; -webkit-text-size-adjust: 100%; }
        main { max-width: 36em; margin: 0 auto; }
        .site { font-size: 13px; color: var(--muted); margin-bottom: 6px; }
        h1 { font-size: 26px; line-height: 1.2; letter-spacing: -0.01em; font-weight: 600; margin: 0 0 22px; }
        h2, h3, h4 { font-size: 19px; line-height: 1.3; font-weight: 600; margin: 28px 0 8px; }
        p { margin: 0 0 16px; } p.li { margin-left: 4px; }
        img { max-width: 100%; height: auto; border-radius: 10px; margin: 8px 0 16px; }
        blockquote { margin: 0 0 16px; padding-left: 14px; border-left: 2px solid var(--hairline); color: var(--muted); }
        pre { white-space: pre-wrap; font: 14px/1.5 ui-monospace, Menlo; }
        figcaption { font-size: 13px; color: var(--muted); margin-top: -8px; }
        </style></head><body><main>
        <div class="site">\(escape(article.site))</div><h1>\(escape(article.title))</h1>
        \(article.html)
        </main></body></html>
        """
    }
}

struct ReaderSheet: View {
    let article: Reader.Article?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let article { ReaderWeb(html: Reader.page(article)) } else { Color.clear }
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Reader")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(Q.ink)
        .presentationCornerRadius(28)
    }
}

private struct ReaderWeb: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.loadHTMLString(html, baseURL: nil)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
}
