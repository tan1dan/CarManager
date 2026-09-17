import Foundation

/// A local stand-in for the backend auth service. Real sign-in exchanges an Apple/Google/email
/// credential at the backend for a session; tokens then live in the Keychain.
///
/// PLACEHOLDER: no network, no Keychain yet. It exists so the authentication FLOW is real
/// and testable at this stage.
public actor StubAuthProvider: AuthProviding {
    private var session: AuthSession?
    private let clock: any ClockProviding
    private let shouldRestore: Bool

    public init(clock: any ClockProviding = SystemClock(), restoresSession: Bool = false) {
        self.clock = clock
        self.shouldRestore = restoresSession
    }

    public func restoreSession() async throws -> AuthSession? {
        guard shouldRestore else { return session }
        if session == nil { session = Self.makeSession(provider: .email, email: "demo@example.com", now: clock.now) }
        return session
    }

    public func signIn(_ credentials: AuthCredentials) async throws -> AuthSession {
        let created: AuthSession = switch credentials {
        case .email(let email, _): Self.makeSession(provider: .email, email: email, now: clock.now)
        case .apple: Self.makeSession(provider: .apple, email: nil, now: clock.now)
        case .google: Self.makeSession(provider: .google, email: nil, now: clock.now)
        }
        session = created
        return created
    }

    public func signUp(_ registration: AuthRegistration) async throws -> AuthSession {
        let created = Self.makeSession(
            provider: .email, email: registration.email, name: registration.name, now: clock.now
        )
        session = created
        return created
    }

    public func signOut() async throws { session = nil }
    public func deleteAccount() async throws { session = nil }
    public func requestPasswordReset(email: String) async throws {}

    private static func makeSession(
        provider: AuthProvider, email: String?, name: String? = nil, now: Date
    ) -> AuthSession {
        AuthSession(
            profile: UserProfile(
                displayName: name, email: email, authProvider: provider, createdAt: now
            ),
            accessToken: UUID().uuidString,
            expiresAt: now.addingTimeInterval(3600)
        )
    }
}
