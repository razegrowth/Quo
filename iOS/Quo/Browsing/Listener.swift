import ActivityKit
import AVFoundation
import MediaPlayer
import SwiftUI

/// Listen to Page, from the ^ toolbar: the article read aloud by the
/// iPhone's own voice, a paragraph at a time, as the Mac's does (Sources/
/// Search/Listen.swift). It goes on with Quo in the background or the phone
/// locked, with a Live Activity on the Lock Screen and in the Dynamic Island
/// to pause or stop it, and the usual play and pause in Control Centre. The
/// voice is the best one installed for the page's language. Nothing leaves
/// the phone. One page at a time; going elsewhere in that tab, or closing
/// it, stops it.
@MainActor
final class Listener: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Listener()

    enum State: Equatable { case idle, reading, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var title = ""
    @Published private(set) var site = ""
    @Published private(set) var part = 0
    @Published private(set) var parts: [String] = []
    private(set) var tabID: UUID?
    private var address: URL?
    private let voice = AVSpeechSynthesizer()
    private var speaking: AVSpeechSynthesisVoice?
    private var activity: AnyObject?

    override init() {
        super.init()
        voice.delegate = self
        ListenControl.handler = { [weak self] action in
            switch action {
            case .pauseOrGo: self?.pauseOrGo()
            case .stop: self?.stop()
            }
        }
        let center = MPRemoteCommandCenter.shared()
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.state == .reading { self?.pauseOrGo() } }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { if self?.state == .paused { self?.pauseOrGo() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pauseOrGo() }
            return .success
        }
    }

    func reading(_ tab: Tab?) -> Bool { tab != nil && tab?.id == tabID && state != .idle }

    /// Read `tab` aloud, or stop if it's the one being read.
    func toggle(_ tab: Tab) {
        if reading(tab) { return stop() }
        Task {
            guard let page = await tab.readableSoon() else {
                Browser.shared.say("Nothing to read on this page")
                return
            }
            start(page, tab: tab)
        }
    }

    private func start(_ page: PageText, tab: Tab) {
        voice.stopSpeaking(at: .immediate)
        parts = page.parts
        part = 0
        title = page.title
        let host = tab.host ?? ""
        site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        tabID = tab.id
        address = tab.url
        speaking = Self.voice(for: page.lang)
        // Spoken words: other sound ducks under them, and they go on in
        // the background (UIBackgroundModes: audio).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        state = .reading
        if let first = page.parts.first, !first.hasPrefix(page.title.prefix(20)) { say(page.title) }
        page.parts.forEach(say)
        startActivity()
        nowPlaying()
    }

    private func say(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = speaking
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.postUtteranceDelay = 0.25
        if ProcessInfo.processInfo.environment["QUO_QUIET"] != nil { utterance.volume = 0 }
        voice.speak(utterance)
    }

    func pauseOrGo() {
        switch state {
        case .reading: if voice.pauseSpeaking(at: .word) { state = .paused }
        case .paused: if voice.continueSpeaking() { state = .reading }
        case .idle: return
        }
        updateActivity()
        nowPlaying()
    }

    func stop() {
        guard state != .idle || tabID != nil else { return }
        voice.stopSpeaking(at: .immediate)
        state = .idle
        parts = []
        part = 0
        tabID = nil
        address = nil
        endActivity()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Back to how pages' own sound plays (Media).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// A tab went somewhere else, or closed: if it's the one being read,
    /// the reading stops.
    func left(_ tab: Tab, closing: Bool = false) {
        guard tab.id == tabID, state != .idle else { return }
        if closing || tab.url?.absoluteString.split(separator: "#").first != address?.absoluteString.split(separator: "#").first { stop() }
    }

    /// The best voice installed for the page's language: Premium, then
    /// Enhanced, then any; the phone's own if the page doesn't say.
    static func voice(for language: String?) -> AVSpeechSynthesisVoice? {
        let wanted = (language?.isEmpty == false ? language! : AVSpeechSynthesisVoice.currentLanguageCode())
        let base = String(wanted.prefix(2)).lowercased()
        let fitting = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.lowercased().hasPrefix(base) }
        let exact = fitting.filter { $0.language.lowercased() == wanted.lowercased().replacingOccurrences(of: "_", with: "-") }
        let pool = exact.isEmpty ? fitting : exact
        return pool.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: wanted)
    }

    // MARK: - the Lock Screen

    private var content: ListenAttributes.ContentState {
        ListenAttributes.ContentState(paused: state == .paused, part: min(part + 1, max(1, parts.count)), parts: parts.count)
    }

    private func startActivity() {
        endActivity()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = ListenAttributes(title: title, site: site)
        activity = try? Activity.request(attributes: attributes, content: .init(state: content, staleDate: nil))
    }

    private func updateActivity() {
        guard let activity = activity as? Activity<ListenAttributes> else { return }
        let state = content
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    private func endActivity() {
        guard let activity = activity as? Activity<ListenAttributes> else { return }
        self.activity = nil
        let state = content
        Task { await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .immediate) }
    }

    private func nowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: site,
            MPNowPlayingInfoPropertyPlaybackRate: state == .reading ? 1.0 : 0.0,
        ]
    }

    /// What a test run reads: whether a Live Activity is up, and its state.
    var activityState: String {
        guard let activity = activity as? Activity<ListenAttributes> else { return "none" }
        return "\(activity.activityState) paused=\(activity.content.state.paused) part=\(activity.content.state.part)/\(activity.content.state.parts)"
    }

    // MARK: AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        MainActor.assumeIsolated {
            if let index = parts.firstIndex(of: text), index != part {
                part = index
                updateActivity()
            }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        MainActor.assumeIsolated {
            if !voice.isSpeaking, state == .reading { stop() }
        }
    }
}

/// While a page is read, a small bar over the foot of the page: what's
/// read, how far, pause or go on, and stop.
struct ListenBar: View {
    @ObservedObject var listener = Listener.shared

    var body: some View {
        if listener.state != .idle {
            HStack(spacing: 10) {
                Button(action: listener.pauseOrGo) {
                    Image(systemName: listener.state == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Q.ink)
                        .frame(width: 34, height: 34)
                        .background(Q.tile, in: Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(listener.state == .paused ? "Go on" : "Pause")
                VStack(alignment: .leading, spacing: 1) {
                    Text(listener.title).font(Q.footnote.weight(.semibold)).foregroundStyle(Q.ink).lineLimit(1)
                    Text(listener.state == .paused ? "Paused" : "Reading aloud \u{00B7} \(listener.part + 1) of \(max(1, listener.parts.count))")
                        .font(Q.caption)
                        .foregroundStyle(Q.muted)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: listener.stop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Q.muted)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Stop reading")
            }
            .padding(.leading, 8).padding(.trailing, 6).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Q.hairline))
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(Q.quick, value: listener.part)
            .accessibilityIdentifier("listen.bar")
        }
    }
}
