import Testing
import Foundation
@testable import CarManager

@Suite("Authentication routing")
@MainActor
struct AuthenticationRoutingTests {

    @Test("Onboarding blocks every other destination until completed")
    func onboardingBlocks() {
        let guardEvaluator = RouteGuard()
        let decision = guardEvaluator.evaluate(
            .tab(.garage), context: .make(onboardingCompleted: false)
        )
        #expect(decision == .redirect(.fullScreen(.onboarding)))
    }

    @Test("Onboarding itself is reachable while onboarding is incomplete")
    func onboardingReachable() {
        let decision = RouteGuard().evaluate(
            .fullScreen(.onboarding), context: .make(onboardingCompleted: false)
        )
        #expect(decision == .allow)
    }

    @Test("An anonymous user is sent to sign-in for account-gated destinations")
    func anonymousRedirectedToSignIn() {
        let decision = RouteGuard().evaluate(
            .tab(.ai, path: [.aiChat(nil)]), context: .make(auth: .anonymous)
        )
        #expect(decision == .redirect(.fullScreen(.authentication(.signIn))))
    }

    @Test("An anonymous user can still use the whole local garage")
    func anonymousCanUseGarage() {
        let context = RouteGuard.Context.make(auth: .anonymous)
        let vehicleID = VehicleID()

        #expect(RouteGuard().evaluate(.tab(.garage), context: context) == .allow)
        #expect(RouteGuard().evaluate(
            .tab(.garage, path: [.fuelHistory(vehicleID)]), context: context) == .allow)
        #expect(RouteGuard().evaluate(
            .modal(.fuelEditor(.create(vehicleID))), context: context) == .allow)
    }

    @Test("The intercepted destination is stored and replayed after sign-in")
    func pendingDestinationReplay() {
        let router = makeRouter(context: .make(auth: .anonymous))
        let target = AppDestination.tab(.ai, path: [.aiChat(nil)])

        router.navigate(to: target)
        #expect(router.pendingDestination == target)
        #expect(router.fullScreen == .authentication(.signIn))

        // Simulate a successful sign-in.
        let signedIn = makeRouter(context: .make(
            auth: .authenticated(UserProfile(authProvider: .email, createdAt: Date())),
            entitlement: .premium(now: FixedClock().now)
        ))
        signedIn.navigate(to: target)
        #expect(signedIn.selectedTab == .ai)
        #expect(signedIn.router(for: .ai).path == [.aiChat(nil)])
    }

    @Test("A destination needing a vehicle sends a user with none to the vehicle editor")
    func requiresVehicle() {
        let decision = RouteGuard().evaluate(
            .tab(.garage, path: [.fuelHistory(VehicleID())]),
            context: .make(vehicleCount: 0, hasVehicle: false)
        )
        #expect(decision == .redirect(AppDestination(tab: .garage, modal: .vehicleEditor(.create))))
    }
}

@Suite("Premium gating")
@MainActor
struct PremiumRoutingTests {
    private let now = FixedClock().now

    @Test("A free user tapping Scan Receipt gets the paywall, not the camera")
    func receiptScanGated() {
        let decision = RouteGuard().evaluate(
            .fullScreen(.camera(.receipt)), context: .make(entitlement: .free)
        )
        #expect(decision == .present(.paywall(.feature(.receiptScan))))
    }

    @Test("A premium user reaches the camera, once the disclaimer is acknowledged")
    func premiumReachesCamera() {
        let context = RouteGuard.Context.make(
            entitlement: .premium(now: now),
            disclaimers: [AIDisclaimer.dashboard.version]
        )
        #expect(RouteGuard().evaluate(.fullScreen(.camera(.dashboard)), context: context) == .allow)
    }

    @Test("Dashboard scan requires the disclaimer to be acknowledged first")
    func disclaimerRequired() {
        let decision = RouteGuard().evaluate(
            .fullScreen(.camera(.dashboard)),
            context: .make(entitlement: .premium(now: now), disclaimers: [])
        )
        #expect(decision == .present(.disclaimerAcknowledgement(.notProfessionalDiagnostics)))
    }

    @Test("An exhausted AI quota routes to the paywall with the quota context")
    func quotaExhausted() {
        let decision = RouteGuard().evaluate(
            .tab(.ai, path: [.aiChat(nil)]),
            context: .make(
                auth: .authenticated(UserProfile(authProvider: .email, createdAt: now)),
                entitlement: .free,
                usage: .exhausted(now: now)
            )
        )
        guard case .present(.paywall(.aiQuota)) = decision else {
            Issue.record("Expected an AI-quota paywall, got \(decision)")
            return
        }
    }

    @Test("The paywall records the destination and replays it after purchase")
    func paywallReplaysDestination() {
        let router = makeRouter(context: .make(entitlement: .free))
        let target = AppDestination.fullScreen(.camera(.receipt))

        router.navigate(to: target)
        #expect(router.activeModal == .paywall(.feature(.receiptScan)))
        #expect(router.pendingDestination == target)
    }
}

@Suite("Feature gating matrix")
struct FeatureGatingTests {
    private let now = FixedClock().now

    @Test("A free user may create their first vehicle but not a second")
    func vehicleLimit() {
        #expect(FeatureGating.evaluate(
            .multipleVehicles, entitlement: .free, usage: .available(now: now),
            vehicleCount: 0, now: now
        ) == .allowed)

        #expect(FeatureGating.evaluate(
            .multipleVehicles, entitlement: .free, usage: .available(now: now),
            vehicleCount: 1, now: now
        ) == .locked(.requiresPremium))
    }

    @Test("Premium removes the vehicle limit")
    func premiumUnlimitedVehicles() {
        #expect(FeatureGating.evaluate(
            .multipleVehicles, entitlement: .premium(now: now), usage: .available(now: now),
            vehicleCount: 12, now: now
        ) == .allowed)
        #expect(FeatureGating.vehicleLimit(for: .premium(now: now), now: now) == nil)
        #expect(FeatureGating.vehicleLimit(for: .free, now: now) == 1)
    }

    @Test("The free tier gets a real taste of AI chat, then hits the quota")
    func aiQuota() {
        let available = FeatureGating.evaluate(
            .aiChat, entitlement: .free, usage: .available(now: now), vehicleCount: 1, now: now
        )
        guard case .allowedWithQuota(let remaining, _) = available else {
            Issue.record("Expected a quota allowance, got \(available)")
            return
        }
        #expect(remaining == 5)

        let exhausted = FeatureGating.evaluate(
            .aiChat, entitlement: .free, usage: .exhausted(now: now), vehicleCount: 1, now: now
        )
        guard case .locked(.quotaExhausted) = exhausted else {
            Issue.record("Expected a quota lock, got \(exhausted)")
            return
        }
    }

    @Test("Scan features are premium-only for free users", arguments: [
        PremiumFeature.receiptScan, .dashboardScan, .damageAnalysis, .aiInsights, .pdfExport
    ])
    func scanFeaturesLocked(_ feature: PremiumFeature) {
        #expect(FeatureGating.evaluate(
            feature, entitlement: .free, usage: .available(now: now), vehicleCount: 1, now: now
        ) == .locked(.requiresPremium))
    }

    @Test("Every premium feature is allowed for a subscriber", arguments: PremiumFeature.allCases)
    func premiumAllowsEverything(_ feature: PremiumFeature) {
        #expect(FeatureGating.evaluate(
            feature, entitlement: .premium(now: now), usage: .exhausted(now: now),
            vehicleCount: 5, now: now
        ) == .allowed)
    }

    @Test("The free tier keeps its raw records; only the analytics window is clamped")
    func periodClamping() {
        #expect(FeatureGating.clampedPeriod(.allTime, entitlement: .free, now: now) == .year)
        #expect(FeatureGating.clampedPeriod(.month, entitlement: .free, now: now) == .month)
        #expect(FeatureGating.clampedPeriod(.allTime, entitlement: .premium(now: now), now: now) == .allTime)
    }

    @Test("A subscriber in billing retry keeps access rather than being locked out")
    func billingRetryKeepsAccess() {
        var entitlement = Entitlement.premium(now: now)
        entitlement.isInBillingRetry = true
        entitlement.expiresAt = now.addingTimeInterval(-86_400)

        #expect(FeatureGating.isPremiumActive(entitlement, now: now))
    }

    @Test("An expired entitlement stops granting access")
    func expiredEntitlement() {
        var entitlement = Entitlement.premium(now: now)
        entitlement.expiresAt = now.addingTimeInterval(-86_400)

        #expect(!FeatureGating.isPremiumActive(entitlement, now: now))
    }
}
