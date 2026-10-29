import Foundation

#if DEBUG
/// A StoreKit stand-in for tests, previews and DEBUG launch arguments. It does not exist in
/// Release builds: the shipped app always talks to `StoreKitSubscriptionProvider`.
///
/// Its products mirror App Store Connect's US prices, so a paywall screenshot taken with
/// `-debugPaywallPrices` shows exactly what a US customer sees.
public actor PreviewSubscriptionProvider: SubscriptionProviding {
    private var entitlement: Entitlement
    private let catalog: [SubscriptionProduct]
    private let clock: any ClockProviding

    public init(
        entitlement: Entitlement = .free,
        products: [SubscriptionProduct] = PreviewSubscriptionProvider.usProducts,
        clock: any ClockProviding = SystemClock()
    ) {
        self.entitlement = entitlement
        self.catalog = products
        self.clock = clock
    }

    public static let usProducts = [
        SubscriptionProduct(
            id: .monthly, displayName: "Premium Monthly", displayPrice: "$6.99",
            price: Decimal(string: "6.99")!, period: .month
        ),
        SubscriptionProduct(
            id: .yearly, displayName: "Premium Yearly", displayPrice: "$59.99",
            price: Decimal(string: "59.99")!, period: .year, pricePerMonth: "$4.99"
        )
    ]

    public func products() async throws -> [SubscriptionProduct] { catalog }

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
#endif
