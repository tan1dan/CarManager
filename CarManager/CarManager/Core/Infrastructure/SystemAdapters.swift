import Foundation

/// The production clock. No other production type calls Date() — that is what makes every
/// date-sensitive test deterministic.
public struct SystemClock: ClockProviding {
    public init() {}
    public var now: Date { Date() }
    public var calendar: Calendar { Calendar.current }
    public var timeZone: TimeZone { TimeZone.current }
}

public struct UUIDGenerator: IDGenerating {
    public init() {}
    public func newUUID() -> UUID { UUID() }
}

/// Non-sensitive preferences only. Tokens live in the Keychain; domain data lives in the store.
public final class UserPreferencesStore: PreferencesProviding, @unchecked Sendable {
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func value<T>(_ key: String, default fallback: T) -> T {
        lock.lock(); defer { lock.unlock() }
        return defaults.object(forKey: key) as? T ?? fallback
    }
    private func set(_ key: String, _ newValue: Any?) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(newValue, forKey: key)
    }

    public var unitSystem: UnitSystem {
        get { UnitSystem(rawValue: value("pref.unitSystem", default: "")) ?? .metric }
        set { set("pref.unitSystem", newValue.rawValue) }
    }
    public var defaultCurrency: CurrencyCode {
        get { CurrencyCode(value("pref.currency", default: "EUR")) }
        set { set("pref.currency", newValue.iso4217) }
    }
    public var appearance: AppearancePreference {
        get { AppearancePreference(rawValue: value("pref.appearance", default: "")) ?? .system }
        set { set("pref.appearance", newValue.rawValue) }
    }
    public var languageOverride: String? {
        get { value("pref.language", default: nil as String?) }
        set { set("pref.language", newValue) }
    }
    public var defaultVehicleID: VehicleID? {
        get { value("pref.defaultVehicle", default: nil as String?).flatMap { VehicleID(uuidString: $0) } }
        set { set("pref.defaultVehicle", newValue?.raw.uuidString) }
    }
    public var notificationsEnabled: Bool {
        get { value("pref.notifications", default: true) }
        set { set("pref.notifications", newValue) }
    }
    public var telemetryEnabled: Bool {
        get { value("pref.telemetry", default: false) }
        set { set("pref.telemetry", newValue) }
    }
    public var iCloudSyncEnabled: Bool {
        get { value("pref.icloud", default: true) }
        set { set("pref.icloud", newValue) }
    }
    public var onboardingCompletedVersion: Int {
        get { value("pref.onboardingVersion", default: 0) }
        set { set("pref.onboardingVersion", newValue) }
    }
    public var acknowledgedDisclaimerVersions: Set<Int> {
        get { Set(value("pref.disclaimers", default: [Int]())) }
        set { set("pref.disclaimers", Array(newValue)) }
    }
}

/// In-memory preferences for tests and previews.
public final class InMemoryPreferences: PreferencesProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _unitSystem: UnitSystem = .metric
    private var _currency: CurrencyCode = .eur
    private var _appearance: AppearancePreference = .system
    private var _language: String?
    private var _defaultVehicleID: VehicleID?
    private var _notifications = true
    private var _telemetry = false
    private var _icloud = true
    private var _onboardingVersion = 0
    private var _disclaimers: Set<Int> = []

    public init(onboardingCompletedVersion: Int = 0) {
        _onboardingVersion = onboardingCompletedVersion
    }

    private func read<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    private func write(_ body: () -> Void) { lock.lock(); defer { lock.unlock() }; body() }

    public var unitSystem: UnitSystem {
        get { read { _unitSystem } } set { write { _unitSystem = newValue } }
    }
    public var defaultCurrency: CurrencyCode {
        get { read { _currency } } set { write { _currency = newValue } }
    }
    public var appearance: AppearancePreference {
        get { read { _appearance } } set { write { _appearance = newValue } }
    }
    public var languageOverride: String? {
        get { read { _language } } set { write { _language = newValue } }
    }
    public var defaultVehicleID: VehicleID? {
        get { read { _defaultVehicleID } } set { write { _defaultVehicleID = newValue } }
    }
    public var notificationsEnabled: Bool {
        get { read { _notifications } } set { write { _notifications = newValue } }
    }
    public var telemetryEnabled: Bool {
        get { read { _telemetry } } set { write { _telemetry = newValue } }
    }
    public var iCloudSyncEnabled: Bool {
        get { read { _icloud } } set { write { _icloud = newValue } }
    }
    public var onboardingCompletedVersion: Int {
        get { read { _onboardingVersion } } set { write { _onboardingVersion = newValue } }
    }
    public var acknowledgedDisclaimerVersions: Set<Int> {
        get { read { _disclaimers } } set { write { _disclaimers = newValue } }
    }
}

public struct AlwaysOnlineConnectivity: ConnectivityProviding {
    public init() {}
    public var isOnline: Bool { get async { true } }
}

public struct StubSyncStatusProvider: SyncStatusProviding {
    public init() {}
    public func currentStatus() async -> SyncState { .idle(lastSyncedAt: nil) }
}

public struct ConsoleTelemetry: TelemetryProviding {
    private let isEnabled: Bool
    public init(isEnabled: Bool = false) { self.isEnabled = isEnabled }
    public func track(_ event: String, parameters: [String: String]) {
        guard isEnabled else { return }
        print("[telemetry] \(event) \(parameters)")
    }
    public func recordError(_ error: Error, context: [String: String]) {
        guard isEnabled else { return }
        print("[telemetry:error] \(error) \(context)")
    }
}

/// Files are written to Application Support behind an actor. Domain models hold a FileRef
/// with a RELATIVE path — absolute container URLs change between launches and installs.
public actor DiskFileStorage: FileStorage {
    private let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Files", isDirectory: true)
    }

    public func store(_ data: Data, preferredName: String, kind: FileKind) async throws -> FileRef {
        let directory = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let relativePath = "\(kind.rawValue)/\(id.uuidString)"
        do {
            try data.write(to: root.appendingPathComponent(relativePath))
        } catch {
            throw DomainError.document(.fileWriteFailed)
        }
        return FileRef(id: id, relativePath: relativePath, checksum: "\(data.count)")
    }

    public func read(_ ref: FileRef) async throws -> Data {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(ref.relativePath)) else {
            throw DomainError.document(.fileNotFound)
        }
        return data
    }

    public func availability(_ ref: FileRef) async -> FileAvailability {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(ref.relativePath).path)
            ? .local : .remote
    }

    public func delete(_ ref: FileRef) async throws {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(ref.relativePath))
    }
}

public actor InMemoryFileStorage: FileStorage {
    private var files: [UUID: Data] = [:]
    public init() {}

    public func store(_ data: Data, preferredName: String, kind: FileKind) async throws -> FileRef {
        let id = UUID()
        files[id] = data
        return FileRef(id: id, relativePath: "\(kind.rawValue)/\(id.uuidString)", checksum: "\(data.count)")
    }
    public func read(_ ref: FileRef) async throws -> Data {
        guard let data = files[ref.id] else { throw DomainError.document(.fileNotFound) }
        return data
    }
    public func availability(_ ref: FileRef) async -> FileAvailability {
        files[ref.id] != nil ? .local : .remote
    }
    public func delete(_ ref: FileRef) async throws { files.removeValue(forKey: ref.id) }
}
