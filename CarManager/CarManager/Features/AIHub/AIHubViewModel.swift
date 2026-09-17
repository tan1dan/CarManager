import Foundation
import Observation

@MainActor
@Observable
final class AIHubViewModel {
    private(set) var state: ViewState<[ConversationSummary]> = .idle

    private let listConversations: ListConversations
    private let featureGate: FeatureGate

    init(listConversations: ListConversations, featureGate: FeatureGate) {
        self.listConversations = listConversations
        self.featureGate = featureGate
    }

    /// Display-only: it decides how a row RENDERS, never whether an action may run.
    func access(for feature: PremiumFeature) -> FeatureAccess { featureGate.evaluate(feature) }

    func load() async {
        state = .loading
        do {
            let summaries = try await listConversations(vehicleID: nil)
            state = summaries.isEmpty ? .empty : .loaded(summaries)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
