import Foundation
import NaturalLanguage

/// Checks a test run can ask for at launch, with QUO_TRACE set; nothing in
/// any other run. Each writes what it found to the log (Trace).
///
///   QUO_ROUTE_TEST="github|how do I boil an egg"  where typed words go (Routing)
///   QUO_MEANING_TEST="cheap flights to lisbon"    history pages near in meaning (Meaning)
///   QUO_FAKE_MODEL=1                              a stand-in for Apple's model (OnDevice)
///   QUO_QUIET=1                                   Listen to Page reads silently
@MainActor
enum TestRuns {
    static func start() {
        guard Trace.on else { return }
        Trace.mark("apple intelligence \(OnDevice.why)")
        Task { await OnDevice.probe() }
        let environment = ProcessInfo.processInfo.environment
        if let phrase = environment["QUO_MEANING_TEST"] {
            Meaning.shared.build(History.shared.visits)
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Trace.mark("meaning available \(Meaning.shared.available) word \(NLEmbedding.wordEmbedding(for: .english) != nil)")
                for (title, score) in Meaning.shared.scores(phrase, in: History.shared.visits).prefix(8) {
                    Trace.mark(String(format: "meaning %.2f %@", score, title))
                }
                Trace.mark("meaning picked \(History.shared.matchesWithMeaning(phrase).map(\.title).joined(separator: " | "))")
            }
        }
        if let phrases = environment["QUO_ROUTE_TEST"] {
            for phrase in phrases.split(separator: "|").map(String.init) {
                Trace.mark("route \(phrase) -> \(AppSettings.shared.destination(for: phrase)?.absoluteString ?? "nil") question=\(Routing.isQuestion(phrase))")
            }
        }
    }
}
