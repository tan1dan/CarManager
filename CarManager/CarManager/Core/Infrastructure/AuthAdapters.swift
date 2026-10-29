import Foundation

/// Account identity backed by Sign in with Apple alone.
///
/// Apple authenticates the user; this type only remembers who that was. The identifier lives
/// in the Keychain, so it survives a reinstall, and every launch re-asks Apple whether the
/// authorization still stands — the user can revoke it in Settings at any time.
public struct AppleAuthProvider: AuthProviding {
    let identityStore: any AppleIdentityStoring
    let credentialState: any AppleCredentialStateProviding
    let clock: any ClockProviding
    /// `nil` only where there is no real Apple authorization to withdraw: tests and the
    /// DEBUG test identity.
    let revoker: (any AppleAuthorizationRevoking)?

    public init(
        identityStore: any AppleIdentityStoring,
        credentialState: any AppleCredentialStateProviding,
        revoker: (any AppleAuthorizationRevoking)? = nil,
        clock: any ClockProviding
    ) {
        self.identityStore = identityStore
        self.credentialState = credentialState
        self.revoker = revoker
        self.clock = clock
    }

    public func restoreSession() async throws -> UserProfile? {
        guard let stored = try identityStore.load(), !stored.isSignedOut else { return nil }
        switch await credentialState.state(forUserID: stored.userID) {
        case .authorized:
            return stored.profile
        case .revoked, .notFound:
            // Access was taken away in Settings, or the Apple ID is gone from this device.
            try? identityStore.clear()
            return nil
        }
    }

    public func signInWithApple(_ credential: AppleIDCredential) async throws -> UserProfile {
        let existing = try? identityStore.load()
        let identity: StoredAppleIdentity
        if let existing, existing.userID == credential.userID {
            identity = existing.merging(credential)
        } else {
            identity = StoredAppleIdentity(
                userID: credential.userID,
                displayName: credential.fullName,
                email: credential.email,
                firstSignedInAt: clock.now
            )
        }
        try identityStore.save(identity)
        return identity.profile
    }

    /// Ends the session but remembers the name and email: Apple sends them only once.
    public func signOut() async throws {
        guard var stored = try identityStore.load() else { return }
        stored.isSignedOut = true
        try identityStore.save(stored)
    }

    public func updateDisplayName(_ name: String) async throws -> UserProfile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...UserProfile.maxDisplayNameLength).contains(trimmed.count) else {
            throw DomainError.validation(.emptyField(.name))
        }
        guard var stored = try identityStore.load() else { throw DomainError.authentication(.requiresReauthentication) }
        stored.displayName = trimmed
        try identityStore.save(stored)
        return stored.profile
    }

    public func revokeAuthorization() async throws {
        guard let revoker else { return }
        guard let stored = try identityStore.load() else { throw DomainError.authentication(.requiresReauthentication) }
        try await revoker.revoke(expectedUserID: stored.userID)
    }

    /// Forgets the identity on this device entirely. The data itself is erased by
    /// `DeleteAccount` before this runs.
    public func deleteAccount() async throws {
        try identityStore.clear()
    }
}

/// In-memory identity, for tests and for DEBUG runs that should start signed out.
public final class InMemoryAppleIdentityStore: AppleIdentityStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var identity: StoredAppleIdentity?

    public init(_ identity: StoredAppleIdentity? = nil) { self.identity = identity }

    public func load() throws -> StoredAppleIdentity? {
        lock.withLock { identity }
    }

    public func save(_ identity: StoredAppleIdentity) throws {
        lock.withLock { self.identity = identity }
    }

    public func clear() throws {
        lock.withLock { identity = nil }
    }
}

/// Always says the stored identity is fine — used by tests and previews.
public struct AlwaysAuthorizedCredentialState: AppleCredentialStateProviding {
    public init() {}
    public func state(forUserID userID: String) async -> AppleCredentialState { .authorized }
}
