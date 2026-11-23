import AVFoundation
import AppKit
import SwiftUI

/// View › Listen to Page, as Safari's: the article read aloud by the Mac's
/// own voice, a paragraph at a time, with a small bar at the foot of the page
/// to pause, go on or stop. The article is the block of the page with the
/// most prose, as Reader decides it; text you've selected, if any, instead.
/// The voice is the best one installed for the page's language (Premium or
/// Enhanced ones from System Settings › Accessibility › Spoken Content, if
/// you have them). Nothing leaves the Mac.
///
/// One page at a time for the whole app. Going elsewhere in that tab, or
/// closing it, stops it.
@MainActor
final class Listener: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Listener()

    enum State: Equatable { case idle, reading, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var title = ""
    @Published private(set) var part = 0
    @Published private(set) var parts: [String] = []
    /// The tab being read, and the address it was read from.
    private(set) var tabID: Tab.ID?
    private var address: URL?

    private let voice = AVSpeechSynthesizer()

    override init() {
        super.init()
        voice.delegate = self
    }

    /// Read `tab` aloud, or stop if it's the one being read.
    func toggle(_ tab: Tab?, said: @escaping (String) -> Void) {
        guard let tab else { return }
        if tabID == tab.id, state != .idle { return stop() }
        guard tab.isWeb, let web = tab.built else { return said("Nothing to read on this page") }
        web.evaluateJavaScript(Self.script) { [weak self, weak tab] result, _ in
            MainActor.assumeIsolated {
                guard let self, let tab else { return }
                let found = result as? [String: Any]
                let paragraphs = (found?["parts"] as? [String] ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.count > 1 }
                guard !paragraphs.isEmpty else { return said("Nothing to read on this page") }
                self.start(paragraphs, title: found?["title"] as? String ?? tab.label,
                           language: found?["lang"] as? String, tab: tab)
            }
        }
    }

    private func start(_ paragraphs: [String], title: String, language: String?, tab: Tab) {
        voice.stopSpeaking(at: .immediate)
        parts = paragraphs
        part = 0
        self.title = title
        tabID = tab.id
        address = tab.address
        speaking = Self.voice(for: language)
        state = .reading
        // A heading first: the title, unless the article starts with it.
        if let first = paragraphs.first, !first.hasPrefix(title.prefix(20)) {
            say(title)
        }
        paragraphs.forEach(say)
    }

    private var speaking: AVSpeechSynthesisVoice?

    private func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = speaking
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.25
        // A test run reads to nobody (it still reads, so it can be followed).
        if Store.testing { utterance.volume = 0 }
        voice.speak(utterance)
    }

    func pauseOrGo() {
        switch state {
        case .reading: if voice.pauseSpeaking(at: .word) { state = .paused }
        case .paused: if voice.continueSpeaking() { state = .reading }
        case .idle: break
        }
    }

    func stop() {
        voice.stopSpeaking(at: .immediate)
        state = .idle
        parts = []
        part = 0
        tabID = nil
        address = nil
    }

    /// A tab went somewhere else, or closed: if it's the one being read,
    /// the reading stops.
    func left(_ tab: Tab, closing: Bool = false) {
        guard tab.id == tabID else { return }
        if closing || tab.address != address { stop() }
    }

    /// The best voice installed for the page's language: Premium, then
    /// Enhanced, then any; the Mac's own if the page doesn't say.
    static func voice(for language: String?) -> AVSpeechSynthesisVoice? {
        let wanted = (language?.isEmpty == false ? language! : AVSpeechSynthesisVoice.currentLanguageCode())
        let base = String(wanted.prefix(2)).lowercased()
        let fitting = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(base) }
        let exact = fitting.filter { $0.language.lowercased() == wanted.lowercased().replacingOccurrences(of: "_", with: "-") }
        let pool = exact.isEmpty ? fitting : exact
        return pool.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: wanted)
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        MainActor.assumeIsolated {
            if let index = parts.firstIndex(of: text) { part = index }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            if !voice.isSpeaking, state == .reading { stop() }
        }
    }

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
      return { title, lang, parts };
    })();
    """
}

extension Browser {
    /// View › Listen to Page: the page in front read aloud, or stopped.
    func toggleListen() {
        Listener.shared.toggle(active) { [weak self] said in self?.announce(said) }
    }
}

/// The bar at the foot of the page while it's read: what's being read, how
/// far, pause or go on, and stop.
struct ListenBar: View {
    @ObservedObject var listener: Listener
    let tabID: Tab.ID?

    var body: some View {
        if listener.state != .idle, listener.tabID == tabID {
            HStack(spacing: 10) {
                Button(action: listener.pauseOrGo) {
                    Image(systemName: listener.state == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Palette.ink.opacity(0.08), in: Circle())
                }
                .buttonStyle(PressStyle())
                .help(listener.state == .paused ? "Go On" : "Pause")
                VStack(alignment: .leading, spacing: 1) {
                    Text(listener.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(listener.state == .paused ? "Paused" : "Reading aloud · \(listener.part + 1) of \(max(1, listener.parts.count))")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: 260, alignment: .leading)
                Button(action: listener.stop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PressStyle())
                .help("Stop Reading")
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(Palette.ground, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 5)
            .padding(.bottom, 16)
            .transition(.opacity.combined(with: .offset(y: 8)))
            .animation(Motion.quick, value: listener.part)
        }
    }
}
