import Foundation
import Observation

@MainActor
@Observable
final class ProfileViewModel {
    private(set) var state: ViewState<UserStatistics> = .idle
    private(set) var presentation: ProfilePresentationModel = .placeholder

    private let loadStatistics: LoadUserStatistics
    private let formatter: ProfileFormatter
    private let authStore: AuthSessionStore
    private let entitlements: EntitlementStore

    init(
        loadStatistics: LoadUserStatistics,
        formatter: ProfileFormatter,
        authStore: AuthSessionStore,
        entitlements: EntitlementStore
    ) {
        self.loadStatistics = loadStatistics
        self.formatter = formatter
        self.authStore = authStore
        self.entitlements = entitlements
    }

    func load() async {
        state = .loading
        do {
            let statistics = try await loadStatistics()
            rebuild(with: statistics)
            state = .loaded(statistics)
        } catch {
            rebuild(with: .empty)
            state = .failed(ErrorPresenter.present(error))
        }
    }

    /// Rebuilds the display model from current auth and entitlement state without re-querying.
    func refreshPresentation() {
        rebuild(with: state.value ?? .empty)
    }

    private func rebuild(with statistics: UserStatistics) {
        presentation = formatter.makeModel(
            authState: authStore.state,
            entitlement: entitlements.entitlement,
            isPremium: entitlements.isPremium,
            statistics: statistics
        )
    }

    /// Signing out clears the account session only. Local and iCloud data are untouched.
    func signOut() async {
        do {
            try await authStore.signOut()
            refreshPresentation()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
