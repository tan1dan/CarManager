import Foundation

// MARK: - Authentication

/// Signing in exchanges the Apple credential for a profile. There is nothing to validate
/// locally: Apple has already authenticated the user.
public struct SignInWithApple: Sendable {
    let auth: any AuthProviding
    public init(auth: any AuthProviding) { self.auth = auth }

    public func callAsFunction(_ credential: AppleIDCredential) async throws -> UserProfile {
        guard !credential.userID.isEmpty else {
            throw DomainError.authentication(.invalidCredentials)
        }
        return try await auth.signInWithApple(credential)
    }
}

public struct SignOut: Sendable {
    let auth: any AuthProviding
    public init(auth: any AuthProviding) { self.auth = auth }
    public func callAsFunction() async throws { try await auth.signOut() }
}

// MARK: - Subscription

public struct LoadProducts: Sendable {
    let subscriptions: any SubscriptionProviding
    public init(subscriptions: any SubscriptionProviding) { self.subscriptions = subscriptions }
    public func callAsFunction() async throws -> [SubscriptionProduct] {
        try await subscriptions.products()
    }
}

public struct PurchasePremium: Sendable {
    let subscriptions: any SubscriptionProviding
    public init(subscriptions: any SubscriptionProviding) { self.subscriptions = subscriptions }
    /// `.pending` (Ask to Buy) is a first-class outcome, not an error.
    public func callAsFunction(_ productID: ProductID) async throws -> PurchaseOutcome {
        try await subscriptions.purchase(productID)
    }
}

public struct RestorePurchases: Sendable {
    let subscriptions: any SubscriptionProviding
    public init(subscriptions: any SubscriptionProviding) { self.subscriptions = subscriptions }
    /// `.nothingToRestore` is a NEUTRAL outcome shown as information, never an error alert.
    public func callAsFunction() async throws -> RestoreOutcome {
        try await subscriptions.restore()
    }
}

// MARK: - Notification inbox

public struct LoadNotificationInbox: Sendable {
    let inbox: any NotificationInboxRepository
    public init(inbox: any NotificationInboxRepository) { self.inbox = inbox }
    public func callAsFunction(limit: Int = 50) async throws -> [AppNotification] {
        try await inbox.notifications(limit: limit)
    }
}

public struct ClearNotifications: Sendable {
    let inbox: any NotificationInboxRepository
    public init(inbox: any NotificationInboxRepository) { self.inbox = inbox }
    public func callAsFunction() async throws { try await inbox.clearAll() }
}

public struct MarkNotificationRead: Sendable {
    let inbox: any NotificationInboxRepository
    let clock: any ClockProviding
    public init(inbox: any NotificationInboxRepository, clock: any ClockProviding) {
        self.inbox = inbox; self.clock = clock
    }
    public func callAsFunction(ids: [NotificationID]) async throws {
        try await inbox.markRead(ids: ids, at: clock.now)
    }
}

// MARK: - Export

/// Premium-gated at the call site. Renders off the main actor via the `DocumentExporting` port
/// and returns a temporary URL for the share sheet.
public struct ExportVehicleHistoryPDF: Sendable {
    let exporter: any DocumentExporting

    public init(exporter: any DocumentExporting) { self.exporter = exporter }

    public func callAsFunction(vehicleID: VehicleID, period: AnalyticsPeriod) async throws -> URL {
        try await exporter.exportPDF(vehicleID: vehicleID, period: period)
    }
}

// MARK: - User statistics

/// The counts shown on Profile. `VehicleSummary` already carries the per-vehicle totals, so
/// this needs no new repository method.
public struct UserStatistics: Equatable, Sendable {
    public let vehicleCount: Int
    public let fuelEntryCount: Int
    public let serviceRecordCount: Int

    public init(vehicleCount: Int, fuelEntryCount: Int, serviceRecordCount: Int) {
        self.vehicleCount = vehicleCount
        self.fuelEntryCount = fuelEntryCount
        self.serviceRecordCount = serviceRecordCount
    }

    public static let empty = UserStatistics(
        vehicleCount: 0, fuelEntryCount: 0, serviceRecordCount: 0
    )
}

public struct LoadUserStatistics: Sendable {
    let vehicles: any VehicleRepository

    public init(vehicles: any VehicleRepository) { self.vehicles = vehicles }

    public func callAsFunction() async throws -> UserStatistics {
        let summaries = try await vehicles.summaries()
        return UserStatistics(
            vehicleCount: summaries.count,
            fuelEntryCount: summaries.reduce(0) { $0 + $1.fuelEntryCount },
            serviceRecordCount: summaries.reduce(0) { $0 + $1.serviceRecordCount }
        )
    }
}

// MARK: - Home composite

public struct HomeDashboard: Sendable, Equatable {
    public let vehicle: Vehicle
    public let currentOdometer: Odometer?
    public let latestFuelEntry: FuelEntry?
    public let upcomingReminders: [ReminderEvaluation]
    public let expiringDocuments: [EvaluateDocumentExpiries.Item]
    public let insights: [AIInsight]
    public let unreadNotificationCount: Int
}

/// Assembles everything Home shows, concurrently. It reads only CACHED insights — Home must
/// render offline and must never trigger a network call.
public struct LoadHomeDashboard: Sendable {
    let vehicles: any VehicleRepository
    let odometer: any OdometerRepository
    let fuel: any FuelRepository
    let evaluateReminders: EvaluateReminderTriggers
    let evaluateDocuments: EvaluateDocumentExpiries
    let insights: any AIInsightRepository
    let inbox: any NotificationInboxRepository

    public init(
        vehicles: any VehicleRepository, odometer: any OdometerRepository, fuel: any FuelRepository,
        evaluateReminders: EvaluateReminderTriggers, evaluateDocuments: EvaluateDocumentExpiries,
        insights: any AIInsightRepository, inbox: any NotificationInboxRepository
    ) {
        self.vehicles = vehicles; self.odometer = odometer; self.fuel = fuel
        self.evaluateReminders = evaluateReminders; self.evaluateDocuments = evaluateDocuments
        self.insights = insights; self.inbox = inbox
    }

    public func callAsFunction(vehicleID: VehicleID) async throws -> HomeDashboard {
        guard let vehicle = try await vehicles.vehicle(id: vehicleID) else {
            throw DomainError.validation(.vehicleNotFound)
        }
        async let currentOdometer = odometer.current(vehicleID: vehicleID)
        async let latestFuel = fuel.latest(vehicleID: vehicleID)
        async let reminders = evaluateReminders(vehicleID: vehicleID)
        async let documents = evaluateDocuments(vehicleID: vehicleID)
        async let cachedInsights = insights.insights(vehicleID: vehicleID)
        async let unread = inbox.unreadCount()

        return HomeDashboard(
            vehicle: vehicle,
            currentOdometer: try await currentOdometer?.value,
            latestFuelEntry: try await latestFuel,
            upcomingReminders: try await reminders,
            expiringDocuments: try await documents,
            insights: try await cachedInsights,
            unreadNotificationCount: try await unread
        )
    }
}

/// "Delete account": erases everything the app stored for this person, then forgets the
/// Apple identity. The store mirrors to the private iCloud database, so the deletions reach
/// iCloud and the user's other devices too.
///
/// Order matters: documents first (their files are removed with them), then each vehicle with
/// its records, then everything not tied to a vehicle. The identity goes last, so a failure
/// part-way leaves the user signed in and able to try again.
public struct DeleteAccount: Sendable {
    let auth: any AuthProviding
    let vehicles: any VehicleRepository
    let documents: any DocumentRepository
    let conversations: any AIConversationRepository
    let inbox: any NotificationInboxRepository
    let scans: (any ScanRepository)?
    let files: any FileStorage
    let notifications: any NotificationScheduling
    let preferences: any PreferencesProviding

    public init(
        auth: any AuthProviding, vehicles: any VehicleRepository, documents: any DocumentRepository,
        conversations: any AIConversationRepository, inbox: any NotificationInboxRepository,
        scans: (any ScanRepository)? = nil,
        files: any FileStorage, notifications: any NotificationScheduling, preferences: any PreferencesProviding
    ) {
        self.auth = auth; self.vehicles = vehicles; self.documents = documents
        self.conversations = conversations; self.inbox = inbox; self.scans = scans; self.files = files
        self.notifications = notifications; self.preferences = preferences
    }

    public func callAsFunction() async throws {
        var orphaned: [FileRef] = []
        for document in try await documents.query(DocumentQuery()) {
            orphaned += try await documents.delete(id: document.id)
        }
        for vehicle in try await vehicles.all() {
            orphaned += try await vehicles.delete(id: vehicle.id)
        }
        for conversation in try await conversations.summaries(vehicleID: nil) {
            orphaned += try await conversations.delete(id: conversation.id)
        }
        if let scans {
            for scan in try await scans.dashboardScans(vehicleID: nil) {
                orphaned += try await scans.deleteDashboardScan(id: scan.id)
            }
            for analysis in try await scans.damageAnalyses(vehicleID: nil) {
                orphaned += try await scans.deleteDamageAnalysis(id: analysis.id)
            }
        }
        try await inbox.clearAll()
        for ref in orphaned { try? await files.delete(ref) }

        await notifications.cancelAll(matching: "")
        preferences.defaultVehicleID = nil
        preferences.acknowledgedDisclaimerVersions = []

        try await auth.deleteAccount()
    }
}
