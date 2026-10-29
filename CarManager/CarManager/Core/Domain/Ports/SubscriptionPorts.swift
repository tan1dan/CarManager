import Foundation

/// StoreKit lives behind this port. Exactly one implementation file imports StoreKit,
/// and no View or ViewModel ever does.
public protocol SubscriptionProviding: Sendable {
    func products() async throws -> [SubscriptionProduct]
    func currentEntitlement() async -> Entitlement
    func purchase(_ productID: ProductID) async throws -> PurchaseOutcome
    func restore() async throws -> RestoreOutcome
    func openManageSubscriptions() async
    /// Entitlement changes that happen outside a purchase: renewals, refunds, expiry,
    /// Ask to Buy approvals, family sharing, purchases on another device.
    func entitlementUpdates() async -> AsyncStream<Entitlement>
}

public extension SubscriptionProviding {
    func entitlementUpdates() async -> AsyncStream<Entitlement> { AsyncStream { $0.finish() } }
}
