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

    public init(
        identityStore: any AppleIdentityStoring,
        credentialState: any AppleCredentialStateProviding,
        clock: any ClockProviding
    ) {
        self.identityStore = identityStore
        self.credentialState = credentialState
        self.clock = clock
    }

    public func restoreSession() async throws -> UserProfile? {
        guard let stored = try identityStore.load() else { return nil }
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

    public func signOut() async throws {
        try identityStore.clear()
    }

    /// Forgets the account on this device. The garage itself lives in the user's iCloud, and
    /// the Apple authorization can only be revoked by the user in Settings, so deleting the
    /// app's own data is a separate step owned by the CloudKit layer.
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
