# 03 · Domain Model & Entity Relationship Model

All domain types are `struct`, `Sendable`, `Equatable`, `Codable` where export requires it.
All IDs are typed `UUID` wrappers. All timestamps are `Date` in UTC, formatted at presentation.
**No domain type imports anything but `Foundation`.**

---

## 1. Primitives & value objects

```swift
struct VehicleID: Hashable, Codable, Sendable { let raw: UUID }
// …FuelEntryID, ServiceRecordID, ExpenseID, ReminderID, DocumentID,
//   OdometerReadingID, ConversationID, MessageID, InsightID, NotificationID

struct Money: Hashable, Sendable, Codable {
    let amount: Decimal          // never Double. never Float.
    let currency: CurrencyCode
    // + adding two Money of different currency is a compile-time-safe runtime precondition
    //   failure; use MoneyBag for mixed sums (see CostLedger).
}

struct CurrencyCode: Hashable, Sendable, Codable { let iso4217: String }   // "EUR", "SEK"

struct Distance: Hashable, Comparable, Sendable, Codable {   // canonical: kilometres
    let kilometers: Double
    static func miles(_ v: Double) -> Distance
    var miles: Double { get }
}

struct Volume: Hashable, Comparable, Sendable, Codable {     // canonical: litres
    let liters: Double
    static func usGallons(_ v: Double) -> Volume
    static func imperialGallons(_ v: Double) -> Volume
}

struct Odometer: Hashable, Comparable, Sendable, Codable { let value: Distance }

struct VIN: Hashable, Sendable, Codable {                    // validated on construction
    let raw: String                                          // 17 chars, ISO 3779 checksum
    init?(_ raw: String)
}

struct LicensePlate: Hashable, Sendable, Codable {
    let normalized: String                                   // uppercased, whitespace-stripped
    let region: RegionCode?
}

enum RecordSource: Hashable, Sendable, Codable {
    case manual, receiptScan(ReceiptScanID), imported, automatic(providerID: String)   // A-11
}

struct DateRange: Hashable, Sendable, Codable { let start: Date; let end: Date }

enum AnalyticsPeriod: Hashable, Sendable, Codable {
    case week, month, sixMonths, year, allTime, custom(DateRange)
    func range(now: Date, calendar: Calendar) -> DateRange    // pure, calendar-aware, testable
}
```

> **Why `Distance`/`Volume` newtypes rather than `Measurement<UnitLength>`?**
> `Measurement` is `Sendable` and fine, but it invites unit ambiguity at call sites and its
> arithmetic silently converts. A newtype with one canonical unit makes "is this km or miles?"
> unrepresentable and keeps the SwiftData column a plain `Double`. Presentation converts to the
> user's `UnitSystem` in exactly one place: the feature `Formatter`.

---

## 2. Entities

### 2.1 Vehicle — the aggregate root

```swift
struct Vehicle: Identifiable, Hashable, Sendable {
    let id: VehicleID
    var brand: String                     // "Audi"          required
    var model: String                     // "A4"            required
    var year: Int?                        // 2021
    var trim: String?                     // "Quattro"       A-16
    var color: String?                    // "Nardo Grey"    A-16
    var vin: VIN?
    var licensePlate: LicensePlate?
    var registrationCountry: RegionCode?  // "SE"            A-16
    var fuelType: FuelType                // required — drives fuel-entry defaults & consumption units
    var engineDisplacementCC: Int?
    var purchaseDate: Date?
    var purchasePrice: Money?             // needed for Cost of Ownership
    var primaryCurrency: CurrencyCode     // default for all new records on this vehicle (A-13)
    var photoRef: FileRef?                // NOT the image bytes
    var isDefault: Bool                   // exactly one true per user — invariant enforced in use case
    var ownershipScope: OwnershipScope    // .personal (reserved for future CKShare, A-07b)
    let createdAt: Date
    var updatedAt: Date

    // DERIVED — never stored authoritatively. Assembled by repositories/use cases.
    // var currentOdometer: Odometer?     ← comes from OdometerReading, see §2.2
}

enum FuelType: String, CaseIterable, Sendable, Codable {
    case petrol, diesel, lpg, cng, hybridPetrol, hybridDiesel, electric, pluginHybrid, other
    var usesLiquidVolume: Bool     // false for .electric → consumption is kWh/100km
}
```

**Validation (`VehicleValidator`, pure):** brand & model non-empty after trimming;
`year` within `1885...currentYear+2`; VIN either nil or checksum-valid; `engineDisplacementCC` in
`50...10_000`; `purchaseDate` not in the future.

### 2.2 OdometerReading — the decision that pays for itself twice

```swift
struct OdometerReading: Identifiable, Hashable, Sendable {
    let id: OdometerReadingID
    let vehicleID: VehicleID
    let value: Odometer
    let recordedAt: Date
    let source: OdometerSource
    let createdAt: Date
}

enum OdometerSource: Hashable, Sendable, Codable {
    case manual
    case fuelEntry(FuelEntryID)
    case serviceRecord(ServiceRecordID)
    case expense(ExpenseID)
    case obd                                  // reserved
}
```

**Rules.**
- Every record that carries a mileage **creates or updates exactly one linked reading**; deleting the
  parent deletes the reading (cascade).
- `Vehicle.currentOdometer` = reading with the greatest `recordedAt`, tie-broken by greatest `value`.
- Rows are **append-only and immutable except through their parent**, therefore CloudKit
  last-writer-wins can never corrupt current mileage: two devices adding fuel produce two rows, not
  one contested field.
- A reading lower than a prior reading is **allowed** (odometer replacement, clerical error) but
  flagged: `OdometerAnomaly` is surfaced in the fuel calculator as a segment break, not silently
  averaged.

**Why this matters concretely:** without it, "edit a fuel entry from 2023" either corrupts
`Vehicle.currentMileage` or requires a recompute-on-every-write scan. With it, current mileage is a
one-row `FetchDescriptor` with `sortBy` + `fetchLimit: 1`.

### 2.3 FuelEntry

```swift
struct FuelEntry: Identifiable, Hashable, Sendable {
    let id: FuelEntryID
    let vehicleID: VehicleID
    var date: Date
    var odometer: Odometer
    var volume: Volume                    // litres (or kWh for EV — see FuelType)
    var pricePerUnit: Money               // stored AND totalCost stored — see note
    var totalCost: Money
    var fuelType: FuelType                // may differ from vehicle default (E5 vs E10, AdBlue…)
    var station: String?
    var isFullTank: Bool                  // THE field the whole consumption algorithm hinges on
    var missedPreviousFillUp: Bool        // user-declarable; breaks the segment (see 09 §Fuel)
    var paymentMethodTagID: PaymentMethodTagID?   // A-12 — a label, never a PAN
    var note: String?
    var receiptRef: FileRef?
    let source: RecordSource
    let createdAt: Date
    var updatedAt: Date
}
```

> **`pricePerUnit` and `totalCost` are both stored, not derived.** Receipts round; `volume ×
> pricePerUnit` frequently differs from the printed total by a cent. The editor lets the user type
> any two of {volume, pricePerUnit, totalCost} and computes the third, but persists all three as
> entered. `FuelEntryValidator` warns (does not block) when the product deviates > 2%.
> Analytics always uses `totalCost`. Average price is `Σ totalCost / Σ volume`, never a mean of
> `pricePerUnit` — see `09-analytics.md`.

**Validation:** `volume > 0`; `totalCost >= 0`; odometer `>= 0`; `date` not more than 1 day in the
future (timezone slack).

### 2.4 ServiceRecord — multi-item, per A-26

```swift
struct ServiceRecord: Identifiable, Hashable, Sendable {
    let id: ServiceRecordID
    let vehicleID: VehicleID
    var date: Date
    var odometer: Odometer?
    var items: [ServiceItem]              // ≥ 1. THE screenshot-11 "INCLUDE" chips
    var workshop: String?
    var totalCost: Money                  // authoritative; may exceed Σ item costs (fees, VAT)
    var note: String?
    var attachmentRefs: [FileRef]         // photos + receipt/documents
    let source: RecordSource
    let createdAt: Date
    var updatedAt: Date

    var primaryType: ServiceType { items.first?.type ?? .other }   // derived, for list rows
    var isRepair: Bool { items.contains { $0.nature == .repair } } // drives cost categorisation
}

struct ServiceItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var type: ServiceType
    var name: String                       // "Oil change", free text refinement
    var nature: ServiceNature              // .scheduledMaintenance | .repair
    var partCost: Money?
    var laborCost: Money?
    var parts: [PartUsage]                 // name, partNumber?, quantity, unitCost?
}

enum ServiceType: String, CaseIterable, Sendable, Codable {
    case oilChange, filters, brakes, tires, battery, suspension, engine, electrical, other
}
enum ServiceNature: String, Sendable, Codable { case scheduledMaintenance, repair }
```

**Why `nature` exists:** the Expenses screen (13) splits *Maintenance* from *Repairs*. A brake job
can be either. Deriving it from `ServiceType` alone is wrong. The user picks; the default is
`.scheduledMaintenance` for `oilChange`/`filters`/`tires`, `.repair` for `engine`/`electrical`.

**Why multi-item matters:** completing a service record with an `oilChange` item **and** a `filters`
item must satisfy *both* the oil-change reminder and the filter reminder. `CompleteReminder`
consumes `ServiceRecord.items`, not `primaryType`. This is the single most user-visible correctness
consequence of the model.

### 2.5 Expense

```swift
struct Expense: Identifiable, Hashable, Sendable {
    let id: ExpenseID
    let vehicleID: VehicleID
    var title: String
    var category: ExpenseCategory
    var cost: Money
    var date: Date
    var odometer: Odometer?
    var note: String?
    var receiptRef: FileRef?
    let source: RecordSource
    let createdAt: Date
    var updatedAt: Date
}

enum ExpenseCategory: String, CaseIterable, Sendable, Codable {
    case fuel, maintenance, repairs, insurance, parking, carWash, tires, taxes, accessories, other
}
```

**The `.fuel` / `.maintenance` overlap — resolved by flow, not by validation.** See §4.

### 2.6 Reminder

```swift
struct Reminder: Identifiable, Hashable, Sendable {
    let id: ReminderID
    let vehicleID: VehicleID
    var title: String
    var kind: ReminderKind                 // standard type or .custom
    var trigger: ReminderTrigger
    var recurrence: RecurrenceRule
    var note: String?
    var isActive: Bool
    var lastCompletedAt: Date?
    var lastCompletedOdometer: Odometer?
    var leadTime: ReminderLeadTime         // how early to warn: days and/or kilometres
    let createdAt: Date
    var updatedAt: Date
}

enum ReminderKind: Hashable, Sendable, Codable {
    case oilChange, filterReplacement, tireChange, tirePressure, technicalInspection,
         insurance, battery, brakePads, timingBelt, vehicleTax
    case custom
    /// Which ServiceItem types auto-complete this reminder (A-26 / §2.4)
    var satisfyingServiceTypes: Set<ServiceType> { get }
}

enum ReminderTrigger: Hashable, Sendable, Codable {
    case date(DateTrigger)
    case mileage(MileageTrigger)
    case whicheverFirst(DateTrigger, MileageTrigger)      // the spec's third mode
}

struct DateTrigger: Hashable, Sendable, Codable { var dueDate: Date }

struct MileageTrigger: Hashable, Sendable, Codable {      // A-17 — baseline enables the progress bar
    var baselineOdometer: Odometer                        // 82,120 km in screenshot 15
    var intervalDistance: Distance                        // 15,000 km
    var dueOdometer: Odometer { baseline + interval }
}

enum RecurrenceRule: Hashable, Sendable, Codable {
    case none
    case everyMonths(Int)                                 // "Yearly" = .everyMonths(12)
    case everyYears(Int)                                  // "Every 2 years"
    case everyDistance(Distance)                          // "Every 15,000 km"
    case both(months: Int, distance: Distance)            // recur on whichever comes first
    case seasonal(months: Set<Int>)                       // A-18 — "Apr / Nov" tire swap
}

struct ReminderLeadTime: Hashable, Sendable, Codable {
    var days: Int?          // e.g. 14 → "Insurance expires in 14 days"
    var distance: Distance? // e.g. 1000 km → "Oil change due in 520 km" surfaces at ≤1000
}
```

### 2.7 DocumentMetadata — metadata only, never bytes

```swift
struct DocumentMetadata: Identifiable, Hashable, Sendable {
    let id: DocumentID
    let vehicleID: VehicleID?              // nil ⇒ user-level (e.g. Driver License)
    var name: String
    var type: DocumentType
    var startDate: Date?
    var expirationDate: Date?
    var note: String?
    var fileRef: FileRef                   // pointer. the ONLY link to bytes.
    var fileSize: Int64                    // A-19 — "PDF · 12 MB"
    var mimeType: String
    var pageCount: Int?
    var thumbnailRef: FileRef?
    var reminderID: ReminderID?            // auto-created expiry reminder, if any
    let createdAt: Date
    var updatedAt: Date
}

enum DocumentType: String, CaseIterable, Sendable, Codable {
    case insurance, registration, technicalInspection, warranty, driverLicense,
         serviceDocument, purchaseInvoice, manual, other
}

struct FileRef: Hashable, Sendable, Codable {
    let id: UUID
    let relativePath: String               // relative to the storage root. NEVER absolute.
    let checksum: String                   // SHA-256, for sync integrity + dedup
}
```

> **`relativePath` is relative on purpose.** iOS container URLs change between launches, installs and
> devices. Storing absolute URLs is the classic bug that makes every attachment disappear after an
> app update. `FileLocationResolver` turns a `FileRef` into a live `URL` at access time.

### 2.8 AppNotification — the in-app inbox (A-25)

```swift
struct AppNotification: Identifiable, Hashable, Sendable {
    let id: NotificationID
    let vehicleID: VehicleID?
    var kind: NotificationKind
    var title: String                      // pre-localised at creation time? NO — see below
    var titleKey: LocalizedKey             // stored as a key + arguments, localised at render
    var arguments: [String]
    var createdAt: Date
    var readAt: Date?
    var destination: AppDestination?       // tapping the row navigates here
}

enum NotificationKind: String, Sendable, Codable {
    case documentExpiring, reminderDue, aiInsight, fuelLogged, syncIssue, subscriptionLapsed
}
```

Stored as **keys + arguments, not rendered strings** — otherwise changing the app language leaves a
Swedish inbox in English. Same rule for `UNNotificationContent`, which is built at *schedule* time
and therefore uses `NSString(localizedUserNotificationString:arguments:)`.

### 2.9 AI entities

```swift
struct AIConversation: Identifiable, Hashable, Sendable {
    let id: ConversationID
    var vehicleID: VehicleID?              // context binding; nil = general automotive question
    var title: String                      // auto-derived from first user message
    var messages: [AIMessage]              // ordered, ascending
    var contextVersion: Int                // which AIVehicleContext schema produced this thread
    let createdAt: Date
    var updatedAt: Date
}

struct AIMessage: Identifiable, Hashable, Sendable {
    let id: MessageID
    let role: AIMessageRole                // .user | .assistant | .systemNotice
    var text: String
    var attachments: [FileRef]             // scanned images that seeded the turn
    var isPartial: Bool                    // true if the stream was cancelled mid-flight
    var failure: AIMessageFailure?         // rendered inline; the turn is kept, not discarded
    let createdAt: Date
}

struct AIInsight: Identifiable, Hashable, Sendable {
    let id: InsightID
    let vehicleID: VehicleID
    var headline: String                   // "Fuel consumption up 9% this month"
    var body: String
    var severity: InsightSeverity          // .info | .attention | .warning
    var supportingMetrics: [MetricReference]   // ← the anti-hallucination contract
    var generatedAt: Date
    var validUntil: Date
    var sourcePeriod: DateRange
    var dismissedAt: Date?
}

/// Points at a metric the StatisticsEngine ACTUALLY produced. An insight citing an unknown
/// metric ID is REJECTED by GenerateAIInsights before persistence. See 08 §Grounding.
struct MetricReference: Hashable, Sendable, Codable {
    let metricID: MetricID                 // enum-backed, closed set
    let value: Double
    let period: DateRange
}
```

### 2.10 Scan results — three related but distinct shapes

```swift
/// Receipt: a DRAFT. Never a persisted financial record until confirmed. See §5.
struct ReceiptScan: Identifiable, Hashable, Sendable {
    let id: ReceiptScanID
    let vehicleID: VehicleID
    let imageRef: FileRef
    let recognizedText: String?            // on-device OCR, kept for audit/offline
    var draft: ReceiptDraft
    var status: ScanStatus                 // .analyzing | .awaitingReview | .confirmed(RecordRef) | .discarded
    let createdAt: Date
}

struct ReceiptDraft: Hashable, Sendable {
    var suggestedRecordKind: RecordKind    // .fuel | .service | .expense  ← what we'd create
    var vendor: FieldSuggestion<String>
    var date: FieldSuggestion<Date>
    var total: FieldSuggestion<Money>
    var currency: FieldSuggestion<CurrencyCode>
    var odometer: FieldSuggestion<Odometer>
    var serviceItems: [FieldSuggestion<ServiceItem>]
    var laborCost: FieldSuggestion<Money>
    var expenseCategory: FieldSuggestion<ExpenseCategory>
    var fuelVolume: FieldSuggestion<Volume>
    var fuelPricePerUnit: FieldSuggestion<Money>
}

/// Every extracted field carries its confidence and whether the human touched it.
struct FieldSuggestion<T: Hashable & Sendable>: Hashable, Sendable {
    var value: T?
    var confidence: Double                 // 0…1 from the provider
    var wasEditedByUser: Bool
    var isAccepted: Bool
}

struct DashboardScan: Identifiable, Hashable, Sendable {
    let id: UUID
    let vehicleID: VehicleID?
    let imageRef: FileRef
    var findings: [DashboardFinding]
    let disclaimer: AIDisclaimer           // NON-OPTIONAL. see §6
    let createdAt: Date
}

struct DashboardFinding: Hashable, Sendable {
    var warningName: String                // "Check Engine"
    var likelyCauses: [String]
    var severity: FindingSeverity          // .informational | .soon | .urgent | .stopDriving
    var recommendedAction: String
    var drivingSafety: DrivingSafetyAssessment   // .likelySafe | .cautionAdvised | .doNotDrive | .unknown
    var confidence: Double
}

struct DamageAnalysis: Identifiable, Hashable, Sendable {
    let id: UUID
    let vehicleID: VehicleID
    let imageRefs: [FileRef]
    var findings: [DamageFinding]
    let disclaimer: AIDisclaimer           // NON-OPTIONAL
    let createdAt: Date
}

struct DamageFinding: Hashable, Sendable {
    var damageType: String
    var severity: DamageSeverity           // .cosmetic | .moderate | .structural | .unknown
    var suggestedRepair: String
    var cosmeticRepairPossible: Bool?
    var estimatedCost: CostEstimateRange?  // ← a RANGE. never a single number. see §6
}

struct CostEstimateRange: Hashable, Sendable {
    let low: Money
    let high: Money
    let basis: EstimateBasis               // .aiEstimate | .regionalAverage
    let confidence: Double
}
```

### 2.11 Identity & entitlement

```swift
struct UserProfile: Identifiable, Hashable, Sendable {   // ACCOUNT identity, not data identity (A-03)
    let id: UserID                         // backend subject
    var displayName: String?
    var email: String?
    var authProvider: AuthProvider         // .apple | .google | .email
    var avatarRef: FileRef?
    let createdAt: Date
}

struct Entitlement: Hashable, Sendable {
    var tier: SubscriptionTier             // .free | .premium
    var source: EntitlementSource          // .none | .direct | .familyShared | .introOffer | .grace
    var expiresAt: Date?
    var willAutoRenew: Bool
    var isInBillingRetry: Bool
    var lastVerifiedAt: Date

    static let free = Entitlement(tier: .free, source: .none, …)
}

enum PremiumFeature: String, CaseIterable, Sendable {
    case multipleVehicles, aiChat, receiptScan, dashboardScan, damageAnalysis,
         advancedAnalytics, aiInsights, pdfExport, plateScan, prioritySupport
}

enum FeatureAccess: Hashable, Sendable {
    case allowed
    case allowedWithQuota(remaining: Int, resetsAt: Date)
    case locked(LockReason)                // .requiresPremium | .quotaExhausted(resetsAt:) | .requiresSignIn
}
```

---

## 3. Entity Relationship Model

```
                                    ┌──────────────┐
                                    │ UserProfile  │  (account identity; NOT the data owner — A-03)
                                    └──────────────┘
                                            │ 0..1 (soft link, no FK)
   ┌────────────────────────────────────────┴──────────────────────────────────────────┐
   │                                                                                    │
┌──▼──────────┐ 1                                                                       │
│  Vehicle    │───────────────────────────────────────────────────────────────┐         │
│ (aggregate  │                                                               │         │
│   root)     │                                                               │         │
└──┬──────────┘                                                               │         │
   │ 1                                                                        │         │
   ├──────────────► * OdometerReading   (cascade delete; append-only)         │         │
   ├──────────────► * FuelEntry         (cascade delete) ──1:0..1──► OdometerReading
   ├──────────────► * ServiceRecord     (cascade delete) ──1:0..1──► OdometerReading
   │                     │ 1..*                                                          │
   │                     └────► ServiceItem  (owned value, no identity outside parent)   │
   │                                 │ 0..*                                              │
   │                                 └────► PartUsage                                    │
   ├──────────────► * Expense          (cascade delete) ──1:0..1──► OdometerReading      │
   ├──────────────► * Reminder         (cascade delete)                                  │
   ├──────────────► * DocumentMetadata (cascade delete) ──0..1──► Reminder (expiry)      │
   ├──────────────► * AIInsight        (cascade delete)                                  │
   ├──────────────► * AppNotification  (nullify: vehicle-less notices survive)           │
   └──────────────► 0..* AIConversation (NULLIFY, not cascade — see below)               │
                                                                                          │
   PaymentMethodTag ◄──0..1── FuelEntry   (user-level, shared across vehicles) ───────────┘

   FileRef is NOT an entity. It is an embedded value pointing into FileStorage.
   Vehicle.photoRef, FuelEntry.receiptRef, ServiceRecord.attachmentRefs,
   DocumentMetadata.fileRef/thumbnailRef, AIMessage.attachments, *Scan.imageRef(s)
```

### 3.1 Ownership & deletion strategy

| Relationship | Rule | Rationale |
|---|---|---|
| Vehicle → Fuel/Service/Expense/Odometer/Reminder/Document/Insight | **Cascade** | Records are meaningless without their vehicle |
| Vehicle → AIConversation | **Nullify** | Chats are a user asset. Deleting a car should not delete the conversation where you diagnosed it. The thread keeps its transcript and shows "vehicle removed". |
| Vehicle → AppNotification | **Nullify** | The inbox is user-level |
| ServiceRecord → ServiceItem/PartUsage | **Cascade**, owned values | No independent identity |
| Fuel/Service/Expense → OdometerReading | **Cascade** | The reading exists because the record does |
| DocumentMetadata → Reminder (expiry) | **Cascade** the reminder | Deleting the insurance PDF should remove its expiry alert |
| Any entity → `FileRef` | **No cascade.** Deletion enqueues an `OrphanedFile` job | Files may be shared (a receipt attached to both a service record and a document). Refcount-free GC by sweep — see `11-notifications-and-files.md §GC` |

**Hard delete, not soft delete.** No `deletedAt` on any entity. Reasons: CloudKit mirroring
propagates deletes natively; tombstones double the row count and every query gains a
`deletedAt == nil` predicate that will eventually be forgotten somewhere; there is no
multi-user undo requirement. **Undo is handled in the UI layer** with a 5-second "Undo" snackbar
backed by an in-memory `PendingDeletion` buffer that defers the actual repository call. → ADR-006

### 3.2 Synchronization metadata — deliberately minimal

Every entity carries `createdAt` and `updatedAt`. That is all.

**No `localID`/`remoteID`** — SwiftData's `PersistentIdentifier` plus CloudKit's `CKRecord.ID` are
maintained by the mirroring layer; a parallel ID scheme creates two sources of truth.
**No `syncStatus`** — `NSPersistentCloudKitContainer` does not expose per-row sync state and cannot
be told to respect ours. **No `version`** — its only use is optimistic-concurrency conflict
detection, which the mirroring layer resolves internally before we could act on it.
**No `deletedAt`** — see above.

The full `SyncMetadata` shape *is* specified in `07-persistence-and-sync.md §6` as the migration
target for the day a custom backend replaces CloudKit. It is not built now. → ADR-003

---

## 4. THE EXPENSE DECISION (explicit, as required)

> **Decision: `FuelEntry` and `ServiceRecord` are NOT financial transactions in storage. There is no
> unified `Expense` table. There IS a unified `CostEntry` read-model produced by `CostLedger`.**

### 4.1 What was rejected

| Option | Why rejected |
|---|---|
| **A. One `Transaction` table; fuel/service are subtypes or side-tables** | Forces every fuel write into a two-row transaction, makes the Fuel feature depend on the Expense feature, and pushes single-table-inheritance nulls (`volume`, `pricePerUnit`, `workshop`) into a table where 80% of rows don't use them. CloudKit mirroring makes multi-row atomicity awkward. |
| **B. Fuel/Service each *also* write an `Expense` row** | Guaranteed double-counting the first time an edit or a sync conflict touches one row and not the other. This is the exact failure the spec warns about. |
| **C. Analytics reads raw tables and sums ad hoc** | Every analytics surface re-implements categorisation; the Home "this month" figure and the Analytics "this month" figure drift apart. |

### 4.2 What was chosen

```swift
/// A pure projection. Not persisted. Not an entity. Rebuilt on demand, cheap, deterministic.
struct CostEntry: Hashable, Sendable, Identifiable {
    let id: CostEntryID              // deterministic: derived from the source record's ID
    let vehicleID: VehicleID
    let date: Date
    let amount: Money
    let category: ExpenseCategory    // the ONE categorisation vocabulary
    let odometer: Odometer?
    let origin: CostOrigin
    let title: String
}

enum CostOrigin: Hashable, Sendable {
    case fuel(FuelEntryID)
    case service(ServiceRecordID)
    case expense(ExpenseID)
    case vehiclePurchase(VehicleID)   // included only in Cost-of-Ownership reports
}

enum CostLedger {                     // pure. static. no I/O.
    static func entries(
        fuel: [FuelEntry],
        services: [ServiceRecord],
        expenses: [Expense],
        vehicle: Vehicle,
        includePurchasePrice: Bool
    ) -> [CostEntry]
}
```

**Categorisation rules (deterministic, tested):**

| Source | Resulting `ExpenseCategory` |
|---|---|
| `FuelEntry` | `.fuel` — always |
| `ServiceRecord` where any item `nature == .repair` | `.repairs` |
| `ServiceRecord`, all items `.scheduledMaintenance`, any item `type == .tires` | `.tires` |
| `ServiceRecord`, otherwise | `.maintenance` |
| `Expense` | its own `category` |
| `Vehicle.purchasePrice` | `.other`, and only in Cost-of-Ownership |

### 4.3 How double-counting is prevented

1. **Every write flow produces exactly one record.** `ConfirmReceiptScan` takes a
   `RecordKind` and writes a fuel entry **or** a service record **or** an expense. Never two.
   This is enforced by the use case's signature, not by a runtime check.
2. **The Quick-Log menu (screen 04) offers Add Fuel / Add Service / Add Expense as separate
   destinations.** A user logging a fill-up lands in the fuel editor.
3. **`CostEntry.id` is derived from the source record's ID**, so even if the same record were somehow
   projected twice, `Set<CostEntry>` deduplicates it. Belt and braces.
4. **A manually created `Expense` with `category == .fuel` is fully counted.** It is a real fuel
   purchase the user chose to log as an expense (no volume, so it contributes to cost analytics but
   not to consumption analytics). This is correct behaviour, not a bug — and it is exactly why
   `FuelStatistics` derives from `[FuelEntry]` while `AnalyticsReport` derives from `[CostEntry]`.
   The two are **different questions** and must never be computed from the same array.

### 4.4 Consequence for Analytics

```
FuelEntry[]      ─┐
ServiceRecord[]  ─┼─► CostLedger.entries() ─► [CostEntry] ─► StatisticsEngine ─► AnalyticsReport
Expense[]        ─┘

FuelEntry[]      ────► FuelConsumptionCalculator ────────────► FuelStatistics
OdometerReading[]─────┘
```

Two engines, two inputs, one shared vocabulary. Screen 13's `Fuel €1,842 / Service €1,120 /
Other €1,324` is a `CategoryBreakdown` over `[CostEntry]`. Screen 05-Fuel's `6.2 L/100km` is a
`FuelStatistics`. They never touch each other's inputs.

---

## 5. THE RECEIPT-SCAN STATE MACHINE (explicit, as required)

The spec's hardest constraint: *"Receipt Scan MUST NOT automatically persist extracted data without
user confirmation"* and *"Do not hide this logic inside a ViewModel."*

The state machine lives in the **Domain**, as a value type:

```swift
enum ReceiptScanState: Hashable, Sendable {
    case capturing
    case recognizing(imageRef: FileRef)                    // on-device OCR
    case analyzing(imageRef: FileRef, text: String?)       // remote AI
    case awaitingReview(ReceiptScan)                       // ◄── PERSISTENCE IS IMPOSSIBLE HERE
    case editing(ReceiptScan)
    case confirming(ReceiptScan, resolved: ConfirmedReceipt)
    case saved(RecordRef)
    case failed(AIError, retryable: Bool)
    case discarded
}

/// Constructible ONLY from a fully-resolved draft with an explicit user act.
/// The initializer is failable and validates that every REQUIRED field is accepted.
struct ConfirmedReceipt: Sendable {
    let scanID: ReceiptScanID
    let vehicleID: VehicleID
    let kind: RecordKind
    let payload: ConfirmedPayload      // .fuel(FuelEntryDraft) | .service(…) | .expense(…)
    let confirmedAt: Date
    init?(reviewing scan: ReceiptScan, at date: Date)
}
```

- `ScanReceipt` (use case) can **only** reach `.awaitingReview`. It has **no repository dependency
  for financial records at all** — it literally cannot save one. It writes only the image via
  `FileStorage` and the `ReceiptScan` itself (as an audit record).
- `ConfirmReceiptScan` (a separate use case) takes a `ConfirmedReceipt` — a type that cannot be
  constructed without a user review pass — and is the only path to `AddFuelEntry` /
  `AddServiceRecord` / `AddExpense`.
- The ViewModel owns *presentation* of the state machine; it does not define it, and it cannot skip
  a state, because the type system forbids constructing `ConfirmedReceipt` out of thin air.

**Test that must exist:** `ScanReceipt`'s dependency list contains no financial repository
(compile-time), and a scan that reaches `.failed` or `.discarded` leaves all repositories with zero
writes (runtime).

---

## 6. THE DISCLAIMER MODEL (explicit, as required)

Dashboard Scan and Damage Analysis results are **informational estimates**, and the spec requires
that be represented in the architecture rather than in UI copy.

```swift
struct AIDisclaimer: Hashable, Sendable, Codable {
    let kind: DisclaimerKind         // .notProfessionalDiagnostics | .costEstimateOnly | .bothOfTheAbove
    let textKey: LocalizedKey        // localised at render, versioned with the legal copy
    let version: Int
    let acknowledgedAt: Date?        // set when the user taps through the first-run modal
}
```

Enforcement, structurally:

1. `DashboardScan.disclaimer` and `DamageAnalysis.disclaimer` are **non-optional `let`s**. A result
   without a disclaimer is unrepresentable.
2. `DamageFinding.estimatedCost` is `CostEstimateRange?` — there is **no** `estimatedCost: Money`
   field anywhere. A single guaranteed price is unrepresentable.
3. `ScanDashboard` and `AnalyzeDamage` use cases require `DisclaimerAcknowledgement` to have been
   recorded (first run per disclaimer `version`); otherwise they return
   `.requiresDisclaimerAcknowledgement` and the router presents the acknowledgement sheet.
4. `DashboardFinding.drivingSafety` includes `.unknown`, and the provider's structured-output schema
   **defaults to `.unknown`** on a missing or unparseable value. The failure mode is "we don't know",
   never "safe to drive".
5. Neither result type is offered a "save as service record" shortcut. Acting on the result requires
   the user to open the normal Add Service flow.
