import Foundation
import Observation

@MainActor
@Observable
public final class AuthSessionStore {
    public private(set) var state: AuthState = .restoring

    private let auth: any AuthProviding

    public init(auth: any AuthProviding) { self.auth = auth }

    /// Non-blocking: the garage renders regardless of the outcome. A network hiccup at launch
    /// must never keep a user out of their own offline data.
    public func restore() async {
        do {
            if let session = try await auth.restoreSession() {
                state = .authenticated(session.profile)
            } else {
                state = .anonymous
            }
        } catch {
            state = .anonymous
        }
    }

    public func signIn(_ credentials: AuthCredentials) async throws {
        let session = try await auth.signIn(credentials)
        state = .authenticated(session.profile)
    }

    public func signUp(_ registration: AuthRegistration) async throws {
        let session = try await auth.signUp(registration)
        state = .authenticated(session.profile)
    }

    /// Signing out clears the account session. It does NOT delete local or iCloud data —
    /// the garage belongs to the device's iCloud account, not to the app account.
    public func signOut() async throws {
        try await auth.signOut()
        state = .signedOut
    }

    public func deleteAccount() async throws {
        try await auth.deleteAccount()
        state = .signedOut
    }

    /// Adopts a session produced by a use case, so the ViewModel never has to reach into
    /// the auth provider itself.
    public func adopt(_ session: AuthSession) { state = .authenticated(session.profile) }

    public func continueAsGuest() { state = .anonymous }
}
