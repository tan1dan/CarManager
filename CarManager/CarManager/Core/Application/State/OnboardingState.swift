import Foundation
import Observation

/// Onboarding completion is a durable flag in preferences, not live application state.
@MainActor
@Observable
public final class OnboardingStore {
    public static let currentVersion = 1

    private let preferences: any PreferencesProviding
    public private(set) var isCompleted: Bool

    public init(preferences: any PreferencesProviding) {
        self.preferences = preferences
        self.isCompleted = preferences.onboardingCompletedVersion >= Self.currentVersion
    }

    public func complete() {
        preferences.onboardingCompletedVersion = Self.currentVersion
        isCompleted = true
    }

    public func reset() {
        preferences.onboardingCompletedVersion = 0
        isCompleted = false
    }
}
