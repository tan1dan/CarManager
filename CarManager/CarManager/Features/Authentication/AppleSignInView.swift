import SwiftUI
import AuthenticationServices

/// The only way into an account: Sign in with Apple. Shown full screen when a feature needs
/// an account (AI, support, subscription restore) and from Profile.
///
/// There is no email, password or verification code anywhere in the app — Apple does the
/// authenticating, and the garage itself lives in the user's iCloud.
struct AppleSignInView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: AppleSignInViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel {
                content(viewModel)
            }
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

    private func content(_ viewModel: AppleSignInViewModel) -> some View {
        AuthScaffold(
            title: "Sign in",
            subtitle: "Sign in with Apple to use the AI assistant, restore your subscription and reach support.",
            onBack: { model?.router.dismissFullScreen() },
            errorMessage: viewModel.errorMessage
        ) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                Task { await viewModel.handle(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: DS.Layout.buttonHeight)
            .clipShape(.capsule)
            .disabled(viewModel.isBusy)
            .opacity(viewModel.isBusy ? 0.5 : 1)
            .accessibilityIdentifier("appleSignInButton")

            VStack(alignment: .leading, spacing: 8) {
                Label("Your garage stays in your iCloud", systemImage: "icloud")
                Label("Apple can hide your email address", systemImage: "eye.slash")
            }
            .font(DS.Text.caption)
            .foregroundStyle(DS.Colors.textSecondary)
            .labelStyle(.titleAndIcon)

            Button("Continue without an account") {
                model?.auth.continueAsGuest()
                model?.router.dismissFullScreen()
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .accessibilityIdentifier("authContinueAsGuest")
        }
    }
}
