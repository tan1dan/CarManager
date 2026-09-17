import SwiftUI

/// Placeholder UI. Structure and navigation only — visual design is the next stage.
struct OnboardingView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Onboarding")
                    .accessibilityIdentifier("onboardingTitle")

                Button("Get started") { start(.signUp) }
                    .accessibilityIdentifier("onboardingGetStarted")

                Button("I already have an account") { start(.signIn) }
                    .accessibilityIdentifier("onboardingSignIn")

                // Anonymous mode is fully functional for every local feature — a user can
                // build a garage before ever creating an account.
                Button("Continue without an account") { completeAsGuest() }
                    .accessibilityIdentifier("onboardingSkip")
            }
            .navigationTitle("Welcome")
        }
    }

    private func start(_ entry: AuthEntryPoint) {
        guard let model else { return }
        model.onboarding.complete()
        model.router.presentFullScreen(.authentication(entry))
    }

    private func completeAsGuest() {
        guard let model else { return }
        model.onboarding.complete()
        model.auth.continueAsGuest()
    }
}
