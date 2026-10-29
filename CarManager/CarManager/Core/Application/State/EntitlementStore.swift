import Foundation
import Observation

/// The single source of premium truth. No View and no other ViewModel ever touches StoreKit.
@MainActor
@Observable
public final class EntitlementStore {
    public private(set) var entitlement: Entitlement = .free
    public private(set) var products: [SubscriptionProduct] = []
    public private(set) var isLoadingProducts = false
    /// Set when the App Store could not be reached for prices; the paywall offers a retry.
    public private(set) var productsError: Error?
    public private(set) var aiUsage: AIUsageSnapshot

    private let subscriptions: any SubscriptionProviding
    private let clock: any ClockProviding
    private var updatesTask: Task<Void, Never>?

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
        observeUpdates()
        await loadProducts()
    }

    /// Re-reads the entitlement — on returning to the foreground, an expiry or a refund made
    /// while the app was closed is picked up without a relaunch.
    public func refresh() async {
        entitlement = await subscriptions.currentEntitlement()
    }

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await subscriptions.products()
            productsError = nil
        } catch {
            productsError = error
        }
    }

    /// Renewals, refunds, Ask to Buy approvals and purchases on another device arrive here
    /// while the app is running.
    private func observeUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self, subscriptions] in
            for await entitlement in await subscriptions.entitlementUpdates() {
                self?.entitlement = entitlement
            }
        }
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
