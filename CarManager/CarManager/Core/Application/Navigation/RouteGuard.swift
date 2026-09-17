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

    public func evaluate(_ destination: AppDestination, context: Context) -> Decision {
        // 1. Onboarding blocks everything else.
        if !context.isOnboardingCompleted, destination.fullScreen != .onboarding {
            return .redirect(.fullScreen(.onboarding))
        }

        let requirements = Self.requirements(for: destination)

        // 2. Account required and the user is anonymous → sign in, then replay.
        if requirements.requiresAccount, !context.authState.isAuthenticated {
            return .present(.paywall(.feature(.aiChat))).replacingAuthGate()
        }

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
        requiresAccount = requiresAccount || other.requiresAccount
        requiresVehicle = requiresVehicle || other.requiresVehicle
        requiredFeature = requiredFeature ?? other.requiredFeature
        requiredDisclaimer = requiredDisclaimer ?? other.requiredDisclaimer
    }
}

private extension RouteGuard.Decision {
    /// An anonymous user hitting an account-gated route gets the sign-in flow, not a paywall.
    func replacingAuthGate() -> RouteGuard.Decision {
        .redirect(.fullScreen(.authentication(.signIn)))
    }
}
