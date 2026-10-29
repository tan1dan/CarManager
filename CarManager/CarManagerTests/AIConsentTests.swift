import Testing
import Foundation
@testable import CarManager

/// Guideline 5.1.2(i): nothing reaches the third-party AI before the user has agreed.
@Suite("Consent to share data with the AI provider")
@MainActor
struct AIConsentTests {
    private let guardEvaluator = RouteGuard()
    private let premium = Entitlement.premium(now: FixedClock().now)

    @Test("Every screen that sends data to the AI asks first", arguments: [
        AppDestination(tab: .ai, path: [.aiChat(nil)]),
        AppDestination.fullScreen(.camera(.receipt)),
        AppDestination.fullScreen(.camera(.dashboard)),
        AppDestination.fullScreen(.camera(.damage))
    ])
    func aiScreensAsk(_ destination: AppDestination) {
        let context = RouteGuard.Context.make(entitlement: premium, aiConsent: false)
        #expect(guardEvaluator.evaluate(destination, context: context) == .present(.aiConsent))
    }

    @Test("Once agreed, the same screens open", arguments: [
        AppDestination(tab: .ai, path: [.aiChat(nil)]),
        AppDestination.fullScreen(.camera(.receipt))
    ])
    func agreedOpens(_ destination: AppDestination) {
        let context = RouteGuard.Context.make(entitlement: premium, aiConsent: true)
        #expect(guardEvaluator.evaluate(destination, context: context) == .allow)
    }

    @Test("Screens that send nothing never ask", arguments: [
        AppDestination(tab: .ai, path: [.conversationHistory]),
        AppDestination(tab: .ai, path: [.scanHistory]),
        AppDestination.modal(.fuelEditor(.create(VehicleID()))),
        AppDestination.modal(.expenseEditor(.create(VehicleID())))
    ])
    func nonAIScreensDoNotAsk(_ destination: AppDestination) {
        let context = RouteGuard.Context.make(entitlement: premium, aiConsent: false)
        #expect(guardEvaluator.evaluate(destination, context: context) != .present(.aiConsent))
    }

    @Test("A free user sees the paywall first, not a consent for a feature they can't use")
    func paywallBeforeConsent() {
        let context = RouteGuard.Context.make(entitlement: .free, aiConsent: false)
        let decision = guardEvaluator.evaluate(.fullScreen(.camera(.receipt)), context: context)
        #expect(decision == .present(.paywall(.feature(.receiptScan))))
    }

    @Test("Agreeing continues to the screen the user was opening")
    func agreeingReplaysDestination() {
        let preferences = InMemoryPreferences(onboardingCompletedVersion: 1, aiConsentVersion: 0)
        let router = AppRouter {
            .make(entitlement: premium, aiConsent: preferences.aiDataSharingConsentVersion >= AIDataSharing.currentVersion)
        }
        router.push(.aiChat(nil), in: .ai)
        #expect(router.activeModal == .aiConsent)

        // What "Allow" does.
        preferences.aiDataSharingConsentVersion = AIDataSharing.currentVersion
        router.dismissModal()
        router.replayPendingDestination()

        #expect(router.activeModal == nil)
        #expect(router.router(for: .ai).path.last == .aiChat(nil))
    }

    @Test("Deleting the account forgets the consent")
    func deletionResetsConsent() async throws {
        let clock = FixedClock()
        let preferences = InMemoryPreferences(onboardingCompletedVersion: 1)
        let d = AppDependencies.testing(preferences: preferences, clock: clock)
        #expect(preferences.aiDataSharingConsentVersion == AIDataSharing.currentVersion)

        try await DeleteAccount(
            auth: d.auth, vehicles: d.vehicles, documents: d.documents, conversations: d.conversations,
            inbox: d.inbox, scans: d.scans, files: d.files, notifications: d.notifications, preferences: d.preferences
        )()

        #expect(preferences.aiDataSharingConsentVersion == 0)
    }
}
