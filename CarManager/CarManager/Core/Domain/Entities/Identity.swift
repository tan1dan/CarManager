import Foundation

public enum AuthProvider: String, Codable, Sendable {
    case apple
}

/// ACCOUNT identity — gates AI, support and cross-device subscription restore.
/// It does NOT own the garage: data lives in the device's iCloud account.
public struct UserProfile: Identifiable, Hashable, Sendable {
    public static let maxDisplayNameLength = 40

    public let id: UserID
    public var displayName: String?
    public var email: String?
    public var authProvider: AuthProvider
    public let createdAt: Date

    public init(
        id: UserID = UserID(), displayName: String? = nil, email: String? = nil,
        authProvider: AuthProvider = .apple, createdAt: Date
    ) {
        self.id = id; self.displayName = displayName; self.email = email
        self.authProvider = authProvider; self.createdAt = createdAt
    }
}

/// What Sign in with Apple hands back. `fullName` and `email` arrive ONLY on the very first
/// authorization for this Apple ID; afterwards Apple sends the identifier alone, which is why
/// the app has to persist them itself.
public struct AppleIDCredential: Sendable, Equatable {
    /// Stable per Apple ID and developer team, and the same after a reinstall.
    public let userID: String
    public let fullName: String?
    public let email: String?

    public init(userID: String, fullName: String? = nil, email: String? = nil) {
        self.userID = userID; self.fullName = fullName; self.email = email
    }
}

/// The Apple identity kept on the device between launches, in the Keychain.
public extension UserProfile {
    /// No usable name yet — Apple did not share one and the user has not typed one.
    var needsDisplayName: Bool { (displayName ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    /// An Apple "Hide My Email" relay address: real, but not something to show as an identity.
    var hasPrivateRelayEmail: Bool { email?.lowercased().hasSuffix("privaterelay.appleid.com") ?? false }
}

public struct StoredAppleIdentity: Codable, Sendable, Equatable {
    /// Apple's own identifier — the key everything else hangs off.
    public let userID: String
    /// Minted once, on the first sign-in: Apple's identifier is not a UUID, and `UserID` is.
    public let accountID: UserID
    public var displayName: String?
    public var email: String?
    public let firstSignedInAt: Date
    /// Signing out keeps the name and email Apple will not send again; only this flips.
    public var isSignedOut: Bool

    public init(
        userID: String, accountID: UserID = UserID(), displayName: String? = nil,
        email: String? = nil, firstSignedInAt: Date, isSignedOut: Bool = false
    ) {
        self.userID = userID; self.accountID = accountID; self.displayName = displayName
        self.email = email; self.firstSignedInAt = firstSignedInAt; self.isSignedOut = isSignedOut
    }

    private enum CodingKeys: String, CodingKey { case userID, accountID, displayName, email, firstSignedInAt, isSignedOut }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decode(String.self, forKey: .userID)
        accountID = try c.decode(UserID.self, forKey: .accountID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        email = try c.decodeIfPresent(String.self, forKey: .email)
        firstSignedInAt = try c.decode(Date.self, forKey: .firstSignedInAt)
        // Identities written before this flag existed were signed in.
        isSignedOut = try c.decodeIfPresent(Bool.self, forKey: .isSignedOut) ?? false
    }

    public var profile: UserProfile {
        UserProfile(
            id: accountID, displayName: displayName, email: email,
            authProvider: .apple, createdAt: firstSignedInAt
        )
    }

    /// Apple sends the name and email only on the first authorization, so a later sign-in
    /// must not wipe what is already known.
    public func merging(_ credential: AppleIDCredential) -> StoredAppleIdentity {
        StoredAppleIdentity(
            userID: credential.userID, accountID: accountID,
            displayName: credential.fullName ?? displayName,
            email: credential.email ?? email,
            firstSignedInAt: firstSignedInAt
        )
    }
}

/// What Apple says about a stored identity at launch: the user can revoke the app's access
/// in Settings at any time, and signing in on another device does not tell this one.
public enum AppleCredentialState: Sendable, Equatable {
    case authorized, revoked, notFound
}

/// `.anonymous` is fully functional for every local feature — a user can build a garage
/// before ever creating an account.
public enum AuthState: Sendable, Equatable {
    case restoring
    case anonymous
    case authenticated(UserProfile)
    case signedOut

    public var profile: UserProfile? {
        if case .authenticated(let p) = self { return p }
        return nil
    }
    public var isAuthenticated: Bool { profile != nil }
}
