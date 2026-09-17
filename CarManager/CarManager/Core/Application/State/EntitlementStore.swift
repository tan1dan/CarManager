import Foundation
import Observation

/// The single source of premium truth. No View and no other ViewModel ever touches StoreKit.
@MainActor
@Observable
public final class EntitlementStore {
    public private(set) var entitlement: Entitlement = .free
    public private(set) var products: [SubscriptionProduct] = []
    public private(set) var isLoadingProducts = false
    public private(set) var aiUsage: AIUsageSnapshot

    private let subscriptions: any SubscriptionProviding
    private let clock: any ClockProviding

    public init(subscriptions: any SubscriptionProviding, clock: any ClockProviding) {
        self.subscriptions = subscriptions
        self.clock = clock
        self.aiUsage = AIUsageSnapshot(
            used: 0,
            limit: FeatureGating.freeDailyAIRequests,
            resetsAt: clock.now.addingTimeInterval(86_400),
            isAuthoritative: false
        )
    }

    public var isPremium: Bool {
        FeatureGating.isPremiumActive(entitlement, now: clock.now)
    }

    public func bootstrap() async {
        entitlement = await subscriptions.currentEntitlement()
        await loadProducts()
    }

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        products = (try? await subscriptions.products()) ?? []
    }

    public func purchase(_ productID: ProductID) async throws -> PurchaseOutcome {
        let outcome = try await subscriptions.purchase(productID)
        if case .success(let newEntitlement) = outcome { entitlement = newEntitlement }
        return outcome
    }

    public func restore() async throws -> RestoreOutcome {
        let outcome = try await subscriptions.restore()
        if case .restored(let newEntitlement) = outcome { entitlement = newEntitlement }
        return outcome
    }

    public func openManageSubscriptions() async {
        await subscriptions.openManageSubscriptions()
    }

    /// The server is authoritative for AI quota; this is optimistic UI only.
    public func consumeAIRequest() {
        aiUsage = AIUsageSnapshot(
            used: aiUsage.used + 1, limit: aiUsage.limit,
            resetsAt: aiUsage.resetsAt, isAuthoritative: false
        )
    }
}
