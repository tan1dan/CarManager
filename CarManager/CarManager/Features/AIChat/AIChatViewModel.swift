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
    /// The car this conversation is about; `nil` is "another car" — general advice.
    var vehicleID: VehicleID?
    /// Garage cars to choose from, in garage order.
    let vehicleOptions: [VehicleOption]

    struct VehicleOption: Identifiable, Equatable {
        let id: VehicleID
        let name: String
    }
    private let askAI: AskAI
    private let loadConversation: LoadConversation
    private let featureGate: FeatureGate
    private let consumeQuota: () -> Void
    private let router: AppRouter
    private let clock: any ClockProviding
    /// The ONE cancellation handle for the stream.
    private var streamTask: Task<Void, Never>?

    init(
        conversationID: ConversationID?, vehicleID: VehicleID?, vehicleOptions: [VehicleOption] = [], askAI: AskAI,
        loadConversation: LoadConversation, featureGate: FeatureGate,
        consumeQuota: @escaping () -> Void, router: AppRouter, clock: any ClockProviding
    ) {
        self.conversationID = conversationID
        self.vehicleOptions = vehicleOptions
        // Default to the current car, but only if it is still in the garage.
        self.vehicleID = vehicleOptions.contains { $0.id == vehicleID } ? vehicleID : nil
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
        !composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && remainingCharacters >= 0
            && !isStreaming && !isLocked
    }

    /// The car is fixed once the conversation has started, so answers never mix two cars.
    var canChangeVehicle: Bool { conversationID == nil && messages.isEmpty && !isStreaming }

    /// "Audi A4", "Another car", or "Removed car" when a conversation's car left the garage.
    var vehicleTitle: String {
        guard let vehicleID else { return "Another car" }
        return vehicleOptions.first { $0.id == vehicleID }?.name ?? "Removed car"
    }

    /// Starters for an empty chat.
    let suggestions = [
        "My engine cranks but won't start. What could it be?",
        "What does a flashing check engine light mean?",
        "Brakes squeal when I stop. Is it safe to drive?"
    ]

    // MARK: - Actions

    func load() async {
        guard let conversationID, messages.isEmpty else { return }
        if let conversation = try? await loadConversation(id: conversationID) {
            messages = conversation.messages
            vehicleID = conversation.vehicleID
        }
    }

    /// The question whose answer failed. It is already saved, so Retry asks again without
    /// adding it a second time.
    private(set) var failedQuestion: String?
    private var questionSaved = false

    var remainingCharacters: Int { AskAI.maxMessageLength - composerText.trimmingCharacters(in: .whitespacesAndNewlines).count }

    func send(_ suggestion: String? = nil) {
        if let suggestion { composerText = suggestion }
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        guard text.count <= AskAI.maxMessageLength else {
            errorMessage = UserMessage.text(for: DomainError.ai(.messageTooLong(maxCharacters: AskAI.maxMessageLength)))
            return
        }
        composerText = ""
        ask(text, isRetry: false)
    }

    func retry() {
        guard let question = failedQuestion, !isStreaming else { return }
        ask(question, isRetry: true)
    }

    private func ask(_ text: String, isRetry: Bool) {
        // Gate FIRST: a locked feature short-circuits to the paywall with zero network calls.
        guard access.isAllowed else {
            if case .locked(let reason) = access {
                router.present(.paywall(RouteGuard.paywallContext(for: .aiChat, reason: reason)))
            }
            if !isRetry { composerText = text }
            return
        }

        streamingText = ""
        errorMessage = nil
        failedQuestion = nil
        isStreaming = true
        questionSaved = isRetry

        streamTask = Task { [askAI, conversationID, vehicleID] in
            do {
                let stream = askAI(AskAI.Input(conversationID: conversationID, vehicleID: vehicleID, text: text, isRetry: isRetry))
                for try await event in stream {
                    switch event {
                    case .conversationCreated(let id): self.conversationID = id
                    case .userMessageSaved(let message):
                        messages.append(message)
                        questionSaved = true
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
                // Saved question → offer Retry; unsaved (e.g. storage failed) → give the text back.
                if questionSaved { failedQuestion = text } else { composerText = text }
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
