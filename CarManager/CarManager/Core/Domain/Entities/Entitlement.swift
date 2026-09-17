import Foundation

public enum SubscriptionTier: String, Codable, Sendable { case free, premium }

public enum EntitlementSource: String, Codable, Sendable {
    case none, direct, familyShared, introOffer, grace
}

public struct Entitlement: Hashable, Codable, Sendable {
    public var tier: SubscriptionTier
    public var source: EntitlementSource
    public var expiresAt: Date?
    public var willAutoRenew: Bool
    public var isInBillingRetry: Bool
    public var lastVerifiedAt: Date

    public init(
        tier: SubscriptionTier, source: EntitlementSource, expiresAt: Date? = nil,
        willAutoRenew: Bool = false, isInBillingRetry: Bool = false, lastVerifiedAt: Date
    ) {
        self.tier = tier; self.source = source; self.expiresAt = expiresAt
        self.willAutoRenew = willAutoRenew; self.isInBillingRetry = isInBillingRetry
        self.lastVerifiedAt = lastVerifiedAt
    }

    public static let free = Entitlement(
        tier: .free, source: .none, lastVerifiedAt: Date(timeIntervalSince1970: 0)
    )
    public var isPremium: Bool { tier == .premium }
}

public enum PremiumFeature: String, CaseIterable, Codable, Sendable, Identifiable {
    case multipleVehicles, aiChat, receiptScan, dashboardScan, damageAnalysis,
         advancedAnalytics, aiInsights, pdfExport, plateScan, prioritySupport
    public var id: String { rawValue }
}

public enum LockReason: Hashable, Sendable {
    case requiresPremium
    case quotaExhausted(resetsAt: Date)
    case requiresSignIn
}

public enum FeatureAccess: Hashable, Sendable {
    case allowed
    case allowedWithQuota(remaining: Int, resetsAt: Date)
    case locked(LockReason)

    public var isAllowed: Bool {
        switch self {
        case .allowed, .allowedWithQuota: true
        case .locked: false
        }
    }
    public var lockReason: LockReason? {
        if case .locked(let r) = self { return r }
        return nil
    }
}

public struct AIUsageSnapshot: Hashable, Sendable {
    public let used: Int
    public let limit: Int?
    public let resetsAt: Date
    public let isAuthoritative: Bool

    public init(used: Int, limit: Int?, resetsAt: Date, isAuthoritative: Bool) {
        self.used = used; self.limit = limit; self.resetsAt = resetsAt
        self.isAuthoritative = isAuthoritative
    }
    public var remaining: Int? { limit.map { max(0, $0 - used) } }
}

public enum ProductID: String, CaseIterable, Codable, Sendable, Identifiable {
    case monthly = "app.carassistant.premium.monthly"
    case yearly = "app.carassistant.premium.yearly"
    public var id: String { rawValue }
}

public struct SubscriptionProduct: Identifiable, Hashable, Sendable {
    public let id: ProductID
    public let displayName: String
    /// Always StoreKit's localised price string — never formatted by us.
    public let displayPrice: String
    public let isEligibleForIntroOffer: Bool
    public let introOfferDescription: String?

    public init(
        id: ProductID, displayName: String, displayPrice: String,
        isEligibleForIntroOffer: Bool = false, introOfferDescription: String? = nil
    ) {
        self.id = id; self.displayName = displayName; self.displayPrice = displayPrice
        self.isEligibleForIntroOffer = isEligibleForIntroOffer
        self.introOfferDescription = introOfferDescription
    }
}

public enum PurchaseOutcome: Hashable, Sendable {
    case success(Entitlement)
    case pending
    case userCancelled
}

public enum RestoreOutcome: Hashable, Sendable {
    case restored(Entitlement)
    /// A neutral outcome, never an error.
    case nothingToRestore
}
