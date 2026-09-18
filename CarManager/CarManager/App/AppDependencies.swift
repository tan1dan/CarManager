import Foundation

/// The container. Composed ONCE, in `CarManagerApp.init()`. There are no singletons and no
/// `.shared` anywhere: a missing dependency is a compile error, not a runtime crash.
public struct AppDependencies: Sendable {
    // Repositories
    public var vehicles: any VehicleRepository
    public var odometer: any OdometerRepository
    public var fuel: any FuelRepository
    public var services: any ServiceRepository
    public var expenses: any ExpenseRepository
    public var reminders: any ReminderRepository
    public var documents: any DocumentRepository
    public var conversations: any AIConversationRepository
    public var insights: any AIInsightRepository
    public var inbox: any NotificationInboxRepository
    public var scans: any ScanRepository

    // Ports
    public var auth: any AuthProviding
    public var subscriptions: any SubscriptionProviding
    public var ai: any AIProvider
    public var vision: any VisionAnalysisProvider
    public var textRecognizer: any TextRecognizing
    public var imagePreprocessor: any ImagePreprocessing
    public var files: any FileStorage
    public var notifications: any NotificationScheduling
    public var exporter: any DocumentExporting
    public var preferences: any PreferencesProviding
    public var syncStatus: any SyncStatusProviding
    public var connectivity: any ConnectivityProviding
    public var telemetry: any TelemetryProviding
    public var clock: any ClockProviding
    public var ids: any IDGenerating
    public var vehicleCatalog: any VehicleCatalogProviding

    public init(
        vehicles: any VehicleRepository, odometer: any OdometerRepository,
        fuel: any FuelRepository, services: any ServiceRepository,
        expenses: any ExpenseRepository, reminders: any ReminderRepository,
        documents: any DocumentRepository, conversations: any AIConversationRepository,
        insights: any AIInsightRepository, inbox: any NotificationInboxRepository,
        scans: any ScanRepository, auth: any AuthProviding,
        subscriptions: any SubscriptionProviding, ai: any AIProvider,
        vision: any VisionAnalysisProvider, textRecognizer: any TextRecognizing,
        imagePreprocessor: any ImagePreprocessing, files: any FileStorage,
        notifications: any NotificationScheduling, exporter: any DocumentExporting,
        preferences: any PreferencesProviding, syncStatus: any SyncStatusProviding,
        connectivity: any ConnectivityProviding, telemetry: any TelemetryProviding,
        clock: any ClockProviding, ids: any IDGenerating,
        vehicleCatalog: any VehicleCatalogProviding
    ) {
        self.vehicles = vehicles; self.odometer = odometer; self.fuel = fuel
        self.services = services; self.expenses = expenses; self.reminders = reminders
        self.documents = documents; self.conversations = conversations
        self.insights = insights; self.inbox = inbox; self.scans = scans
        self.auth = auth; self.subscriptions = subscriptions; self.ai = ai
        self.vision = vision; self.textRecognizer = textRecognizer
        self.imagePreprocessor = imagePreprocessor; self.files = files
        self.notifications = notifications; self.exporter = exporter
        self.preferences = preferences; self.syncStatus = syncStatus
        self.connectivity = connectivity; self.telemetry = telemetry
        self.clock = clock; self.ids = ids
        self.vehicleCatalog = vehicleCatalog
    }
}

public extension AppDependencies {
    /// PLACEHOLDER WIRING: repositories are in-memory and the external providers are stubs.
    /// Because everything sits behind a protocol, replacing them with SwiftData + CloudKit,
    /// StoreKit 2 and the backend AI proxy is a change to this factory only.
    static func live(
        preferences: any PreferencesProviding = UserPreferencesStore(),
        clock: any ClockProviding = SystemClock()
    ) -> AppDependencies {
        let store = InMemoryStore()
        return AppDependencies(
            vehicles: InMemoryVehicleRepository(store: store),
            odometer: InMemoryOdometerRepository(store: store),
            fuel: InMemoryFuelRepository(store: store),
            services: InMemoryServiceRepository(store: store),
            expenses: InMemoryExpenseRepository(store: store),
            reminders: InMemoryReminderRepository(store: store),
            documents: InMemoryDocumentRepository(store: store),
            conversations: InMemoryAIConversationRepository(store: store),
            insights: InMemoryAIInsightRepository(store: store),
            inbox: InMemoryNotificationInboxRepository(store: store),
            scans: InMemoryScanRepository(store: store),
            auth: StubAuthProvider(clock: clock),
            subscriptions: StubSubscriptionProvider(clock: clock),
            ai: MockAIProvider(),
            vision: StubVisionAnalysisProvider(),
            textRecognizer: StubTextRecognizer(),
            imagePreprocessor: StubImagePreprocessor(),
            files: DiskFileStorage(),
            notifications: UNNotificationScheduler(),
            exporter: StubDocumentExporter(),
            preferences: preferences,
            syncStatus: StubSyncStatusProvider(),
            connectivity: AlwaysOnlineConnectivity(),
            telemetry: ConsoleTelemetry(isEnabled: preferences.telemetryEnabled),
            clock: clock,
            ids: UUIDGenerator(),
            vehicleCatalog: BundledVehicleCatalog()
        )
    }

    /// Fully in-memory, with a mutation closure so a single dependency can be swapped:
    /// `.testing { $0.clock = FixedClock(now: …) }`
    static func testing(
        preferences: any PreferencesProviding = InMemoryPreferences(),
        clock: any ClockProviding = SystemClock(),
        _ overrides: (inout AppDependencies) -> Void = { _ in }
    ) -> AppDependencies {
        let store = InMemoryStore()
        var dependencies = AppDependencies(
            vehicles: InMemoryVehicleRepository(store: store),
            odometer: InMemoryOdometerRepository(store: store),
            fuel: InMemoryFuelRepository(store: store),
            services: InMemoryServiceRepository(store: store),
            expenses: InMemoryExpenseRepository(store: store),
            reminders: InMemoryReminderRepository(store: store),
            documents: InMemoryDocumentRepository(store: store),
            conversations: InMemoryAIConversationRepository(store: store),
            insights: InMemoryAIInsightRepository(store: store),
            inbox: InMemoryNotificationInboxRepository(store: store),
            scans: InMemoryScanRepository(store: store),
            auth: StubAuthProvider(clock: clock),
            subscriptions: StubSubscriptionProvider(clock: clock),
            ai: MockAIProvider(chunkDelay: .zero),
            vision: StubVisionAnalysisProvider(),
            textRecognizer: StubTextRecognizer(),
            imagePreprocessor: StubImagePreprocessor(),
            files: InMemoryFileStorage(),
            notifications: SpyNotificationScheduler(),
            exporter: StubDocumentExporter(),
            preferences: preferences,
            syncStatus: StubSyncStatusProvider(),
            connectivity: AlwaysOnlineConnectivity(),
            telemetry: ConsoleTelemetry(),
            clock: clock,
            ids: UUIDGenerator(),
            vehicleCatalog: BundledVehicleCatalog()
        )
        overrides(&dependencies)
        return dependencies
    }

    static func preview() -> AppDependencies {
        testing(preferences: InMemoryPreferences(onboardingCompletedVersion: 1))
    }
}
