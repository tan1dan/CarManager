import Foundation

/// StoreKit lives behind this port. Exactly one implementation file imports StoreKit,
/// and no View or ViewModel ever does.
public protocol SubscriptionProviding: Sendable {
    func products() async throws -> [SubscriptionProduct]
    func currentEntitlement() async -> Entitlement
    func purchase(_ productID: ProductID) async throws -> PurchaseOutcome
    func restore() async throws -> RestoreOutcome
    func openManageSubscriptions() async
}
