import Foundation
import Observation

@MainActor
@Observable
final class AIChatViewModel {
    private(set) var messages: [AIMessage] = []
    private(set) var streamingText = ""
    private(set) var isStreaming = false
    private(set) var state: ViewState<Bool> = .idle
    var composerText = ""

    private var conversationID: ConversationID?
    private let vehicleID: VehicleID?
    private let askAI: AskAI
    private let loadConversation: LoadConversation
    private let featureGate: FeatureGate
    private let router: AppRouter
    /// The ONE cancellation handle for the stream.
    private var streamTask: Task<Void, Never>?

    init(
        conversationID: ConversationID?, vehicleID: VehicleID?, askAI: AskAI,
        loadConversation: LoadConversation, featureGate: FeatureGate, router: AppRouter
    ) {
        self.conversationID = conversationID
        self.vehicleID = vehicleID
        self.askAI = askAI
        self.loadConversation = loadConversation
        self.featureGate = featureGate
        self.router = router
    }

    func load() async {
        guard let conversationID else { return }
        state = .loading
        if let conversation = try? await loadConversation(id: conversationID) {
            messages = conversation.messages
        }
        state = .loaded(true)
    }

    func send() {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Gate FIRST: a locked feature short-circuits to the paywall with zero network calls.
        let access = featureGate.evaluate(.aiChat)
        guard access.isAllowed else {
            if let reason = access.lockReason {
                router.present(.paywall(RouteGuard.paywallContext(for: .aiChat, reason: reason)))
            }
            return
        }

        composerText = ""
        streamingText = ""
        isStreaming = true

        streamTask = Task { [askAI, conversationID, vehicleID] in
            do {
                let stream = askAI(AskAI.Input(
                    conversationID: conversationID, vehicleID: vehicleID, text: text
                ))
                for try await event in stream {
                    switch event {
                    case .conversationCreated(let id): self.conversationID = id
                    case .userMessageSaved(let message): messages.append(message)
                    // Deltas accumulate in memory only — never one write per token.
                    case .delta(let chunk): streamingText += chunk
                    case .assistantCompleted(let message):
                        messages.append(message)
                        streamingText = ""
                    }
                }
                isStreaming = false
            } catch {
                isStreaming = false
                state = .failed(ErrorPresenter.present(error))
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}
