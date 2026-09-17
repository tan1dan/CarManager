import Foundation

public protocol AuthProviding: Sendable {
    func restoreSession() async throws -> AuthSession?
    func signIn(_ credentials: AuthCredentials) async throws -> AuthSession
    func signUp(_ registration: AuthRegistration) async throws -> AuthSession
    func signOut() async throws
    func deleteAccount() async throws
    func requestPasswordReset(email: String) async throws
}
