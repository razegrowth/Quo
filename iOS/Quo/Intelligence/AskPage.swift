import SwiftUI

/// Ask This Page, from the ^ toolbar: questions about the page in front,
/// answered by Apple's model on the iPhone from the page's own words. Each
/// answer streams in as it's made, and follows on from the ones before.
/// Nothing leaves the phone. Not offered without Apple Intelligence.
@MainActor
final class AskPage: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let question: String
        var answer = ""
        var done = false
        var failed = false
    }

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var title = ""
    @Published private(set) var site = ""
    /// Reading the page, before the first question can be asked.
    @Published private(set) var loading = true
    @Published private(set) var empty = false
    private var chat: OnDevice.PageChat?
    private var busy = false

    func start(with tab: Tab) async {
        let host = tab.host ?? ""
        site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        title = tab.shownTitle
        guard let page = await tab.readableSoon() else {
            loading = false
            empty = true
            return
        }
        title = page.title
        chat = OnDevice.PageChat(title: page.title, host: site, text: page.text)
        loading = false
    }

    var answering: Bool { busy }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy, let chat else { return }
        busy = true
        let turn = Turn(question: question)
        withAnimation(Q.settle) { turns.append(turn) }
        Task {
            let ok = await chat.ask(question) { [weak self] said in
                guard let self, let index = self.turns.firstIndex(where: { $0.id == turn.id }) else { return }
                self.turns[index].answer = said
            }
            if let index = turns.firstIndex(where: { $0.id == turn.id }) {
                withAnimation(Q.quick) {
                    turns[index].done = true
                    turns[index].failed = !ok && turns[index].answer.isEmpty
                }
            }
            busy = false
        }
    }
}

struct AskPageSheet: View {
    let tab: Tab
    @StateObject private var ask = AskPage()
    @State private var typed = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    private let starters = ["Sum it up", "What are the key points?", "Anything I should watch out for?"]

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if ask.loading {
                            Shimmer().padding(.top, 4)
                        } else if ask.empty {
                            Text("There\u{2019}s nothing on this page to ask about.")
                                .font(Q.body).foregroundStyle(Q.muted)
                        } else if ask.turns.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(starters, id: \.self) { starter in
                                    Button { ask.ask(starter) } label: {
                                        Text(starter)
                                            .font(Q.body)
                                            .foregroundStyle(Q.ink)
                                            .padding(.horizontal, 14).padding(.vertical, 10)
                                            .background(Q.tile, in: Capsule())
                                    }
                                    .buttonStyle(PressStyle())
                                }
                            }
                        }
                        ForEach(ask.turns) { turn in
                            TurnView(turn: turn).id(turn.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: ask.turns.last?.answer) { _, _ in
                    if let last = ask.turns.last { scroll.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) { field }
            .navigationTitle("Ask This Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        }
        .tint(Q.ink)
        .task { await ask.start(with: tab) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            SiteMark(host: ask.site, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ask.title).font(Q.bodyEmphasis).foregroundStyle(Q.ink).lineLimit(2)
                Label("Answered on this iPhone", systemImage: "apple.intelligence")
                    .font(Q.footnote).foregroundStyle(Q.muted)
            }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField("Ask about this page", text: $typed, axis: .vertical)
                .lineLimit(1...4)
                .font(Q.body)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Q.tile, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityIdentifier("ask.field")
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Q.ground)
                    .frame(width: 40, height: 40)
                    .background(Q.ink.opacity(canSend ? 1 : 0.25), in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Ask")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var canSend: Bool {
        !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !ask.answering && !ask.loading && !ask.empty
    }

    private func send() {
        guard canSend else { return }
        ask.ask(typed)
        typed = ""
    }
}

private struct TurnView: View {
    let turn: AskPage.Turn

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.question)
                .font(Q.bodyEmphasis)
                .foregroundStyle(Q.ink)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Q.tile, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
            if turn.failed {
                Text("Couldn\u{2019}t answer that just now.").font(Q.body).foregroundStyle(Q.muted)
            } else if turn.answer.isEmpty {
                Shimmer()
            } else {
                Text(turn.answer)
                    .font(Q.body)
                    .foregroundStyle(Q.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
