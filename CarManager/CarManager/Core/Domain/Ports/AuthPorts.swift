import Foundation

/// Account identity. The app has exactly one way in — Sign in with Apple — and no
/// passwords, emails or third-party auth service behind it.
public protocol AuthProviding: Sendable {
    /// The identity kept from a previous launch, re-checked with Apple. `nil` when there is
    /// none, or when the user revoked the app in Settings.
    func restoreSession() async throws -> UserProfile?
    func signInWithApple(_ credential: AppleIDCredential) async throws -> UserProfile
    func signOut() async throws
    func deleteAccount() async throws
}

/// Where the Apple identity is persisted between launches (the Keychain in production).
public protocol AppleIdentityStoring: Sendable {
    func load() throws -> StoredAppleIdentity?
    func save(_ identity: StoredAppleIdentity) throws
    func clear() throws
}

/// Asks Apple whether a stored identity is still valid.
public protocol AppleCredentialStateProviding: Sendable {
    func state(forUserID userID: String) async -> AppleCredentialState
}
