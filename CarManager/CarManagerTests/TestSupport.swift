import Foundation
@testable import CarManager

/// The highest-leverage fake in the suite: production code never calls Date(), so every
/// date-sensitive test is deterministic.
struct FixedClock: ClockProviding {
    let now: Date
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    var timeZone: TimeZone { TimeZone(identifier: "UTC")! }

    init(_ now: Date = Date(timeIntervalSince1970: 1_760_000_000)) { self.now = now }
}

extension Entitlement {
    static func premium(now: Date) -> Entitlement {
        Entitlement(
            tier: .premium, source: .direct, expiresAt: now.addingTimeInterval(86_400 * 30),
            willAutoRenew: true, lastVerifiedAt: now
        )
    }
}

extension AIUsageSnapshot {
    static func available(now: Date) -> AIUsageSnapshot {
        AIUsageSnapshot(used: 0, limit: 5, resetsAt: now.addingTimeInterval(86_400), isAuthoritative: false)
    }
    static func exhausted(now: Date) -> AIUsageSnapshot {
        AIUsageSnapshot(used: 5, limit: 5, resetsAt: now.addingTimeInterval(86_400), isAuthoritative: false)
    }
}

@MainActor
extension RouteGuard.Context {
    static func make(
        onboardingCompleted: Bool = true,
        auth: AuthState = .anonymous,
        entitlement: Entitlement = .free,
        usage: AIUsageSnapshot? = nil,
        vehicleCount: Int = 1,
        hasVehicle: Bool = true,
        disclaimers: Set<Int> = [],
        now: Date = FixedClock().now
    ) -> RouteGuard.Context {
        RouteGuard.Context(
            isOnboardingCompleted: onboardingCompleted,
            authState: auth,
            entitlement: entitlement,
            aiUsage: usage ?? .available(now: now),
            vehicleCount: vehicleCount,
            hasSelectedVehicle: hasVehicle,
            acknowledgedDisclaimers: disclaimers,
            now: now
        )
    }
}

/// Builds a router whose guard context is fixed, so navigation decisions are testable
/// without constructing the whole app.
@MainActor
func makeRouter(context: RouteGuard.Context) -> AppRouter {
    AppRouter(contextProvider: { context })
}

@MainActor
func makeDependencies(clock: any ClockProviding = FixedClock()) -> AppDependencies {
    AppDependencies.testing(preferences: InMemoryPreferences(onboardingCompletedVersion: 1), clock: clock)
}
