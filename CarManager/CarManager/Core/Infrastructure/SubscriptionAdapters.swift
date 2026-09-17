import Foundation

/// PLACEHOLDER for `StoreKitSubscriptionService`.
///
/// The real implementation is an actor that owns an app-lifetime `Transaction.updates`
/// listener and verifies every transaction before granting entitlement. It will be the ONLY
/// file in the app importing StoreKit — no View and no ViewModel ever will.
public actor StubSubscriptionProvider: SubscriptionProviding {
    private var entitlement: Entitlement
    private let clock: any ClockProviding

    public init(entitlement: Entitlement = .free, clock: any ClockProviding = SystemClock()) {
        self.entitlement = entitlement
        self.clock = clock
    }

    public func products() async throws -> [SubscriptionProduct] {
        [
            SubscriptionProduct(
                id: .monthly, displayName: "Premium Monthly", displayPrice: "€4.99",
                isEligibleForIntroOffer: true, introOfferDescription: "7-day free trial"
            ),
            SubscriptionProduct(
                id: .yearly, displayName: "Premium Yearly", displayPrice: "€39.00",
                isEligibleForIntroOffer: true, introOfferDescription: "7-day free trial"
            )
        ]
    }

    public func currentEntitlement() async -> Entitlement { entitlement }

    public func purchase(_ productID: ProductID) async throws -> PurchaseOutcome {
        let now = clock.now
        let granted = Entitlement(
            tier: .premium, source: .direct,
            expiresAt: now.addingTimeInterval(productID == .yearly ? 365 * 86_400 : 30 * 86_400),
            willAutoRenew: true, lastVerifiedAt: now
        )
        entitlement = granted
        return .success(granted)
    }

    public func restore() async throws -> RestoreOutcome {
        entitlement.isPremium ? .restored(entitlement) : .nothingToRestore
    }

    public func openManageSubscriptions() async {}
}
