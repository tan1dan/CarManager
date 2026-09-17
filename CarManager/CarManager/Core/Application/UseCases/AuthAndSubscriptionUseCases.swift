import Foundation

// MARK: - Authentication

public struct SignIn: Sendable {
    let auth: any AuthProviding
    public init(auth: any AuthProviding) { self.auth = auth }

    public func callAsFunction(email: String, password: String) async throws -> AuthSession {
        try AuthValidator.validateSignIn(email: email, password: password)
        return try await auth.signIn(.email(email, password: password))
    }

    public func withApple(identityToken: String) async throws -> AuthSession {
        try await auth.signIn(.apple(identityToken: identityToken))
    }

    public func withGoogle(idToken: String) async throws -> AuthSession {
        try await auth.signIn(.google(idToken: idToken))
    }
}

public struct SignUp: Sendable {
    let auth: any AuthProviding
    public init(auth: any AuthProviding) { self.auth = auth }

    public func callAsFunction(_ registration: AuthRegistration) async throws -> AuthSession {
        try AuthValidator.validateSignUp(registration)
        return try await auth.signUp(registration)
    }
}

public struct RequestPasswordReset: Sendable {
    let auth: any AuthProviding
    public init(auth: any AuthProviding) { self.auth = auth }
    public func callAsFunction(email: String) async throws {
        guard email.contains("@") else { throw DomainError.validation(.invalidEmail) }
        try await auth.requestPasswordReset(email: email)
    }
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
