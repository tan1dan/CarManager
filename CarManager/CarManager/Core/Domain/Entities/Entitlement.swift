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

/// App Store Connect product identifiers. One subscription group, two durations.
public enum ProductID: String, CaseIterable, Codable, Sendable, Identifiable {
    case monthly = "com.IvanZnak.aicarmanager.premium.monthly"
    case yearly = "com.IvanZnak.aicarmanager.premium.yearly"
    public var id: String { rawValue }
}

public enum SubscriptionPeriodUnit: String, Codable, Sendable {
    case week, month, year
}

/// An introductory offer exactly as StoreKit describes it for this account.
public struct IntroOffer: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case freeTrial, discounted }
    public let kind: Kind
    /// "1 week", "3 months" — already in the user's language.
    public let duration: String
    /// StoreKit's localised price for a discounted offer; nil for a free trial.
    public let price: String?

    public init(kind: Kind, duration: String, price: String?) {
        self.kind = kind; self.duration = duration; self.price = price
    }
}

public struct SubscriptionProduct: Identifiable, Hashable, Sendable {
    public let id: ProductID
    public let displayName: String
    /// Always StoreKit's localised price string — never formatted by us.
    public let displayPrice: String
    /// The raw amount, for comparing plans (savings). Never shown directly.
    public let price: Decimal
    public let period: SubscriptionPeriodUnit
    /// What a longer plan costs per month, formatted by StoreKit ("$4.99").
    public let pricePerMonth: String?
    public let isEligibleForIntroOffer: Bool
    public let introOffer: IntroOffer?

    public init(
        id: ProductID, displayName: String, displayPrice: String, price: Decimal = 0,
        period: SubscriptionPeriodUnit? = nil, pricePerMonth: String? = nil,
        isEligibleForIntroOffer: Bool = false, introOffer: IntroOffer? = nil
    ) {
        self.id = id; self.displayName = displayName; self.displayPrice = displayPrice
        self.price = price; self.period = period ?? (id == .yearly ? .year : .month)
        self.pricePerMonth = pricePerMonth
        self.isEligibleForIntroOffer = isEligibleForIntroOffer
        self.introOffer = introOffer
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
