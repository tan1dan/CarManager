import Foundation
import AuthenticationServices
import UIKit

/// Revokes this app's Sign in with Apple authorization, as App Review requires when an
/// account is deleted (Guideline 5.1.1(v)).
///
/// No token is ever stored. The user confirms with Apple once more, which yields a one-time
/// authorization code; the `apple-revoke` Edge Function swaps it for a token with Apple and
/// revokes that token. The private key that signs the request lives only on the server.
public struct AppleAuthorizationRevoker: AppleAuthorizationRevoking {
    private let url: URL
    private let publishableKey: String
    private let session: URLSession

    public init(configuration: AIServiceConfiguration, session: URLSession = .shared) {
        self.url = configuration.functionURL.deletingLastPathComponent().appending(path: "apple-revoke")
        self.publishableKey = configuration.publishableKey
        self.session = session
    }

    public func revoke(expectedUserID: String) async throws {
        let credential = try await AppleReauthentication.run()
        // Another Apple ID on this device must not revoke — or stand in for — this account.
        guard credential.user == expectedUserID else { throw DomainError.authentication(.invalidCredentials) }
        guard let data = credential.authorizationCode, let code = String(data: data, encoding: .utf8) else {
            throw DomainError.authentication(.revocationFailed)
        }
        try await send(code: code)
    }

    func send(code: String) async throws {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONEncoder().encode(["authorizationCode": code])

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
            throw DomainError.authentication(.networkUnavailable)
        } catch {
            throw DomainError.authentication(.revocationFailed)
        }
        guard let http = response as? HTTPURLResponse else { throw DomainError.authentication(.revocationFailed) }
        switch http.statusCode {
        case 200..<300:
            return
        case 400 where (try? JSONDecoder().decode([String: String].self, from: data))?["error"] == "invalid_grant":
            // The code was too old (Apple gives 5 minutes) or already used.
            throw DomainError.authentication(.requiresReauthentication)
        default:
            throw DomainError.authentication(.revocationFailed)
        }
    }
}

/// A one-off Sign in with Apple prompt with no scopes: only "confirm it's you".
@MainActor
private final class AppleReauthentication: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, any Error>?
    private var controller: ASAuthorizationController?

    static func run() async throws -> ASAuthorizationAppleIDCredential {
        let flow = AppleReauthentication()
        return try await withCheckedThrowingContinuation { continuation in
            flow.start(continuation)
        }
    }

    private func start(_ continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, any Error>) {
        self.continuation = continuation
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        // The controller holds its delegate weakly; this keeps the flow alive until it ends.
        self.controller = controller
        controller.performRequests()
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                finish(.success(credential))
            } else {
                finish(.failure(DomainError.authentication(.invalidCredentials)))
            }
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        MainActor.assumeIsolated { finish(.failure(DomainError.fromAppleSignIn(error))) }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
        }
    }

    private func finish(_ result: Result<ASAuthorizationAppleIDCredential, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
        controller = nil
    }
}
