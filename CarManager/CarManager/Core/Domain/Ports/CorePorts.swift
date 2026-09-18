import Foundation

/// Injected clock. Production code never calls Date() — this is what makes every
/// date-sensitive test deterministic.
public protocol ClockProviding: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
    var timeZone: TimeZone { get }
}

public protocol IDGenerating: Sendable {
    func newUUID() -> UUID
}

public enum AppearancePreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
}

/// User preferences — deliberately separate from application state and from domain data.
public protocol PreferencesProviding: AnyObject, Sendable {
    var unitSystem: UnitSystem { get set }
    var defaultCurrency: CurrencyCode { get set }
    var appearance: AppearancePreference { get set }
    var languageOverride: String? { get set }
    var defaultVehicleID: VehicleID? { get set }
    var notificationsEnabled: Bool { get set }
    var telemetryEnabled: Bool { get set }
    var iCloudSyncEnabled: Bool { get set }
    var onboardingCompletedVersion: Int { get set }
    var acknowledgedDisclaimerVersions: Set<Int> { get set }
}

public protocol ConnectivityProviding: Sendable {
    var isOnline: Bool { get async }
}

public enum SyncState: Sendable, Equatable {
    case unavailable(reason: String)
    case idle(lastSyncedAt: Date?)
    case syncing
    case failed(message: String, willRetry: Bool)
}

public protocol SyncStatusProviding: Sendable {
    func currentStatus() async -> SyncState
}

public protocol FileStorage: Sendable {
    func store(_ data: Data, preferredName: String, kind: FileKind) async throws -> FileRef
    func read(_ ref: FileRef) async throws -> Data
    func availability(_ ref: FileRef) async -> FileAvailability
    func delete(_ ref: FileRef) async throws
}

public enum NotificationAuthorization: Sendable, Equatable {
    case notDetermined, authorized, denied
}

/// The domain hands over plain values. Only the infrastructure adapter imports
/// UserNotifications.
public struct ScheduledNotification: Hashable, Sendable {
    public let identifier: String
    public let titleKey: String
    public let bodyKey: String
    public let arguments: [String]
    public let fireDate: Date

    public init(identifier: String, titleKey: String, bodyKey: String, arguments: [String] = [], fireDate: Date) {
        self.identifier = identifier; self.titleKey = titleKey; self.bodyKey = bodyKey
        self.arguments = arguments; self.fireDate = fireDate
    }
}

public protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func schedule(_ requests: [ScheduledNotification]) async throws
    func cancel(identifiers: [String]) async
    func cancelAll(matching prefix: String) async
}

public protocol DocumentExporting: Sendable {
    func exportPDF(vehicleID: VehicleID, period: AnalyticsPeriod) async throws -> URL
}

public protocol TelemetryProviding: Sendable {
    func track(_ event: String, parameters: [String: String])
    func recordError(_ error: Error, context: [String: String])
}

/// Read-only reference data for the brand/model pickers. Kept on device so choosing a car
/// works offline and never sends what the user is typing anywhere.
public protocol VehicleCatalogProviding: Sendable {
    func catalog() async throws -> VehicleCatalog
}
