# 05 · Repository Interfaces & Service Interfaces

---

## 1. Repository design rules

1. Repositories return **domain value types**. `@Model` classes never cross the boundary.
2. Repositories are **`Sendable`**, implemented as thin façades over the single `PersistenceActor`.
3. Repositories contain **no business logic** — no validation, no derivation, no cross-entity rules.
   They translate a typed query into a `FetchDescriptor` and map results.
4. Every repository exposes a **`changes` stream** so ViewModels can re-fetch without `@Query` and
   without `NotificationCenter` (`01 §2.2`).
5. Queries are **typed query objects**, not `NSPredicate` strings or closures, so they are testable
   and cannot leak SwiftData semantics upward.
6. Paging is explicit (`Page<T>`) on every unbounded list. A garage of 10 vehicles × 8 years of fuel
   is ~4,000 rows; loading them all to compute a header is a real performance bug.

```swift
protocol Repository: Sendable {
    associatedtype Change: Sendable
    var changes: AsyncStream<Change> { get }
}

struct Page<T: Sendable>: Sendable { let items: [T]; let cursor: PageCursor?; let totalCount: Int }
```

### The final repository set — and what was rejected

| Repository | Verdict |
|---|---|
| `VehicleRepository` | ✅ |
| `OdometerRepository` | ✅ **added** (not in the spec) — required by `03 §2.2` |
| `FuelRepository` | ✅ |
| `ServiceRepository` | ✅ |
| `ExpenseRepository` | ✅ |
| `ReminderRepository` | ✅ |
| `DocumentRepository` | ✅ |
| `AIConversationRepository` | ✅ |
| `AIInsightRepository` | ✅ |
| `NotificationInboxRepository` | ✅ **added** — the persisted in-app Alerts feed (A-25) |
| `ScanRepository` | ✅ **added** — `ReceiptScan`/`DashboardScan`/`DamageAnalysis` audit records |
| `PaymentMethodTagRepository` | ❌ **rejected** — 1 tiny user-level table, folded into `PreferencesProviding` |
| `UserRepository` | ❌ **rejected** — `UserProfile` is a single backend-owned record. It lives in `AuthSessionStore` + Keychain, not in SwiftData. A "repository" over one optional value is ceremony. |
| `SubscriptionRepository` | ❌ **rejected** — StoreKit *is* the store of record for transactions; `EntitlementStore` caches the derived entitlement in preferences. Persisting transactions ourselves invites drift. |

---

## 2. Repository interfaces

```swift
// ─────────────────────────────────────────────────────────── Vehicle
protocol VehicleRepository: Repository where Change == VehicleChange {
    func all() async throws(PersistenceError) -> [Vehicle]
    func summaries() async throws(PersistenceError) -> [VehicleSummary]   // counts + current odo
    func vehicle(id: VehicleID) async throws(PersistenceError) -> Vehicle?
    func defaultVehicle() async throws(PersistenceError) -> Vehicle?
    func count() async throws(PersistenceError) -> Int                     // free-tier gate
    func insert(_ vehicle: Vehicle) async throws(PersistenceError)
    func update(_ vehicle: Vehicle) async throws(PersistenceError)
    func delete(id: VehicleID) async throws(PersistenceError) -> [FileRef] // refs to GC
    /// Transactional: clears isDefault on all others. The exactly-one invariant lives here
    /// because it requires a single write transaction; the RULE lives in SetDefaultVehicle.
    func setDefault(id: VehicleID) async throws(PersistenceError)
}

// ─────────────────────────────────────────────────────────── Odometer
protocol OdometerRepository: Repository where Change == VehicleID {
    func current(vehicleID: VehicleID) async throws(PersistenceError) -> OdometerReading?
    func readings(vehicleID: VehicleID, in: DateRange?) async throws(PersistenceError) -> [OdometerReading]
    func append(_ reading: OdometerReading) async throws(PersistenceError)
    func updateLinked(source: OdometerSource, to value: Odometer, at date: Date) async throws(PersistenceError)
    func deleteLinked(source: OdometerSource) async throws(PersistenceError)
    /// For MileageProjector: distance/day over a trailing window.
    func averageDailyDistance(vehicleID: VehicleID, window: DateRange) async throws(PersistenceError) -> Distance?
}

// ─────────────────────────────────────────────────────────── Fuel
struct FuelQuery: Hashable, Sendable {
    var vehicleID: VehicleID
    var dateRange: DateRange?
    var fullTankOnly: Bool = false
    var sort: SortOrder = .dateDescending
    var limit: Int?
    var cursor: PageCursor?
}

protocol FuelRepository: Repository where Change == VehicleID {
    func query(_ q: FuelQuery) async throws(PersistenceError) -> Page<FuelEntry>
    /// Ascending by odometer then date — the exact ordering the segmentation algorithm needs.
    func entriesForConsumption(vehicleID: VehicleID, in: DateRange?) async throws(PersistenceError) -> [FuelEntry]
    func latest(vehicleID: VehicleID) async throws(PersistenceError) -> FuelEntry?
    func entry(id: FuelEntryID) async throws(PersistenceError) -> FuelEntry?
    func count(vehicleID: VehicleID) async throws(PersistenceError) -> Int
    func insert(_ e: FuelEntry) async throws(PersistenceError)
    func update(_ e: FuelEntry) async throws(PersistenceError)
    func delete(id: FuelEntryID) async throws(PersistenceError) -> [FileRef]
}

// ─────────────────────────────────────────────────────────── Service
struct ServiceQuery: Hashable, Sendable {
    var vehicleID: VehicleID
    var dateRange: DateRange?
    var odometerRange: ClosedRange<Double>?
    var types: Set<ServiceType>?
    var nature: ServiceNature?
    var searchText: String?
    var sort: SortOrder = .dateDescending
    var cursor: PageCursor?
}

protocol ServiceRepository: Repository where Change == VehicleID {
    func query(_ q: ServiceQuery) async throws(PersistenceError) -> Page<ServiceRecord>
    func record(id: ServiceRecordID) async throws(PersistenceError) -> ServiceRecord?
    func lastRecord(vehicleID: VehicleID, ofTypes: Set<ServiceType>) async throws(PersistenceError) -> ServiceRecord?
    func count(vehicleID: VehicleID) async throws(PersistenceError) -> Int
    func insert(_ r: ServiceRecord) async throws(PersistenceError)
    func update(_ r: ServiceRecord) async throws(PersistenceError)
    func delete(id: ServiceRecordID) async throws(PersistenceError) -> [FileRef]
}

// ─────────────────────────────────────────────────────────── Expense
protocol ExpenseRepository: Repository where Change == VehicleID {
    func query(_ q: ExpenseQuery) async throws(PersistenceError) -> Page<Expense>
    func expense(id: ExpenseID) async throws(PersistenceError) -> Expense?
    func insert(_ e: Expense) async throws(PersistenceError)
    func update(_ e: Expense) async throws(PersistenceError)
    func delete(id: ExpenseID) async throws(PersistenceError) -> [FileRef]
}

// ─────────────────────────────────────────────────────────── Reminder
protocol ReminderRepository: Repository where Change == VehicleID {
    func reminders(vehicleID: VehicleID?, activeOnly: Bool) async throws(PersistenceError) -> [Reminder]
    func reminder(id: ReminderID) async throws(PersistenceError) -> Reminder?
    func insert(_ r: Reminder) async throws(PersistenceError)
    func update(_ r: Reminder) async throws(PersistenceError)
    func delete(id: ReminderID) async throws(PersistenceError)
}

// ─────────────────────────────────────────────────────────── Document
protocol DocumentRepository: Repository where Change == VehicleID {
    func query(_ q: DocumentQuery) async throws(PersistenceError) -> Page<DocumentMetadata>
    func document(id: DocumentID) async throws(PersistenceError) -> DocumentMetadata?
    func expiring(before: Date) async throws(PersistenceError) -> [DocumentMetadata]
    func insert(_ d: DocumentMetadata) async throws(PersistenceError)
    func update(_ d: DocumentMetadata) async throws(PersistenceError)
    func delete(id: DocumentID) async throws(PersistenceError) -> [FileRef]
}

// ─────────────────────────────────────────────────────────── AI
protocol AIConversationRepository: Repository where Change == ConversationID {
    func conversations(vehicleID: VehicleID?) async throws(PersistenceError) -> [ConversationSummary]
    func conversation(id: ConversationID) async throws(PersistenceError) -> AIConversation?
    func createConversation(_ c: AIConversation) async throws(PersistenceError)
    func appendMessage(_ m: AIMessage, to: ConversationID) async throws(PersistenceError)
    /// Used by the streaming path to flush the assembled assistant turn ONCE, at completion —
    /// never per token. Per-token writes would produce thousands of CloudKit records.
    func replaceMessage(_ m: AIMessage, in: ConversationID) async throws(PersistenceError)
    func deleteConversation(id: ConversationID) async throws(PersistenceError) -> [FileRef]
}

protocol AIInsightRepository: Repository where Change == VehicleID {
    func insights(vehicleID: VehicleID, includeDismissed: Bool) async throws(PersistenceError) -> [AIInsight]
    func replaceAll(_ insights: [AIInsight], vehicleID: VehicleID) async throws(PersistenceError)
    func dismiss(id: InsightID, at: Date) async throws(PersistenceError)
    func purgeExpired(now: Date) async throws(PersistenceError)
}

// ─────────────────────────────────────────────────────────── Inbox & scans
protocol NotificationInboxRepository: Repository where Change == Void {
    func notifications(limit: Int) async throws(PersistenceError) -> [AppNotification]
    func unreadCount() async throws(PersistenceError) -> Int
    func insert(_ n: AppNotification) async throws(PersistenceError)
    func markRead(ids: [NotificationID], at: Date) async throws(PersistenceError)
    func clearAll() async throws(PersistenceError)          // screenshot 05 "Clear"
}

protocol ScanRepository: Repository where Change == Void {
    func receiptScan(id: ReceiptScanID) async throws(PersistenceError) -> ReceiptScan?
    func upsert(_ scan: ReceiptScan) async throws(PersistenceError)
    func recentDashboardScans(vehicleID: VehicleID?, limit: Int) async throws(PersistenceError) -> [DashboardScan]
    func insert(_ scan: DashboardScan) async throws(PersistenceError)
    func insert(_ analysis: DamageAnalysis) async throws(PersistenceError)
    func purge(olderThan: Date) async throws(PersistenceError) -> [FileRef]   // scans are ephemeral
}
```

---

## 3. Service (Port) interfaces

**Design rule applied:** the spec lists 13 candidate service protocols. Three of them
(*Receipt Recognition*, *Dashboard Analysis*, *Damage Analysis*) are **one provider with three
request types**, not three protocols — they share transport, auth, quota, retry and error handling,
and splitting them would triple the mock surface for zero benefit. Two of them (*Analytics*,
*Cloud Sync*) are **not services at all**: analytics is a pure domain calculator, and cloud sync is a
platform behaviour we only *observe*.

| Spec candidate | Decision |
|---|---|
| Authentication | ✅ `AuthProviding` (+ 3 strategy impls) |
| AI | ✅ `AIProvider` |
| OCR | ✅ `TextRecognizer` — separate, because it is on-device and works offline |
| Image Analysis / Receipt / Dashboard / Damage | ✅ **merged** into `VisionAnalysisProvider` |
| Subscriptions | ✅ `SubscriptionProviding` |
| Notifications | ✅ `NotificationScheduling` |
| File Storage | ✅ `FileStorage` |
| PDF Export | ✅ `DocumentExporting` |
| Analytics (statistics) | ❌ **not a protocol** — `StatisticsEngine` is a pure enum of static funcs |
| Analytics (telemetry) | ✅ `TelemetryProviding` (A-09) |
| Cloud Sync | ⚠️ **read-only** `SyncStatusProviding`. There is no `SyncService` to write. → ADR-003 |
| *(added)* Clock | ✅ `ClockProviding` — the highest-value test seam in the whole app |
| *(added)* Preferences | ✅ `PreferencesProviding` |
| *(added)* Connectivity | ✅ `ConnectivityProviding` (A-24) |
| *(added)* Image preprocessing | ✅ `ImagePreprocessing` — privacy-critical (EXIF stripping) |

```swift
// ─────────────────────────────────────────────────────────── AI
protocol AIProvider: Sendable {
    func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func complete<T: AIStructuredResult>(_ request: AIStructuredRequest<T>) async throws(AIError) -> T
}

struct AIChatRequest: Sendable {
    let messages: [AIMessage]
    let context: AIVehicleContext?        // built, bounded, deterministic. never raw rows.
    let locale: Locale
    let purpose: AIPurpose                // .chat | .insights — drives system prompt + quota bucket
}

enum AIStreamEvent: Sendable {
    case delta(String)
    case completed(text: String, usage: AIUsage)
}

/// One provider, three request types. Receipt / Dashboard / Damage.
protocol VisionAnalysisProvider: Sendable {
    func analyze(_ request: VisionAnalysisRequest) async throws(AIError) -> VisionAnalysisResult
}

enum VisionAnalysisRequest: Sendable {
    case receipt(image: Data, ocrText: String?, vehicle: AIVehicleContext.VehicleFacts, locale: Locale)
    case dashboard(image: Data, vehicle: AIVehicleContext.VehicleFacts?, locale: Locale)
    case damage(images: [Data], vehicle: AIVehicleContext.VehicleFacts, locale: Locale)
}

enum VisionAnalysisResult: Sendable {
    case receipt(ReceiptDraft)
    case dashboard([DashboardFinding])
    case damage([DamageFinding])
}

// ─────────────────────────────────────────────────────────── On-device vision
protocol TextRecognizer: Sendable {
    func recognizeText(in image: Data, languages: [Locale.Language]) async throws -> RecognizedText
}

protocol ImagePreprocessing: Sendable {
    /// Downscale to the provider's max edge, normalise orientation, STRIP EXIF/GPS, JPEG-encode.
    func prepareForUpload(_ image: Data, maxEdge: Int, quality: Double) async throws -> Data
}

// ─────────────────────────────────────────────────────────── Notifications
protocol NotificationScheduling: Sendable {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async throws(PermissionError) -> Bool
    /// Idempotent by identifier. Domain hands over a plain value; the adapter builds UNContent.
    func schedule(_ requests: [ScheduledNotification]) async throws(PermissionError)
    func cancel(identifiers: [String]) async
    func cancelAll(matching prefix: String) async
    func pending() async -> [String]
}

/// The domain-side notification value. Contains NO UserNotifications types.
struct ScheduledNotification: Hashable, Sendable {
    let identifier: String                // "reminder.<uuid>.<occurrence>" — deterministic
    let titleKey: LocalizedKey
    let bodyKey: LocalizedKey
    let arguments: [String]
    let fireDate: Date
    let categoryID: String                // for "Mark done" / "Snooze" actions
    let destination: AppDestination       // encoded into userInfo for deep linking
    let threadID: String?                 // groups per-vehicle notifications
    let interruptionLevel: NotificationInterruption   // .passive | .active | .timeSensitive
}

// ─────────────────────────────────────────────────────────── Files
protocol FileStorage: Sendable {
    func store(_ data: Data, preferredName: String, kind: FileKind) async throws(DocumentError) -> FileRef
    func read(_ ref: FileRef) async throws(DocumentError) -> Data
    func url(for ref: FileRef) async throws(DocumentError) -> URL      // for QuickLook/share
    func exists(_ ref: FileRef) async -> Bool
    func availability(_ ref: FileRef) async -> FileAvailability        // .local | .downloading(p) | .remote
    func ensureLocal(_ ref: FileRef) async throws(DocumentError)       // triggers iCloud download
    func delete(_ ref: FileRef) async throws(DocumentError)
    func enqueueForGarbageCollection(_ refs: [FileRef]) async
    func totalSize() async -> Int64                                    // Settings → storage usage
}

// ─────────────────────────────────────────────────────────── Subscriptions
protocol SubscriptionProviding: Sendable {
    func products() async throws(SubscriptionError) -> [SubscriptionProduct]
    func currentEntitlement() async -> Entitlement
    func purchase(_ productID: ProductID) async throws(SubscriptionError) -> PurchaseOutcome
    func restore() async throws(SubscriptionError) -> RestoreOutcome
    func isEligibleForIntroOffer(_ productID: ProductID) async -> Bool     // A-22
    /// Long-lived. Backed by StoreKit's Transaction.updates. Started once, at launch.
    var entitlementUpdates: AsyncStream<Entitlement> { get }
}

// ─────────────────────────────────────────────────────────── Auth
protocol AuthProviding: Sendable {
    func restoreSession() async throws(AuthenticationError) -> AuthSession?
    func signIn(_ credentials: AuthCredentials) async throws(AuthenticationError) -> AuthSession
    func signUp(_ registration: AuthRegistration) async throws(AuthenticationError) -> AuthSession
    func signOut() async throws(AuthenticationError)
    func deleteAccount() async throws(AuthenticationError)
    func refreshTokenIfNeeded() async throws(AuthenticationError) -> AuthSession?
}

enum AuthCredentials: Sendable {
    case email(String, password: String)
    case apple(identityToken: Data, authorizationCode: Data, fullName: PersonNameComponents?)
    case google(idToken: String, accessToken: String)
}

// ─────────────────────────────────────────────────────────── Support ports
protocol ClockProviding: Sendable {
    var now: Date { get }
    var calendar: Calendar { get }
    var timeZone: TimeZone { get }
}

protocol PreferencesProviding: Sendable, AnyObject {
    var unitSystem: UnitSystem { get set }              // .metric | .imperial | .custom(…)
    var defaultCurrency: CurrencyCode { get set }
    var appearance: AppearancePreference { get set }
    var languageOverride: String? { get set }
    var defaultVehicleID: VehicleID? { get set }
    var notificationsEnabled: Bool { get set }
    var telemetryEnabled: Bool { get set }
    var iCloudSyncEnabled: Bool { get set }
    var onboardingCompletedVersion: Int { get set }
    var acknowledgedDisclaimerVersions: Set<Int> { get set }
    var paymentMethodTags: [PaymentMethodTag] { get set }
    var changes: AsyncStream<PreferenceKey> { get }
}

protocol SyncStatusProviding: Sendable {
    var status: AsyncStream<SyncState> { get }
    func currentStatus() async -> SyncState
    var isCloudAccountAvailable: Bool { get async }
}

protocol ConnectivityProviding: Sendable {
    var isOnline: Bool { get async }
    var updates: AsyncStream<Bool> { get }
}

protocol DocumentExporting: Sendable {
    func exportPDF(_ document: ExportableDocument) async throws(DocumentError) -> URL
    func exportArchive(_ archive: DataArchive) async throws(DocumentError) -> URL
}

protocol TelemetryProviding: Sendable {
    func track(_ event: TelemetryEvent)     // no-op when preferences.telemetryEnabled == false
    func recordError(_ error: Error, context: [String: String])
}
```

### 3.1 Note on `UnitSystem` — where conversion happens

`UnitSystem` lives in `PreferencesProviding`, is read by feature `Formatter`s, and **is never seen by
the Domain**. `FuelStatistics.averageConsumption` is always L/100km. `Formatter` renders it as
L/100km, MPG (US), MPG (imperial), or km/L. This is the only correct place for the conversion: a
domain that stores MPG cannot compute a weighted average correctly, because MPG is a reciprocal
measure and averaging reciprocals is not the reciprocal of the average — a classic and very common
bug in this app category.
