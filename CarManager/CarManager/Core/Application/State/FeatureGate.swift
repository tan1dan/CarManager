import Foundation
import Observation

/// The live wrapper over the pure `FeatureGating` function.
/// Enforcement happens in exactly three places: RouteGuard, use cases, and — for display only —
/// presentation. A View asking "am I premium?" to decide whether to CALL something is the
/// anti-pattern this removes.
@MainActor
@Observable
public final class FeatureGate {
    private let entitlements: EntitlementStore
    private let vehicles: SelectedVehicleStore
    private let clock: any ClockProviding

    public init(entitlements: EntitlementStore, vehicles: SelectedVehicleStore, clock: any ClockProviding) {
        self.entitlements = entitlements
        self.vehicles = vehicles
        self.clock = clock
    }

    public func evaluate(_ feature: PremiumFeature) -> FeatureAccess {
        FeatureGating.evaluate(
            feature,
            entitlement: entitlements.entitlement,
            usage: entitlements.aiUsage,
            vehicleCount: vehicles.vehicleCount,
            now: clock.now
        )
    }

    public func canUse(_ feature: PremiumFeature) -> Bool { evaluate(feature).isAllowed }

    /// The authoritative check, called as the first statement of every gated use case —
    /// it catches deep links, notification taps and restored navigation state.
    public func requirePremium(_ feature: PremiumFeature) throws {
        guard evaluate(feature).isAllowed else {
            throw DomainError.subscription(.requiresPremium(feature))
        }
    }

    public func clampedPeriod(_ period: AnalyticsPeriod) -> AnalyticsPeriod {
        FeatureGating.clampedPeriod(period, entitlement: entitlements.entitlement, now: clock.now)
    }

    public func vehicleLimit() -> Int? {
        FeatureGating.vehicleLimit(for: entitlements.entitlement, now: clock.now)
    }
}
