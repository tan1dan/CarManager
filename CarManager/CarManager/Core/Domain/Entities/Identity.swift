import Foundation

public enum AuthProvider: String, Codable, Sendable {
    case apple, google, email
}

/// ACCOUNT identity — gates AI, support and cross-device subscription restore.
/// It does NOT own the garage: data lives in the device's iCloud account.
public struct UserProfile: Identifiable, Hashable, Sendable {
    public let id: UserID
    public var displayName: String?
    public var email: String?
    public var authProvider: AuthProvider
    public let createdAt: Date

    public init(
        id: UserID = UserID(), displayName: String? = nil, email: String? = nil,
        authProvider: AuthProvider, createdAt: Date
    ) {
        self.id = id; self.displayName = displayName; self.email = email
        self.authProvider = authProvider; self.createdAt = createdAt
    }
}

public struct AuthSession: Hashable, Sendable {
    public let profile: UserProfile
    public let accessToken: String
    public let expiresAt: Date
    public init(profile: UserProfile, accessToken: String, expiresAt: Date) {
        self.profile = profile; self.accessToken = accessToken; self.expiresAt = expiresAt
    }
}

public enum AuthCredentials: Sendable {
    case email(String, password: String)
    case apple(identityToken: String)
    case google(idToken: String)
}

public struct AuthRegistration: Sendable {
    public var name: String
    public var email: String
    public var password: String
    public var acceptedTerms: Bool
    public init(name: String, email: String, password: String, acceptedTerms: Bool) {
        self.name = name; self.email = email; self.password = password
        self.acceptedTerms = acceptedTerms
    }
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
