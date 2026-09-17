import Foundation
import Observation

/// Owns the five global stores, the router and the use-case factories.
/// This is a composition object, not an `AppState` god-object: each store has one narrow
/// responsibility and is independently testable.
@MainActor
@Observable
public final class AppModel {
    public let dependencies: AppDependencies
    public let auth: AuthSessionStore
    public let vehicles: SelectedVehicleStore
    public let entitlements: EntitlementStore
    public let onboarding: OnboardingStore
    public let sync: SyncStatusStore
    public let featureGate: FeatureGate
    public private(set) var router: AppRouter!

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.auth = AuthSessionStore(auth: dependencies.auth)
        self.vehicles = SelectedVehicleStore(
            vehicles: dependencies.vehicles, preferences: dependencies.preferences
        )
        self.entitlements = EntitlementStore(
            subscriptions: dependencies.subscriptions, clock: dependencies.clock
        )
        self.onboarding = OnboardingStore(preferences: dependencies.preferences)
        self.sync = SyncStatusStore(provider: dependencies.syncStatus)
        self.featureGate = FeatureGate(
            entitlements: entitlements, vehicles: vehicles, clock: dependencies.clock
        )

        // The router asks for a guard context on every navigation, so gating always sees
        // current state without the router holding the stores.
        self.router = AppRouter { [auth, entitlements, vehicles, onboarding, dependencies] in
            RouteGuard.Context(
                isOnboardingCompleted: onboarding.isCompleted,
                authState: auth.state,
                entitlement: entitlements.entitlement,
                aiUsage: entitlements.aiUsage,
                vehicleCount: vehicles.vehicleCount,
                hasSelectedVehicle: vehicles.selected != nil,
                acknowledgedDisclaimers: dependencies.preferences.acknowledgedDisclaimerVersions,
                now: dependencies.clock.now
            )
        }
    }

    /// Launch sequence. Only the garage load gates first paint — session restoration and
    /// entitlement refresh run alongside it, so a network hiccup never keeps a user out of
    /// their own offline data.
    public func bootstrap() async {
        #if DEBUG
        await DebugSeed.run(dependencies)
        #endif
        async let session: Void = auth.restore()
        async let entitlement: Void = entitlements.bootstrap()
        await vehicles.bootstrap()
        _ = await (session, entitlement)
    }

    public var selectedVehicleID: VehicleID? { vehicles.selected?.id }

    public func acknowledgeDisclaimer(_ kind: DisclaimerKind) {
        let version = kind == .notProfessionalDiagnostics
            ? AIDisclaimer.dashboard.version
            : AIDisclaimer.damage.version
        dependencies.preferences.acknowledgedDisclaimerVersions.insert(version)
    }
}
