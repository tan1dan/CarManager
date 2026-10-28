import Testing
import Foundation
@testable import CarManager

@Suite("Sign in with Apple")
struct AppleAuthTests {
    private let clock = FixedClock()

    private func makeProvider(
        stored: StoredAppleIdentity? = nil,
        state: AppleCredentialState = .authorized
    ) -> (AppleAuthProvider, InMemoryAppleIdentityStore) {
        let store = InMemoryAppleIdentityStore(stored)
        let provider = AppleAuthProvider(
            identityStore: store,
            credentialState: FixedCredentialState(state),
            clock: clock
        )
        return (provider, store)
    }

    @Test("The first sign-in keeps the name and email Apple sends only once")
    func firstSignIn() async throws {
        let (provider, store) = makeProvider()

        let profile = try await provider.signInWithApple(
            AppleIDCredential(userID: "001.abc", fullName: "Alex Lindström", email: "alex@example.com")
        )

        #expect(profile.displayName == "Alex Lindström")
        #expect(profile.email == "alex@example.com")
        #expect(profile.authProvider == .apple)
        #expect(store.loaded()?.userID == "001.abc")
    }

    @Test("A later sign-in sends no name — the stored one must survive")
    func laterSignInKeepsName() async throws {
        let (provider, _) = makeProvider()
        let first = try await provider.signInWithApple(
            AppleIDCredential(userID: "001.abc", fullName: "Alex", email: "alex@example.com")
        )

        let second = try await provider.signInWithApple(AppleIDCredential(userID: "001.abc"))

        #expect(second.displayName == "Alex")
        #expect(second.email == "alex@example.com")
        // The same Apple ID keeps the same account identifier across sign-ins.
        #expect(second.id == first.id)
    }

    @Test("A different Apple ID starts a new account rather than inheriting the old name")
    func differentAppleID() async throws {
        let stored = StoredAppleIdentity(
            userID: "001.abc", displayName: "Alex", email: "alex@example.com",
            firstSignedInAt: clock.now
        )
        let (provider, _) = makeProvider(stored: stored)

        let profile = try await provider.signInWithApple(AppleIDCredential(userID: "002.xyz"))

        #expect(profile.displayName == nil)
        #expect(profile.email == nil)
        #expect(profile.id != stored.accountID)
    }

    @Test("Restoring returns the stored profile while Apple still authorises it")
    func restoreAuthorized() async throws {
        let stored = StoredAppleIdentity(userID: "001.abc", displayName: "Alex", firstSignedInAt: clock.now)
        let (provider, _) = makeProvider(stored: stored, state: .authorized)

        #expect(try await provider.restoreSession()?.displayName == "Alex")
    }

    @Test("Access revoked in Settings signs the user out and forgets the identity",
          arguments: [AppleCredentialState.revoked, .notFound])
    func restoreRevoked(state: AppleCredentialState) async throws {
        let stored = StoredAppleIdentity(userID: "001.abc", firstSignedInAt: clock.now)
        let (provider, store) = makeProvider(stored: stored, state: state)

        #expect(try await provider.restoreSession() == nil)
        #expect(store.loaded() == nil)
    }

    @Test("Nothing stored means nothing to restore, and Apple is not asked")
    func restoreEmpty() async throws {
        let (provider, _) = makeProvider()
        #expect(try await provider.restoreSession() == nil)
    }

    @Test("Signing out ends the session but keeps the details Apple sends only once")
    func signOut() async throws {
        let stored = StoredAppleIdentity(userID: "001.abc", email: "a@b.c", firstSignedInAt: clock.now)
        let (provider, store) = makeProvider(stored: stored)

        try await provider.signOut()

        #expect(try await provider.restoreSession() == nil)
        #expect(store.loaded()?.isSignedOut == true)
        #expect(store.loaded()?.email == "a@b.c")
    }

    @Test("Deleting the account forgets the identity completely")
    func deleteForgets() async throws {
        let (provider, store) = makeProvider(stored: StoredAppleIdentity(userID: "001.abc", firstSignedInAt: clock.now))
        try await provider.deleteAccount()
        #expect(store.loaded() == nil)
    }

    @Test("An empty Apple identifier is refused before anything is stored")
    func emptyIdentifier() async {
        let (provider, store) = makeProvider()
        let signIn = SignInWithApple(auth: provider)

        await #expect(throws: DomainError.authentication(.invalidCredentials)) {
            _ = try await signIn(AppleIDCredential(userID: ""))
        }
        #expect(store.loaded() == nil)
    }
}

@Suite("Auth session store")
@MainActor
struct AuthSessionStoreTests {
    private let clock = FixedClock()

    @Test("A revoked authorization leaves the app usable as a guest, not stuck")
    func revokedFallsBackToGuest() async {
        let provider = AppleAuthProvider(
            identityStore: InMemoryAppleIdentityStore(
                StoredAppleIdentity(userID: "001.abc", firstSignedInAt: clock.now)
            ),
            credentialState: FixedCredentialState(.revoked),
            clock: clock
        )
        let store = AuthSessionStore(auth: provider)

        await store.restore()

        #expect(store.state == .anonymous)
        #expect(!store.state.isAuthenticated)
    }
}

private extension InMemoryAppleIdentityStore {
    /// `#expect` cannot swallow a `throws` in every position; the store never throws anyway.
    func loaded() -> StoredAppleIdentity? { try? load() }
}

private struct FixedCredentialState: AppleCredentialStateProviding {
    let value: AppleCredentialState
    init(_ value: AppleCredentialState) { self.value = value }
    func state(forUserID userID: String) async -> AppleCredentialState { value }
}
