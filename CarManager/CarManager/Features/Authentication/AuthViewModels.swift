import Foundation
import Observation

/// ViewModels hold USE CASES and the global stores — never a repository, never StoreKit,
/// never SwiftData.
@MainActor
@Observable
final class SignInViewModel {
    var email = ""
    var password = ""
    private(set) var state: ViewState<Bool> = .idle

    private let signIn: SignIn
    private let authStore: AuthSessionStore
    private let router: AppRouter

    init(signIn: SignIn, authStore: AuthSessionStore, router: AppRouter) {
        self.signIn = signIn
        self.authStore = authStore
        self.router = router
    }

    func signIn() async {
        state = .loading
        do {
            let session = try await signIn(email: email, password: password)
            finish(session)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func signInWithApple() async {
        state = .loading
        do { finish(try await signIn.withApple(identityToken: "placeholder-apple-token")) }
        catch { state = .failed(ErrorPresenter.present(error)) }
    }

    func signInWithGoogle() async {
        state = .loading
        do { finish(try await signIn.withGoogle(idToken: "placeholder-google-token")) }
        catch { state = .failed(ErrorPresenter.present(error)) }
    }

    private func finish(_ session: AuthSession) {
        authStore.adopt(session)
        state = .loaded(true)
        router.dismissFullScreen()
        // Land on the screen the user originally asked for, not back at Home.
        router.replayPendingDestination()
    }
}

@MainActor
@Observable
final class SignUpViewModel {
    var name = ""
    var email = ""
    var password = ""
    var acceptedTerms = false
    private(set) var state: ViewState<Bool> = .idle

    private let signUp: SignUp
    private let authStore: AuthSessionStore
    private let router: AppRouter

    init(signUp: SignUp, authStore: AuthSessionStore, router: AppRouter) {
        self.signUp = signUp
        self.authStore = authStore
        self.router = router
    }

    func signUp() async {
        state = .loading
        do {
            let session = try await signUp(AuthRegistration(
                name: name, email: email, password: password, acceptedTerms: acceptedTerms
            ))
            authStore.adopt(session)
            state = .loaded(true)
            router.dismissFullScreen()
            router.replayPendingDestination()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
