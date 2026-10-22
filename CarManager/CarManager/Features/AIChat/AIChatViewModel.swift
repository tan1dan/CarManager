import Foundation
import Observation

/// AI chat (Figma 18 · answering 35 · limit reached 36).
@MainActor
@Observable
final class AIChatViewModel {
    private(set) var messages: [AIMessage] = []
    private(set) var streamingText = ""
    private(set) var isStreaming = false
    private(set) var errorMessage: String?
    var composerText = ""

    private var conversationID: ConversationID?
    private let vehicleID: VehicleID?
    private let askAI: AskAI
    private let loadConversation: LoadConversation
    private let featureGate: FeatureGate
    private let consumeQuota: () -> Void
    private let router: AppRouter
    private let clock: any ClockProviding
    /// The ONE cancellation handle for the stream.
    private var streamTask: Task<Void, Never>?

    init(
        conversationID: ConversationID?, vehicleID: VehicleID?, askAI: AskAI,
        loadConversation: LoadConversation, featureGate: FeatureGate,
        consumeQuota: @escaping () -> Void, router: AppRouter, clock: any ClockProviding
    ) {
        self.conversationID = conversationID
        self.vehicleID = vehicleID
        self.askAI = askAI
        self.loadConversation = loadConversation
        self.featureGate = featureGate
        self.consumeQuota = consumeQuota
        self.router = router
        self.clock = clock
    }

    // MARK: - Display state

    private var access: FeatureAccess { featureGate.evaluate(.aiChat) }

    /// When the free daily questions are used up.
    var limitResetsAt: Date? {
        if case .locked(.quotaExhausted(let resetsAt)) = access { return resetsAt }
        return nil
    }

    var isLocked: Bool { !access.isAllowed }

    /// "Online", "Typing…", "2 free questions left today".
    var status: String {
        if isStreaming { return "Typing…" }
        switch access {
        case .allowed: return "Online"
        case .allowedWithQuota(let remaining, _):
            return "\(remaining) free question\(remaining == 1 ? "" : "s") left today"
        case .locked(.quotaExhausted):
            let limit = FeatureGating.freeDailyAIRequests
            return "\(limit) of \(limit) free questions used"
        case .locked: return "Premium"
        }
    }

    var canSend: Bool {
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming && !isLocked
    }

    /// Starters for an empty chat. Questions only — the answers come from the user's own data.
    let suggestions = [
        "Why did my fuel consumption change?",
        "What does the check engine light mean?",
        "When is my next service due?"
    ]

    // MARK: - Actions

    func load() async {
        guard let conversationID, messages.isEmpty else { return }
        if let conversation = try? await loadConversation(id: conversationID) {
            messages = conversation.messages
        }
    }

    func send(_ suggestion: String? = nil) {
        if let suggestion { composerText = suggestion }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        // Gate FIRST: a locked feature short-circuits to the paywall with zero network calls.
        guard access.isAllowed else {
            if case .locked(let reason) = access {
                router.present(.paywall(RouteGuard.paywallContext(for: .aiChat, reason: reason)))
            }
            return
        }

        composerText = ""
        streamingText = ""
        errorMessage = nil
        isStreaming = true

        streamTask = Task { [askAI, conversationID, vehicleID] in
            do {
                let stream = askAI(AskAI.Input(conversationID: conversationID, vehicleID: vehicleID, text: text))
                for try await event in stream {
                    switch event {
                    case .conversationCreated(let id): self.conversationID = id
                    case .userMessageSaved(let message):
                        messages.append(message)
                        consumeQuota()
                    // Deltas accumulate in memory only — never one write per token.
                    case .delta(let chunk): streamingText += chunk
                    case .assistantCompleted(let message):
                        messages.append(message)
                        streamingText = ""
                    }
                }
                isStreaming = false
            } catch {
                keepPartialAnswer()
                isStreaming = false
                if case DomainError.ai(.cancelled) = error { return }
                errorMessage = UserMessage.text(for: error)
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        keepPartialAnswer()
        isStreaming = false
    }

    func upgrade() {
        router.present(.paywall(.aiQuota(resetAt: limitResetsAt ?? clock.now)))
    }

    /// A stopped answer stays on screen, marked as cut short — never silently discarded.
    private func keepPartialAnswer() {
        guard !streamingText.isEmpty else { return }
        messages.append(AIMessage(role: .assistant, text: streamingText, isPartial: true, createdAt: clock.now))
        streamingText = ""
    }
}

/// Conversations (Figma 37).
@MainActor
@Observable
final class ConversationsViewModel {
    struct Row: Equatable, Identifiable {
        var id: ConversationID
        var title: String
        var subtitle: String
    }
    struct Group: Equatable, Identifiable {
        var id: String { title }
        var title: String
        var rows: [Row]
    }

    var searchText = ""
    private(set) var state: ViewState<[ConversationSummary]> = .idle

    private let list: ListConversations
    private let delete: DeleteConversation
    private let format: DisplayFormat
    private let clock: any ClockProviding

    init(list: ListConversations, delete: DeleteConversation, format: DisplayFormat, clock: any ClockProviding) {
        self.list = list
        self.delete = delete
        self.format = format
        self.clock = clock
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let summaries = try await list(vehicleID: nil)
            state = summaries.isEmpty ? .empty : .loaded(summaries)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func remove(_ id: ConversationID) async {
        try? await delete(id: id)
        await load()
    }

    var groups: [Group] {
        guard case .loaded(let summaries) = state else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let now = clock.now
        let relative = RelativeDateTimeFormatter()
        relative.locale = format.locale
        relative.unitsStyle = .short
        var today: [Row] = [], earlier: [Row] = []
        for summary in summaries.sorted(by: { $0.updatedAt > $1.updatedAt })
        where query.isEmpty || summary.title.localizedCaseInsensitiveContains(query) {
            let isToday = format.calendar.isDate(summary.updatedAt, inSameDayAs: now)
            let when = isToday ? relative.localizedString(for: summary.updatedAt, relativeTo: now)
                               : format.shortDate(summary.updatedAt, relativeTo: now)
            let row = Row(id: summary.id, title: summary.title,
                          subtitle: "\(when) · \(summary.messageCount) message\(summary.messageCount == 1 ? "" : "s")")
            if isToday { today.append(row) } else { earlier.append(row) }
        }
        return [Group(title: "Today", rows: today), Group(title: "Earlier", rows: earlier)].filter { !$0.rows.isEmpty }
    }
}
