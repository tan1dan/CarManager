import Foundation
import Observation

@MainActor
@Observable
final class PaywallViewModel {
    private(set) var presentation: PaywallPresentationModel = .placeholder
    private(set) var selectedProduct: ProductID = ProductCatalogIDs.promoted
    private(set) var isPurchasing = false
    private(set) var message: String?

    private let context: PaywallContext
    private let entitlements: EntitlementStore
    private let router: AppRouter
    private let formatter = PaywallFormatter()

    init(context: PaywallContext, entitlements: EntitlementStore, router: AppRouter) {
        self.context = context
        self.entitlements = entitlements
        self.router = router
    }

    func load() async {
        await entitlements.loadProducts()
        rebuild()
    }

    func select(_ productID: ProductID) {
        selectedProduct = productID
        rebuild()
    }

    func purchaseSelected() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }

        do {
            switch try await entitlements.purchase(selectedProduct) {
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
            message = ErrorPresenter.present(error).messageKey
        }
    }

    func restore() async {
        message = nil
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
            message = ErrorPresenter.present(error).messageKey
        }
    }

    private func rebuild() {
        presentation = formatter.makeModel(
            products: entitlements.products, selected: selectedProduct
        )
    }
}
