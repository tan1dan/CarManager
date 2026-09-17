import Foundation
import Observation

@MainActor
@Observable
final class PaywallViewModel {
    private(set) var products: [SubscriptionProduct] = []
    private(set) var message: String?
    private(set) var state: ViewState<Bool> = .idle

    private let entitlements: EntitlementStore
    private let router: AppRouter

    init(entitlements: EntitlementStore, router: AppRouter) {
        self.entitlements = entitlements
        self.router = router
    }

    func load() async {
        state = .loading
        await entitlements.loadProducts()
        products = entitlements.products
        state = .loaded(true)
    }

    func purchase(_ productID: ProductID) async {
        do {
            switch try await entitlements.purchase(productID) {
            case .success:
                router.dismissModal()
                // Land on the screen that triggered the paywall, not back at Home.
                router.replayPendingDestination()
            case .pending:
                // Ask to Buy. A first-class outcome, not an error.
                message = "Waiting for approval"
            case .userCancelled:
                break
            }
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func restore() async {
        do {
            switch try await entitlements.restore() {
            case .restored:
                router.dismissModal()
                router.replayPendingDestination()
            case .nothingToRestore:
                // Neutral information, never an error alert.
                message = "Nothing to restore"
            }
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
