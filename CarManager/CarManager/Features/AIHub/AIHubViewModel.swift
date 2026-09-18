import Foundation
import Observation

@MainActor
@Observable
final class AIHubViewModel {
    private(set) var presentation: AIHubPresentationModel = .placeholder

    private let listConversations: ListConversations
    private let featureGate: FeatureGate
    private let clock: any ClockProviding

    init(listConversations: ListConversations, featureGate: FeatureGate, clock: any ClockProviding) {
        self.listConversations = listConversations
        self.featureGate = featureGate
        self.clock = clock
    }

    /// Lock state is display-only: it decides how a tile RENDERS, never whether an action
    /// may run. Enforcement is RouteGuard plus the use case.
    func load() async {
        let formatter = AIHubFormatter(now: clock.now, calendar: clock.calendar, locale: .current)
        let isLocked: (PremiumFeature) -> Bool = { [featureGate] in !featureGate.canUse($0) }

        if case .loaded = presentation.recentChats {} else {
            presentation.recentChats = .loading
        }
        do {
            let summaries = try await listConversations(vehicleID: nil)
            presentation = formatter.makeModel(summaries: summaries, isLocked: isLocked)
        } catch {
            presentation = AIHubPresentationModel(
                tools: AIHubFormatter.tools(isLocked: isLocked),
                recentChats: .failed(ErrorPresenter.present(error).messageKey),
                showsAllChatsLink: false
            )
        }
    }
}
