import SwiftUI
import AuthenticationServices

/// The welcome screen, built from Figma node 3:3794 ("Splash"), and the app's only door:
/// nothing is reachable until the user signs in with Apple.
struct OnboardingView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: AppleSignInViewModel?

    var body: some View {
        ZStack {
            SplashBackground()

            VStack(spacing: 0) {
                Spacer()
                SplashBrand()
                Spacer()

                VStack(spacing: 16) {
                    if let message = viewModel?.errorMessage {
                        Text(message)
                            .font(DS.Text.subheadline)
                            .foregroundStyle(DS.Colors.danger)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("signInError")
                    }

                    // The only way in: an Apple account is required for the whole app
                    // (ADR-016). Apple creates the account on first use, so "sign up" and
                    // "sign in" are the same button.
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await viewModel?.handle(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: DS.Layout.buttonHeight)
                    .clipShape(.capsule)
                    .disabled(viewModel?.isBusy ?? true)
                    .overlay {
                        if viewModel?.isBusy == true {
                            ProgressView().tint(.black)
                        }
                    }
                    .accessibilityIdentifier("onboardingSignIn")

                    legalNote
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
        }
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = AppleSignInViewModel(
                signIn: SignInWithApple(auth: model.dependencies.auth),
                authStore: model.auth,
                router: model.router
            )
        }
    }

    private var legalNote: some View {
        Text(Self.legalText)
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.5))
            .tint(Color.white.opacity(0.8))
            .multilineTextAlignment(.center)
            .environment(\.openURL, OpenURLAction { url in
                model?.router.present(.legal(url.host() == "privacy" ? .privacyPolicy : .termsOfUse))
                return .handled
            })
            .frame(minHeight: 32)
    }

    /// Internal scheme so a tap opens the in-app document instead of Safari.
    private static let legalText: AttributedString = {
        (try? AttributedString(markdown:
            "By continuing you agree to the [Terms](carmanager-legal://terms) and [Privacy Policy](carmanager-legal://privacy)."
        )) ?? AttributedString("By continuing you agree to the Terms and Privacy Policy.")
    }()
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
