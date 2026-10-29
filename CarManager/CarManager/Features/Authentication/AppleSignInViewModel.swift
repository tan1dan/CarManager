import Foundation
import Observation
import AuthenticationServices

@MainActor
@Observable
final class AppleSignInViewModel {
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    private let signIn: SignInWithApple
    private let authStore: AuthSessionStore
    private let router: AppRouter

    init(signIn: SignInWithApple, authStore: AuthSessionStore, router: AppRouter) {
        self.signIn = signIn
        self.authStore = authStore
        self.router = router
    }

    /// Takes the result straight from `SignInWithAppleButton`, so no presentation anchor or
    /// delegate plumbing is needed.
    func handle(_ result: Result<ASAuthorization, any Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = AuthMessages.text(for: DomainError.authentication(.invalidCredentials))
                return
            }
            await submit(AppleIDCredential(credential))
        case .failure(let error):
            let domain = DomainError.fromAppleSignIn(error)
            // A cancelled sheet is the user changing their mind, not something to report.
            if case .authentication(.cancelled) = domain { return }
            errorMessage = AuthMessages.text(for: domain)
        }
    }

    private func submit(_ credential: AppleIDCredential) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            authStore.adopt(try await signIn(credential))
            router.dismissFullScreen()
            // Land on the screen the user originally asked for, not back at Home.
            router.replayPendingDestination()
        } catch {
            errorMessage = AuthMessages.text(for: error)
        }
    }
}

/// User-facing wording for sign-in failures.
enum AuthMessages {
    static func text(for error: any Error) -> String {
        guard let error = error as? DomainError, case .authentication(let auth) = error else {
            return String(localized: "Something went wrong. Please try again.")
        }
        switch auth {
        case .cancelled: return String(localized: "Sign-in was cancelled.")
        case .invalidCredentials: return String(localized: "Apple couldn't verify that sign-in. Please try again.")
        case .appleAccountUnavailable:
            return String(localized: "Sign in with Apple isn't available. Check that you're signed into iCloud in Settings.")
        case .networkUnavailable: return String(localized: "You're offline. Check your connection and try again.")
        case .requiresReauthentication: return String(localized: "Please sign in again.")
        case .providerFailed, .revocationFailed: return String(localized: "Something went wrong. Please try again.")
        }
    }
}
