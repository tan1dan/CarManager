import SwiftUI

/// The welcome screen, built from Figma node 3:3794 ("Splash").
///
/// Onboarding is marked complete only when the user actually gets in — by signing in (see
/// `RootView`) or by choosing guest mode. Backing out of Sign in returns here.
struct OnboardingView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: 0) {
                Spacer()
                SplashBrand()
                Spacer()

                VStack(spacing: 12) {
                    // The design has "Get started" and "I already have an account". With Sign
                    // in with Apple there is no difference between the two: Apple creates the
                    // account on first use.
                    AccentCapsuleButton(title: "Continue with Apple") { start() }
                        .accessibilityIdentifier("onboardingSignIn")
                    // Not in the design. Guest mode is part of the architecture: every local
                    // feature works without an account, so the way in must stay visible.
                    Button("Continue without an account") { completeAsGuest() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("onboardingSkip")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
        }
        .environment(\.colorScheme, .dark)
    }

    private func start() {
        model?.router.presentFullScreen(.authentication)
    }

    private func completeAsGuest() {
        guard let model else { return }
        model.onboarding.complete()
        model.auth.continueAsGuest()
    }
}

/// Logo, name and tagline — shared with the launch placeholder so restoring a session looks
/// like the same screen rather than a flash of something else.
struct SplashBrand: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.side")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(DS.Gradients.accentButton)
                        .shadow(color: Color(hex: 0x3B82F6).opacity(0.9), radius: 40, y: 30)
                )
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Car Manager")
                    .font(DS.Text.splash)
                    .tracking(DS.Text.splashTracking)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("The intelligent companion for everything your car needs.")
                    .font(.system(size: 15))
                    .tracking(DS.Text.defaultTracking)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .frame(maxWidth: 240)
            }
        }
    }
}

/// Deep-blue gradient (the vehicle card's) with a blue glow top-right and violet bottom-left.
struct SplashBackground: View {
    var body: some View {
        ZStack {
            DS.Gradients.vehicleCard
            GeometryReader { proxy in
                Circle()
                    .fill(Color(hex: 0x3782FA).opacity(0.4))
                    .frame(width: 256, height: 256)
                    .blur(radius: 100)
                    .position(x: proxy.size.width * 0.66, y: 0)
                Circle()
                    .fill(Color(hex: 0x7866F0).opacity(0.4))
                    .frame(width: 224, height: 224)
                    .blur(radius: 100)
                    .position(x: 72, y: proxy.size.height * 0.8)
            }
        }
        .ignoresSafeArea()
    }
}
