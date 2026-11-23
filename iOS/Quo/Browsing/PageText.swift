import WebKit

/// The words of the page in front, as a person would read them: the article
/// (the block with the most prose), or what you've selected, in order, by
/// heading and paragraph. For Ask This Page, a held card's summary and
/// Listen to Page. The Mac's own script (Sources/Search/Listen.swift), but
/// paragraphs that aren't drawn don't count (a phone site's folded sections
/// would win otherwise), and a page with too little falls back on its text.
struct PageText: Equatable {
    var title: String
    var lang: String?
    var parts: [String]
    var text: String { parts.joined(separator: "\n") }

    /// The article's paragraphs: the selection if there is one; otherwise
    /// the element whose paragraphs hold the most prose (each paragraph
    /// counting for its parent, half for its grandparent, less the text of
    /// links in it), its headings, paragraphs, items and quotes in order.
    static let script = """
    (() => {
      const lang = document.documentElement.lang || '';
      const picked = String(window.getSelection ? window.getSelection() : '').trim();
      if (picked.length > 40) return { title: document.title, lang, parts: picked.split(/\\n+/) };
      const score = new Map();
      for (const p of document.querySelectorAll('p, pre, blockquote')) {
        if (!p.getClientRects().length) continue;
        const text = (p.innerText || '').trim();
        if (text.length < 60) continue;
        let links = 0;
        for (const a of p.querySelectorAll('a')) links += (a.innerText || '').length;
        const worth = text.length - 2 * links + (text.match(/[.,;:]/g) || []).length * 5;
        if (worth <= 0) continue;
        const parent = p.parentElement, grand = parent && parent.parentElement;
        if (parent) score.set(parent, (score.get(parent) || 0) + worth);
        if (grand) score.set(grand, (score.get(grand) || 0) + worth / 2);
      }
      let best = null, most = 0;
      for (const [el, s] of score) if (s > most) { most = s; best = el; }
      const root = best || document.querySelector('article, main, [role=main]') || document.body;
      const heading = document.querySelector('h1');
      const title = (heading && heading.innerText.trim()) || document.title;
      const parts = [];
      for (const el of root.querySelectorAll('h1, h2, h3, h4, p, li, blockquote, pre')) {
        if (el.closest('nav, aside, footer, form, figure figcaption')) continue;
        if (el.tagName === 'LI' && el.querySelector('p')) continue;
        const style = getComputedStyle(el);
        if (style.display === 'none' || style.visibility === 'hidden') continue;
        const text = (el.innerText || '').replace(/\\s+/g, ' ').trim();
        if (text.length > 1 && parts[parts.length - 1] !== text) parts.push(text);
      }
      if (parts.length < 3) {
        parts.length = 0;
        for (const line of (document.body.innerText || '').split(/\\n+/)) {
          const text = line.replace(/\\s+/g, ' ').trim();
          if (text.length > 40) parts.push(text);
        }
      }
      return { title, lang, parts };
    })();
    """
}

extension Tab {
    /// The page's words once it has them: waited for while it loads (up to
    /// ten seconds), then read, and read again a moment later if it came
    /// back empty (a page that draws its text after it says it's loaded).
    func readableSoon() async -> PageText? {
        for _ in 0..<20 where loading { try? await Task.sleep(for: .milliseconds(500)) }
        if let page = await readable() { return page }
        try? await Task.sleep(for: .seconds(1))
        return await readable()
    }

    /// The page's readable words, or nil when it hasn't any (or isn't built).
    func readable() async -> PageText? {
        guard let web = webViewIfBuilt else { Trace.mark("readable: not built"); return nil }
        let found: [String: Any]
        do {
            guard let result = try await web.evaluateJavaScript(PageText.script) as? [String: Any] else {
                Trace.mark("readable: not a dictionary")
                return nil
            }
            found = result
        } catch {
            Trace.mark("readable failed \(error)")
            return nil
        }
        let parts = (found["parts"] as? [String] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count > 1 }
        Trace.mark("readable: \(parts.count) parts on \(web.url?.absoluteString ?? "-") loading \(web.isLoading)")
        guard !parts.isEmpty else { return nil }
        return PageText(title: found["title"] as? String ?? shownTitle, lang: found["lang"] as? String, parts: parts)
    }
}
