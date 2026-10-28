import Testing
import Foundation
@testable import CarManager

@Suite("Account: sign-out and deletion")
@MainActor
struct AccountTests {
    private let clock = FixedClock()

    private func provider(_ store: InMemoryAppleIdentityStore) -> AppleAuthProvider {
        AppleAuthProvider(identityStore: store, credentialState: AlwaysAuthorizedCredentialState(), clock: clock)
    }

    @Test("Signing out keeps the name and email Apple will not send again")
    func signOutKeepsProfile() async throws {
        let store = InMemoryAppleIdentityStore()
        let auth = provider(store)
        _ = try await auth.signInWithApple(AppleIDCredential(userID: "u1", fullName: "Ivan Z", email: "ivan@example.com"))
        try await auth.signOut()
        #expect(try await auth.restoreSession() == nil)              // really signed out

        // Second sign-in: Apple sends neither name nor email.
        let profile = try await auth.signInWithApple(AppleIDCredential(userID: "u1"))
        #expect(profile.displayName == "Ivan Z")
        #expect(profile.email == "ivan@example.com")
        #expect(try await auth.restoreSession()?.email == "ivan@example.com")
    }

    @Test("The email is read from Apple's identity token when the credential has none")
    func emailFromToken() {
        func b64(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        let jwt = b64(#"{"alg":"RS256"}"#) + "." + b64(#"{"sub":"u1","email":"abc@privaterelay.appleid.com"}"#) + ".sig"
        #expect(AppleIDCredential.email(fromIdentityToken: Data(jwt.utf8)) == "abc@privaterelay.appleid.com")
        #expect(AppleIDCredential.email(fromIdentityToken: Data("garbage".utf8)) == nil)
        #expect(AppleIDCredential.email(fromIdentityToken: nil) == nil)
    }

    @Test("Settings says 'Signed in' rather than 'Not signed in' when Apple withheld the email")
    func settingsWithoutEmail() {
        let model = SettingsFormatter(locale: Locale(identifier: "en_US"), timeZone: .gmt, appVersion: "1.0").makeModel(
            authState: .authenticated(UserProfile(authProvider: .apple, createdAt: clock.now)),
            unitSystem: .metric, telemetryEnabled: false, syncState: .idle(lastSyncedAt: nil)
        )
        #expect(model.sections.flatMap(\.rows).first { $0.id == "email" }?.trailing == .value("Signed in"))
    }

    @Test("Deleting the account erases every record and the identity")
    func deleteErasesEverything() async throws {
        let store = InMemoryAppleIdentityStore()
        let auth = provider(store)
        let d = AppDependencies.testing(preferences: InMemoryPreferences(onboardingCompletedVersion: 1), clock: clock) {
            $0.auth = auth
        }
        _ = try await auth.signInWithApple(AppleIDCredential(userID: "u1", fullName: "Ivan", email: "i@x.com"))

        let car = try await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock)(
            VehicleDraft(brand: "Porsche", model: "Macan", initialOdometer: Odometer(kilometers: 30_200)), vehicleLimit: nil
        ).vehicle.id
        _ = try await AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: clock)(FuelEntryDraft(
            vehicleID: car, date: clock.now, odometer: Odometer(kilometers: 30_500), volume: Volume(liters: 50),
            totalCost: Money(90, .eur), fuelType: .diesel, isFullTank: true
        ))
        _ = try await AddExpense(expenses: d.expenses, odometer: d.odometer, clock: clock)(
            vehicleID: car, title: "Wash", category: .carWash, cost: Money(15, .eur), date: clock.now
        )
        _ = try await CreateReminder(reminders: d.reminders, notifications: d.notifications, clock: clock)(
            vehicleID: car, title: "Tyres", kind: .tireChange,
            trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(86_400 * 30))), recurrence: .none
        )
        let document = try await AddDocument(documents: d.documents, files: d.files, clock: clock)(
            vehicleID: car, name: "Licence", type: .driverLicense, fileData: Data("pdf".utf8)
        )
        try await d.conversations.create(AIConversation(vehicleID: nil, title: "Chat", createdAt: clock.now, updatedAt: clock.now))
        try await d.inbox.insert(AppNotification(kind: .reminderDue, titleKey: "x", bodyKey: "y", createdAt: clock.now))
        d.preferences.defaultVehicleID = car
        try await d.scans.insert(DashboardScan(vehicleID: nil, imageRef: FileRef(relativePath: "s.jpg"), findings: [], createdAt: clock.now))
        try await d.scans.insert(DamageAnalysis(vehicleID: car, imageRefs: [], findings: [], createdAt: clock.now))

        let app = AppModel(dependencies: d)
        await app.auth.restore()
        try await app.auth.deleteAccount(DeleteAccount(
            auth: d.auth, vehicles: d.vehicles, documents: d.documents, conversations: d.conversations,
            inbox: d.inbox, scans: d.scans, files: d.files, notifications: d.notifications, preferences: d.preferences
        ))

        #expect(try await d.vehicles.all().isEmpty)
        #expect(try await d.fuel.entries(vehicleID: car).isEmpty)
        #expect(try await d.expenses.expenses(vehicleID: car).isEmpty)
        #expect(try await d.reminders.reminders(vehicleID: nil, activeOnly: false).isEmpty)
        #expect(try await d.odometer.readings(vehicleID: car).isEmpty)
        #expect(try await d.documents.query(DocumentQuery()).isEmpty)
        await #expect(throws: (any Error).self) { _ = try await d.files.read(document.fileRef) }
        #expect(try await d.conversations.summaries(vehicleID: nil).isEmpty)
        #expect(try await d.inbox.notifications(limit: 10).isEmpty)
        #expect(d.preferences.defaultVehicleID == nil)
        #expect(try await ListScanHistory(scans: d.scans)().isEmpty)

        // The identity is gone too: the next sign-in starts a fresh account.
        #expect(try store.load() == nil)
        #expect(!app.auth.state.isAuthenticated)
    }
}

@Suite("Display name")
@MainActor
struct DisplayNameTests {
    private let clock = FixedClock()

    @Test("A sign-in without a name asks for one; the relay email is never used as a name")
    func needsName() async throws {
        let store = InMemoryAppleIdentityStore()
        let auth = AppleAuthProvider(identityStore: store, credentialState: AlwaysAuthorizedCredentialState(), clock: clock)
        let profile = try await auth.signInWithApple(AppleIDCredential(userID: "u1", email: "abc123@privaterelay.appleid.com"))
        #expect(profile.needsDisplayName)
        #expect(profile.hasPrivateRelayEmail)

        let identity = ProfileFormatter(languageName: "English").makeModel(
            authState: .authenticated(profile), entitlement: .free, isPremium: false,
            statistics: UserStatistics(vehicleCount: 0, fuelEntryCount: 0, serviceRecordCount: 0)
        ).identity
        #expect(!identity.name.contains("privaterelay") && !identity.subtitle.contains("privaterelay"))
    }

    @Test("The chosen name is saved, trimmed, survives a relaunch and is kept after sign-out")
    func saveName() async throws {
        let store = InMemoryAppleIdentityStore()
        let auth = AppleAuthProvider(identityStore: store, credentialState: AlwaysAuthorizedCredentialState(), clock: clock)
        _ = try await auth.signInWithApple(AppleIDCredential(userID: "u1"))
        let updated = try await auth.updateDisplayName("  Ivan  ")
        #expect(updated.displayName == "Ivan" && !updated.needsDisplayName)
        #expect(try await auth.restoreSession()?.displayName == "Ivan")

        try await auth.signOut()
        #expect(try await auth.signInWithApple(AppleIDCredential(userID: "u1")).displayName == "Ivan")
    }

    @Test("Blank or over-long names are refused")
    func invalidNames() async throws {
        let auth = AppleAuthProvider(identityStore: InMemoryAppleIdentityStore(), credentialState: AlwaysAuthorizedCredentialState(), clock: clock)
        _ = try await auth.signInWithApple(AppleIDCredential(userID: "u1"))
        await #expect(throws: DomainError.self) { _ = try await auth.updateDisplayName("   ") }
        await #expect(throws: DomainError.self) { _ = try await auth.updateDisplayName(String(repeating: "a", count: 41)) }
    }
}
