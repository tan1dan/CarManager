import Foundation

/// Auth, premium, vehicle-presence and disclaimer interception — as a pure-ish function over
/// value types, so the entire gating matrix is unit-testable with no UI.
@MainActor
public struct RouteGuard: Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        case redirect(AppDestination)
        case present(ModalRoute)
    }

    /// A snapshot of everything the guard needs. Passing a snapshot rather than the live stores
    /// is what keeps this testable without constructing the whole app.
    public struct Context: Sendable, Equatable {
        public var isOnboardingCompleted: Bool
        public var authState: AuthState
        public var entitlement: Entitlement
        public var aiUsage: AIUsageSnapshot
        public var vehicleCount: Int
        public var hasSelectedVehicle: Bool
        public var acknowledgedDisclaimers: Set<Int>
        public var now: Date

        public init(
            isOnboardingCompleted: Bool, authState: AuthState, entitlement: Entitlement,
            aiUsage: AIUsageSnapshot, vehicleCount: Int, hasSelectedVehicle: Bool,
            acknowledgedDisclaimers: Set<Int>, now: Date
        ) {
            self.isOnboardingCompleted = isOnboardingCompleted
            self.authState = authState
            self.entitlement = entitlement
            self.aiUsage = aiUsage
            self.vehicleCount = vehicleCount
            self.hasSelectedVehicle = hasSelectedVehicle
            self.acknowledgedDisclaimers = acknowledgedDisclaimers
            self.now = now
        }
    }

    public init() {}

    /// The only things a signed-out user can reach: the welcome screen and the legal
    /// documents it links to.
    static func isReachableSignedOut(_ destination: AppDestination) -> Bool {
        switch destination.fullScreen {
        case .onboarding?: return true
        default: break
        }
        switch destination.modal {
        case .legal?: return true
        default: return false
        }
    }

    public func evaluate(_ destination: AppDestination, context: Context) -> Decision {
        // 1. No Apple account, no app (ADR-016). The root view already shows the welcome
        //    screen in that state; this rule makes deep links and notification taps obey the
        //    same law. The destination is kept and replayed once the user signs in.
        let signedIn = context.authState.isAuthenticated
        if (!signedIn || !context.isOnboardingCompleted), !Self.isReachableSignedOut(destination) {
            return .redirect(.fullScreen(.onboarding))
        }

        let requirements = Self.requirements(for: destination)

        // 3. A vehicle is required and none exists → send them to create one.
        if requirements.requiresVehicle, !context.hasSelectedVehicle {
            return .redirect(AppDestination(tab: .garage, modal: .vehicleEditor(.create)))
        }

        // 4. Premium gating.
        if let feature = requirements.requiredFeature {
            let access = FeatureGating.evaluate(
                feature,
                entitlement: context.entitlement,
                usage: context.aiUsage,
                vehicleCount: context.vehicleCount,
                now: context.now
            )
            switch access {
            case .allowed, .allowedWithQuota:
                break
            case .locked(let reason):
                return .present(.paywall(Self.paywallContext(for: feature, reason: reason)))
            }
        }

        // 5. Disclaimer acknowledgement for the AI vision flows.
        if let disclaimer = requirements.requiredDisclaimer {
            let version = disclaimer == .notProfessionalDiagnostics
                ? AIDisclaimer.dashboard.version
                : AIDisclaimer.damage.version
            if !context.acknowledgedDisclaimers.contains(version) {
                return .present(.disclaimerAcknowledgement(disclaimer))
            }
        }

        return .allow
    }

    static func requirements(for destination: AppDestination) -> RouteRequirements {
        var merged = RouteRequirements.none
        for route in destination.path { merged.merge(route.requirements) }
        if let modal = destination.modal { merged.merge(modal.requirements) }
        if let fullScreen = destination.fullScreen { merged.merge(fullScreen.requirements) }
        return merged
    }

    static func paywallContext(for feature: PremiumFeature, reason: LockReason) -> PaywallContext {
        switch reason {
        case .quotaExhausted(let resetsAt): .aiQuota(resetAt: resetsAt)
        case .requiresPremium: feature == .multipleVehicles ? .vehicleLimit : .feature(feature)
        case .requiresSignIn: .feature(feature)
        }
    }
}

private extension RouteRequirements {
    mutating func merge(_ other: RouteRequirements) {
        requiresVehicle = requiresVehicle || other.requiresVehicle
        requiredFeature = requiredFeature ?? other.requiredFeature
        requiredDisclaimer = requiredDisclaimer ?? other.requiredDisclaimer
    }
}

