import Foundation

/// A PURE function of value types. The whole gating matrix — the part most likely to carry a
/// product bug — is therefore unit-testable without StoreKit.
public enum FeatureGating {
    public static let freeVehicleLimit = 1
    public static let freeDailyAIRequests = 5

    public static func evaluate(
        _ feature: PremiumFeature,
        entitlement: Entitlement,
        usage: AIUsageSnapshot,
        vehicleCount: Int,
        now: Date
    ) -> FeatureAccess {
        if isPremiumActive(entitlement, now: now) { return .allowed }

        switch feature {
        case .multipleVehicles:
            return vehicleCount < freeVehicleLimit ? .allowed : .locked(.requiresPremium)

        case .aiChat:
            // Free tier gets a real taste. A user who has never seen the assistant answer a
            // question about THEIR car has no reason to buy it.
            guard let remaining = usage.remaining, remaining > 0 else {
                return .locked(.quotaExhausted(resetsAt: usage.resetsAt))
            }
            return .allowedWithQuota(remaining: remaining, resetsAt: usage.resetsAt)

        case .advancedAnalytics:
            // Allowed, but the period is clamped elsewhere — we never hide a user's raw records.
            return .allowed

        case .receiptScan, .dashboardScan, .damageAnalysis,
             .aiInsights, .pdfExport, .plateScan, .prioritySupport:
            return .locked(.requiresPremium)
        }
    }

    /// Grace window: a cached premium entitlement that cannot be re-verified stays valid for
    /// 7 days, so a paying subscriber is not locked out on a plane.
    public static func isPremiumActive(_ entitlement: Entitlement, now: Date) -> Bool {
        guard entitlement.tier == .premium else { return false }
        if entitlement.isInBillingRetry || entitlement.source == .grace { return true }
        if let expiresAt = entitlement.expiresAt, expiresAt < now { return false }
        return true
    }

    /// Free tier keeps all raw records; only the derived analytics window is limited.
    public static func clampedPeriod(_ requested: AnalyticsPeriod, entitlement: Entitlement, now: Date) -> AnalyticsPeriod {
        guard !isPremiumActive(entitlement, now: now) else { return requested }
        switch requested {
        case .allTime: return .year
        default: return requested
        }
    }

    public static func vehicleLimit(for entitlement: Entitlement, now: Date) -> Int? {
        isPremiumActive(entitlement, now: now) ? nil : freeVehicleLimit
    }
}
