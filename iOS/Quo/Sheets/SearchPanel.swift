import AVFoundation
import Speech
import SwiftUI

/// A new search: the field over the keyboard, what matches under it.
struct SearchPanel: View {
    @ObservedObject var browser: Browser
    let prefill: String?
    private var incognito: Bool {
        get { browser.searchIncognito }
        nonmutating set { browser.searchIncognito = newValue }
    }
    @State private var text = ""
    @State private var engineWords: [String] = []
    @State private var asking: Task<Void, Never>?
    @FocusState private var focused: Bool
    @StateObject private var dictation = Dictation()
    @ObservedObject private var tabs = Tabs.shared
    @ObservedObject private var settings = AppSettings.shared

    let morph: Namespace.ID

    init(browser: Browser, prefill: String?, morph: Namespace.ID) {
        self.browser = browser
        self.prefill = prefill
        self.morph = morph
    }

    var body: some View {
        // The sheet behind this is the bottom bar's own, grown (Chrome).
        VStack(spacing: 0) {
            field
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 6)
            content
                .frame(maxWidth: .infinity)
        }
        .environment(\.colorScheme, incognito ? .dark : colorScheme)
        .onAppear {
            text = prefill ?? ""
            if settings.autoKeyboard || prefill != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
            }
        }
        .onDisappear { dictation.stop() }
        .onChange(of: text) { _, new in askEngine(new) }
        .onChange(of: dictation.words) { _, words in if !words.isEmpty { text = words } }
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - the field

    private var field: some View {
        HStack(spacing: 10) {
            TextField(incognito ? "Search privately" : "Search or type an address", text: $text)
                .font(.system(size: 17))
                .foregroundStyle(Q.ink)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                // The field hands over its last keystroke a moment after
                // Return when typed quickly: the words are read a turn later.
                .onSubmit { DispatchQueue.main.async { submit(text) } }
                .accessibilityIdentifier("search.field")

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Q.faint)
                }
                .accessibilityLabel("Clear")
            } else {
                Button { dictation.toggle() } label: {
                    Image(systemName: dictation.listening ? "waveform" : "mic")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(dictation.listening ? Q.ink : Q.muted)
                        .symbolEffect(.variableColor.iterative, isActive: dictation.listening)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(dictation.listening ? "Stop listening" : "Search by voice")
                .accessibilityIdentifier("search.mic")
            }

            Button { withAnimation(Q.settle) { incognito.toggle() } } label: {
                HStack(spacing: 6) {
                    if incognito { Text("Incognito").font(Q.footnote.weight(.medium)) }
                    Image(systemName: incognito ? "eyeglasses" : "eyeglasses")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(6)
                        .background(incognito ? Q.ink : Color.clear, in: Circle())
                        .foregroundStyle(incognito ? Q.ground : Q.muted)
                }
                .foregroundStyle(Q.ink)
            }
            .accessibilityLabel(incognito ? "Leave incognito" : "Incognito")
            .accessibilityIdentifier("search.incognito")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 54)
        .background(Q.tile, in: Capsule())
        .overlay(Capsule().strokeBorder(Q.hairline))
    }

    // MARK: - under it

    @ViewBuilder private var content: some View {
        if let problem = dictation.problem {
            quiet(problem)
        } else if incognito && text.isEmpty {
            quiet("You\u{2019}re browsing Incognito")
                .frame(height: 220)
        } else {
            let rows = suggestions
            if rows.isEmpty {
                Color.clear.frame(height: 12)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            Button { choose(row) } label: { SuggestionRow(row: row) }
                                .buttonStyle(RowStyle())
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func quiet(_ words: String) -> some View {
        Text(words)
            .font(Q.callout.weight(.medium))
            .foregroundStyle(Q.muted)
            .frame(maxWidth: .infinity, minHeight: 120)
    }

    struct Suggestion: Identifiable {
        enum Kind { case tab(Tab), page(URL), search(String) }
        let id: String
        let kind: Kind
        let title: String
        let note: String?
        let host: String?
    }

    private var suggestions: [Suggestion] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        var rows: [Suggestion] = []
        var seen = Set<String>()
        func add(_ row: Suggestion, key: String) {
            guard !seen.contains(key) else { return }
            seen.insert(key)
            rows.append(row)
        }
        if typed.isEmpty {
            for tab in tabs.regular.sorted(by: { $0.lastActive > $1.lastActive }).prefix(4) {
                add(Suggestion(id: "tab" + tab.id.uuidString, kind: .tab(tab), title: tab.shownTitle, note: nil, host: tab.host),
                    key: tab.url?.absoluteString ?? tab.id.uuidString)
            }
            return rows
        }
        let lower = typed.lowercased()
        // Open tabs first, as ⌘T has them on the Mac.
        for tab in tabs.all where tab.incognito == incognito {
            let hay = (tab.title + " " + (tab.url?.absoluteString ?? "")).lowercased()
            guard hay.contains(lower) else { continue }
            add(Suggestion(id: "tab" + tab.id.uuidString, kind: .tab(tab), title: tab.shownTitle, note: "Switch to tab", host: tab.host),
                key: tab.url?.absoluteString ?? tab.id.uuidString)
            if rows.count >= 2 { break }
        }
        // The space's pins and the bookmarks.
        let sync = MacSync.shared
        let marks = sync.pins(in: sync.currentSpaceID).map { ($0.name ?? $0.title, $0.home) } + Self.flatten(sync.bookmarks)
        for (title, home) in marks where (title + " " + home).lowercased().contains(lower) {
            guard let url = URL(string: home) else { continue }
            add(Suggestion(id: "mark" + home, kind: .page(url), title: title, note: Address.shown(url), host: url.host()), key: home)
            if rows.count >= 4 { break }
        }
        if !incognito {
            for visit in History.shared.matches(typed, limit: 4) {
                guard let url = URL(string: visit.url) else { continue }
                add(Suggestion(id: "visit" + visit.url, kind: .page(url), title: visit.title.isEmpty ? Address.shown(url) : visit.title,
                               note: Address.shown(url), host: url.host()), key: visit.url)
                if rows.count >= 6 { break }
            }
        }
        if let url = Address.url(typed) {
            rows.insert(Suggestion(id: "go", kind: .page(url), title: typed, note: "Open", host: url.host()), at: 0)
        }
        rows.append(Suggestion(id: "search", kind: .search(typed), title: typed,
                               note: "Search \(settings.engine.name(custom: settings.customTemplate))", host: nil))
        for words in engineWords.prefix(5) where words.lowercased() != lower {
            rows.append(Suggestion(id: "s" + words, kind: .search(words), title: words, note: nil, host: nil))
        }
        return rows
    }

    static func flatten(_ marks: [Bookmark]) -> [(String, String)] {
        marks.flatMap { mark -> [(String, String)] in
            if let url = mark.url { return [(mark.title, url)] }
            return flatten(mark.children ?? [])
        }
    }

    // MARK: - choosing

    private func choose(_ row: Suggestion) {
        switch row.kind {
        case .tab(let tab):
            tabs.select(tab)
            browser.panel = .none
        case .page(let url): browser.go(url, incognito: incognito, newTab: true)
        case .search(let words): submit(words)
        }
    }

    private func submit(_ typed: String) {
        guard !typed.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        dictation.stop()
        browser.go(typed, incognito: incognito, newTab: true)
    }

    private func close() {
        dictation.stop()
        browser.panel = .none
    }

    /// The engine's own suggestions, after a short pause in typing.
    private func askEngine(_ typed: String) {
        asking?.cancel()
        let words = typed.trimmingCharacters(in: .whitespaces)
        guard settings.engineSuggests, !incognito, !words.isEmpty, words.count <= 80, Address.url(words) == nil,
              let template = EngineWords.endpoint(settings.engine),
              let encoded = words.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: template.replacingOccurrences(of: "%s", with: encoded)) else {
            engineWords = []
            return
        }
        asking = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let found = await EngineWords.fetch(url)
            guard !Task.isCancelled else { return }
            engineWords = found
        }
    }
}

private struct SuggestionRow: View {
    let row: SearchPanel.Suggestion

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if case .search = row.kind {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .medium)).foregroundStyle(Q.muted)
                        .frame(width: 22, height: 22)
                } else {
                    SiteMark(host: row.host, size: 22)
                }
            }
            Text(row.title)
                .font(Q.body)
                .foregroundStyle(Q.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let note = row.note {
                Text(note)
                    .font(Q.footnote)
                    .foregroundStyle(Q.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .contentShape(Rectangle())
    }
}

struct RowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Q.wash : Color.clear, in: RoundedRectangle(cornerRadius: Q.radiusMD, style: .continuous))
            .animation(Q.quick, value: configuration.isPressed)
    }
}

/// Search engines' suggestions: where each answers, as the Mac asks them
/// (EngineSuggest.swift), OpenSearch's ["words", ["…", …]].
enum EngineWords {
    static func endpoint(_ engine: Engine) -> String? {
        switch engine {
        case .google: return "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"
        case .duckduckgo: return "https://duckduckgo.com/ac/?q=%s&type=list"
        case .bing: return "https://www.bing.com/osjson.aspx?query=%s"
        case .ecosia: return "https://ac.ecosia.org/autocomplete?q=%s&type=list"
        case .startpage: return "https://www.startpage.com/osuggestions?q=%s"
        case .kagi: return "https://kagi.com/api/autosuggest?q=%s"
        case .brave: return "https://search.brave.com/api/suggest?q=%s"
        case .qwant: return "https://api.qwant.com/api/suggest/?q=%s&client=opensearch"
        case .custom: return nil
        }
    }

    static func fetch(_ url: URL) async -> [String] {
        var request = URLRequest(url: url, timeoutInterval: 0.8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count >= 2,
              let words = json[1] as? [String] else { return [] }
        return words
    }
}

/// Searching by voice: what's said becomes the field's words.
@MainActor
final class Dictation: ObservableObject {
    @Published private(set) var listening = false
    @Published private(set) var words = ""
    @Published private(set) var problem: String?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() { listening ? stop() : start() }

    func start() {
        problem = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard status == .authorized else {
                        self.problem = "Allow speech recognition in Settings to search by voice"
                        return
                    }
                    self.begin()
                }
            }
        }
    }

    private func begin() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            problem = "Voice isn\u{2019}t available right now"
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            problem = "The microphone isn\u{2019}t available"
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            problem = "The microphone isn\u{2019}t available"
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            problem = "The microphone isn\u{2019}t available"
            return
        }
        listening = true
        task = recognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let result { self.words = result.bestTranscription.formattedString }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
        }
    }

    func stop() {
        guard listening else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
