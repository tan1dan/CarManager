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
    /// Records live in SwiftData, mirrored to the user's private CloudKit database. The
    /// remaining stubs are the external services (StoreKit, AI, Vision), each behind a
    /// protocol, so replacing them stays a change to this factory only.
    @MainActor
    static func live(
        preferences: any PreferencesProviding = UserPreferencesStore(),
        clock: any ClockProviding = SystemClock()
    ) -> AppDependencies {
        let (container, mode) = PersistenceContainer.make()
        if case .localOnly(let reason) = mode {
            print("⚠️ iCloud mirroring is off, data stays on this device. Reason: \(reason)")
        }
        let store = PersistenceActor(modelContainer: container)
        // Receipt scans are NOT persisted: one lives only until the user confirms or discards
        // it, and nothing extracted may be written without that confirmation. Dashboard scans
        // and damage analyses are history, and are kept.
        let scratch = InMemoryStore()
        // Photos and documents go to iCloud with the records; older ones are copied up once.
        let files = SyncedFileStorage(store: store, clock: clock)
        Task.detached(priority: .utility) { await files.uploadLocalOnlyFiles() }
        let vehicles = SwiftDataVehicleRepository(store: store)
        let odometer = SwiftDataOdometerRepository(store: store)
        return AppDependencies(
            vehicles: vehicles,
            odometer: odometer,
            fuel: SwiftDataFuelRepository(store: store),
            services: SwiftDataServiceRepository(store: store),
            expenses: SwiftDataExpenseRepository(store: store),
            reminders: SwiftDataReminderRepository(store: store),
            documents: SwiftDataDocumentRepository(store: store),
            conversations: SwiftDataAIConversationRepository(store: store),
            insights: SwiftDataAIInsightRepository(store: store),
            inbox: SwiftDataNotificationInboxRepository(store: store),
            scans: SwiftDataScanRepository(store: store, receipts: InMemoryScanRepository(store: scratch)),
            auth: makeAuthProvider(clock: clock),
            subscriptions: makeSubscriptions(clock: clock),
            ai: makeAIProvider(),
            vision: HybridVisionAnalysisProvider(
                vehicles: vehicles, odometer: odometer,
                remote: AIServiceConfiguration.fromBundle().map { CarVisionService(configuration: $0) },
                receipts: AIServiceConfiguration.fromBundle().map { CarReceiptService(configuration: $0) },
                clock: clock
            ),
            textRecognizer: VisionTextRecognizer(),
            imagePreprocessor: JPEGImagePreprocessor(),
            files: files,
            notifications: UNNotificationScheduler(),
            exporter: StubDocumentExporter(),
            preferences: preferences,
            syncStatus: CloudKitSyncStatusProvider(mode: mode),
            connectivity: AlwaysOnlineConnectivity(),
            // Always on: there is no opt-out switch any more. ConsoleTelemetry only logs locally;
            // a real analytics backend must be declared in the App Store privacy labels.
            telemetry: ConsoleTelemetry(isEnabled: true),
            clock: clock,
            ids: UUIDGenerator(),
            vehicleCatalog: BundledVehicleCatalog()
        )
    }

    /// Fully in-memory, with a mutation closure so a single dependency can be swapped:
    /// `.testing { $0.clock = FixedClock(now: …) }`
    ///
    /// Uses the hand-written in-memory repositories rather than SwiftData: they are faster
    /// and dependency-free. `persistence()` below is what exercises the real store.
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
            auth: AppleAuthProvider(
                identityStore: InMemoryAppleIdentityStore(),
                credentialState: AlwaysAuthorizedCredentialState(),
                clock: clock
            ),
            subscriptions: {
                #if DEBUG
                PreviewSubscriptionProvider(clock: clock)
                #else
                StoreKitSubscriptionProvider(clock: clock)
                #endif
            }(),
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

extension AppDependencies {
    /// The `car-assistant` Edge Function when Info.plist names it; otherwise a provider that
    /// reports "not configured". Never the mock: a release build must not invent answers.
    static func makeAIProvider() -> any AIProvider {
        guard let configuration = AIServiceConfiguration.fromBundle() else { return UnconfiguredAIProvider() }
        return SupabaseAIProvider(service: AIChatService(configuration: configuration))
    }

    /// StoreKit is still a stub. `-debugPremium` (DEBUG only) starts as a subscriber so the
    /// Premium screens can be checked without going through the paywall each launch.
    static func makeSubscriptions(clock: any ClockProviding) -> any SubscriptionProviding {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-debugPremium") {
            return PreviewSubscriptionProvider(entitlement: Entitlement(
                tier: .premium, source: .direct, expiresAt: clock.now.addingTimeInterval(86_400 * 30),
                willAutoRenew: true, lastVerifiedAt: clock.now
            ), clock: clock)
        }
        // App Store Connect's US prices without StoreKit, for paywall screenshots.
        if arguments.contains("-debugPaywallPrices") {
            return PreviewSubscriptionProvider(clock: clock)
        }
        #endif
        return StoreKitSubscriptionProvider(clock: clock)
    }

    /// Identity is Sign in with Apple plus the Keychain — no service to configure.
    @MainActor
    static func makeAuthProvider(clock: any ClockProviding) -> any AuthProviding {
        #if DEBUG
        // Simulator and UI-test runs cannot sign in to an Apple ID, so a DEBUG build started
        // with `-debugSignedIn` gets a fixed test identity. Compiled out of Release: there is
        // no way into a shipped build without a real Apple account.
        if ProcessInfo.processInfo.arguments.contains("-debugSignedIn") {
            return AppleAuthProvider(
                // `-debugNoName` behaves like "Hide My Email": no name, a relay address.
                identityStore: InMemoryAppleIdentityStore(
                    ProcessInfo.processInfo.arguments.contains("-debugNoName")
                    ? StoredAppleIdentity(userID: "debug.user", email: "x7k2p9q4@privaterelay.appleid.com", firstSignedInAt: clock.now)
                    : StoredAppleIdentity(userID: "debug.user", displayName: "Alex Lindström",
                                          email: "alex@example.com", firstSignedInAt: clock.now)
                ),
                credentialState: AlwaysAuthorizedCredentialState(),
                clock: clock
            )
        }
        #endif
        return AppleAuthProvider(
            identityStore: KeychainAppleIdentityStore(),
            credentialState: SystemAppleCredentialState(),
            revoker: AIServiceConfiguration.fromBundle().map { AppleAuthorizationRevoker(configuration: $0) },
            clock: clock
        )
    }

    /// The real SwiftData stack on an in-memory store — same code paths as production,
    /// nothing written to disk, nothing mirrored to CloudKit.
    static func persistence(
        preferences: any PreferencesProviding = InMemoryPreferences(),
        clock: any ClockProviding = SystemClock()
    ) -> AppDependencies {
        let (container, _) = PersistenceContainer.make(inMemory: true)
        let store = PersistenceActor(modelContainer: container)
        var dependencies = AppDependencies.testing(preferences: preferences, clock: clock)
        dependencies.vehicles = SwiftDataVehicleRepository(store: store)
        dependencies.odometer = SwiftDataOdometerRepository(store: store)
        dependencies.fuel = SwiftDataFuelRepository(store: store)
        dependencies.services = SwiftDataServiceRepository(store: store)
        dependencies.expenses = SwiftDataExpenseRepository(store: store)
        dependencies.reminders = SwiftDataReminderRepository(store: store)
        dependencies.documents = SwiftDataDocumentRepository(store: store)
        dependencies.conversations = SwiftDataAIConversationRepository(store: store)
        dependencies.insights = SwiftDataAIInsightRepository(store: store)
        dependencies.inbox = SwiftDataNotificationInboxRepository(store: store)
        return dependencies
    }
}
