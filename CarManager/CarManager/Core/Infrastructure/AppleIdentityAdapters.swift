import Foundation
import Security
import AuthenticationServices

/// Keeps the Apple identity in the Keychain.
///
/// It is not a secret, but it is the one credential-shaped thing the app stores, and the
/// architecture puts those in the Keychain rather than UserDefaults. `ThisDeviceOnly` keeps it
/// off encrypted backups restored onto another device, where Apple's authorization would not
/// apply anyway.
struct KeychainAppleIdentityStore: AppleIdentityStoring {
    let service: String
    let account: String

    init(service: String = "com.carmanager.identity", account: String = "apple") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() throws -> StoredAppleIdentity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return try JSONDecoder().decode(StoredAppleIdentity.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw DomainError.persistence(.readFailed("Keychain read failed: \(status)"))
        }
    }

    func save(_ identity: StoredAppleIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let insert = baseQuery.merging(attributes) { _, new in new }
            let insertStatus = SecItemAdd(insert as CFDictionary, nil)
            guard insertStatus == errSecSuccess else {
                throw DomainError.persistence(.writeFailed("Keychain insert failed: \(insertStatus)"))
            }
        } else if status != errSecSuccess {
            throw DomainError.persistence(.writeFailed("Keychain update failed: \(status)"))
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DomainError.persistence(.writeFailed("Keychain delete failed: \(status)"))
        }
    }
}

/// Asks Apple whether the stored authorization still stands.
struct SystemAppleCredentialState: AppleCredentialStateProviding {
    func state(forUserID userID: String) async -> AppleCredentialState {
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { state, _ in
                switch state {
                case .authorized: continuation.resume(returning: .authorized)
                case .revoked: continuation.resume(returning: .revoked)
                case .notFound, .transferred: continuation.resume(returning: .notFound)
                @unknown default: continuation.resume(returning: .notFound)
                }
            }
        }
    }
}

extension AppleIDCredential {
    /// Apple sends the name in parts and only on the first authorization.
    init(_ credential: ASAuthorizationAppleIDCredential) {
        let name = PersonNameComponentsFormatter.localizedString(
            from: credential.fullName ?? PersonNameComponents(), style: .default
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        self.init(
            userID: credential.user,
            fullName: name.isEmpty ? nil : name,
            // `email` arrives only on the very first authorization. The identity token carries
            // it on every sign-in, so a returning user still has one. Display only — the token
            // is not verified here and is never trusted for anything else.
            email: credential.email ?? Self.email(fromIdentityToken: credential.identityToken)
        )
    }

    /// Reads the `email` claim from a JWT's payload without verifying it.
    static func email(fromIdentityToken token: Data?) -> String? {
        guard let token, let jwt = String(data: token, encoding: .utf8) else { return nil }
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = claims["email"] as? String, !email.isEmpty
        else { return nil }
        return email
    }
}

extension DomainError {
    /// Maps what `ASAuthorizationController` reports. A cancelled sheet is not a failure.
    static func fromAppleSignIn(_ error: any Error) -> DomainError {
        guard let error = error as? ASAuthorizationError else {
            return .authentication(.providerFailed(error.localizedDescription))
        }
        switch error.code {
        case .canceled: return .authentication(.cancelled)
        case .notHandled, .unknown: return .authentication(.appleAccountUnavailable)
        case .failed, .invalidResponse: return .authentication(.invalidCredentials)
        default: return .authentication(.providerFailed(error.localizedDescription))
        }
    }
}
