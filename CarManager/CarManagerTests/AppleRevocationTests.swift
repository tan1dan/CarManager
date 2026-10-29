import Testing
import Foundation
@testable import CarManager

/// Records calls, and can fail the way Apple or the network does.
private final class SpyRevoker: AppleAuthorizationRevoking, @unchecked Sendable {
    private let lock = NSLock()
    private var _userIDs: [String] = []
    let failure: DomainError?

    init(failure: DomainError? = nil) { self.failure = failure }
    var userIDs: [String] { lock.withLock { _userIDs } }

    func revoke(expectedUserID: String) async throws {
        lock.withLock { _userIDs.append(expectedUserID) }
        if let failure { throw failure }
    }
}

@Suite("Account deletion revokes Sign in with Apple", .serialized)
@MainActor
struct AppleRevocationTests {
    private let clock = FixedClock()
    private let host = "revoke-ref.supabase.co"

    private func app(revoker: SpyRevoker) async throws -> (AppDependencies, VehicleID) {
        let store = InMemoryAppleIdentityStore()
        let auth = AppleAuthProvider(
            identityStore: store, credentialState: AlwaysAuthorizedCredentialState(), revoker: revoker, clock: clock
        )
        let d = AppDependencies.testing(preferences: InMemoryPreferences(onboardingCompletedVersion: 1), clock: clock) {
            $0.auth = auth
        }
        _ = try await auth.signInWithApple(AppleIDCredential(userID: "apple.user.1", fullName: "Ivan"))
        let car = try await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock)(
            VehicleDraft(brand: "Porsche", model: "Macan", initialOdometer: Odometer(kilometers: 30_000)), vehicleLimit: nil
        ).vehicle.id
        return (d, car)
    }

    private func erase(_ d: AppDependencies) -> DeleteAccount {
        DeleteAccount(
            auth: d.auth, vehicles: d.vehicles, documents: d.documents, conversations: d.conversations,
            inbox: d.inbox, scans: d.scans, files: d.files, notifications: d.notifications, preferences: d.preferences
        )
    }

    @Test("The signed-in Apple ID is revoked before anything is erased")
    func revokesThenErases() async throws {
        let revoker = SpyRevoker()
        let (d, _) = try await app(revoker: revoker)

        try await erase(d)()

        #expect(revoker.userIDs == ["apple.user.1"])
        #expect(try await d.vehicles.all().isEmpty)
        #expect(try await d.auth.restoreSession() == nil)
    }

    @Test("Dismissing the Apple prompt deletes nothing", arguments: [
        DomainError.authentication(.cancelled),
        .authentication(.networkUnavailable),
        .authentication(.revocationFailed),
        .authentication(.invalidCredentials)
    ])
    func failedRevocationKeepsEverything(_ failure: DomainError) async throws {
        let (d, car) = try await app(revoker: SpyRevoker(failure: failure))

        await #expect(throws: failure) { try await erase(d)() }

        #expect(try await d.vehicles.vehicle(id: car) != nil)
        #expect(try await d.auth.restoreSession() != nil)
    }

    // MARK: - The request to apple-revoke

    private func revoker(status: Int, body: String) -> AppleAuthorizationRevoker {
        StubURLProtocol.reset(host: host)
        StubURLProtocol.setHandler({ _ in (status, Data(body.utf8)) }, host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return AppleAuthorizationRevoker(
            configuration: AIServiceConfiguration(
                functionURL: URL(string: "https://\(host)/functions/v1/car-assistant")!, publishableKey: "sb_publishable_test"
            ),
            session: URLSession(configuration: config)
        )
    }

    @Test("Posts the one-time code to apple-revoke with the publishable key")
    func requestShape() async throws {
        try await revoker(status: 200, body: #"{"revoked":true}"#).send(code: "c0de.from.apple")

        let request = try #require(StubURLProtocol.requests(host: host).first)
        #expect(request.url?.path == "/functions/v1/apple-revoke")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        #expect(body == ["authorizationCode": "c0de.from.apple"])
    }

    @Test("An expired or reused code asks the user to confirm again")
    func expiredCode() async {
        await #expect(throws: DomainError.authentication(.requiresReauthentication)) {
            try await revoker(status: 400, body: #"{"error":"invalid_grant"}"#).send(code: "old.code.value")
        }
    }

    @Test("Any other server failure keeps the account and says so")
    func serverFailure() async {
        await #expect(throws: DomainError.authentication(.revocationFailed)) {
            try await revoker(status: 502, body: #"{"error":"invalid_client"}"#).send(code: "some.code.value")
        }
    }

    @Test("No connection is reported as offline")
    func offline() async {
        StubURLProtocol.reset(host: host)
        let r = revoker(status: 200, body: "{}")
        StubURLProtocol.setHandler({ _ in throw URLError(.notConnectedToInternet) }, host: host)
        await #expect(throws: DomainError.authentication(.networkUnavailable)) {
            try await r.send(code: "some.code.value")
        }
    }
}
