# 04 · Use Cases

**Shape.** Every use case is a `Sendable` struct with injected dependencies and a single
`callAsFunction` (or `execute`) method. Not a protocol by default — protocols are added **only**
where a ViewModel test needs a fake (marked ⓟ below). Over-protocolising 60 use cases is exactly
the "unnecessary abstraction" the brief forbids.

```swift
struct AddFuelEntry: Sendable {
    let fuelRepo: any FuelRepository
    let odometerRepo: any OdometerRepository
    let reminders: RescheduleRemindersForVehicle
    let clock: any ClockProviding

    func callAsFunction(_ input: Input) async throws(DomainError) -> Output
}
```

**Universal rules for all use cases**

- They never call `Date()`, `UUID()` or `Calendar.current` directly — `ClockProviding` and
  `IDGenerating` are injected. This is what makes date-sensitive tests deterministic.
- They own the **transaction boundary**. A use case that writes two entities does so in one
  `PersistenceActor` transaction.
- They throw `DomainError` (typed throws where the surface is closed).
- They never touch navigation, formatting, or `ViewState`.
- Validation happens **in the use case**, calling pure `…Validator` domain functions. Never in the
  ViewModel, never in the repository.

---

## 1. Vehicle & Garage

### `CreateVehicle` ⓟ
| | |
|---|---|
| **Responsibility** | Create a vehicle, enforce the free-tier limit, establish the default-vehicle invariant, seed the initial odometer reading and the standard reminder set |
| **Input** | `VehicleDraft` (brand, model, year, trim, color, fuelType, vin?, plate?, displacement?, purchaseDate?, purchasePrice?, currency, initialOdometer, photoData?) |
| **Output** | `Vehicle` |
| **Dependencies** | `VehicleRepository`, `OdometerRepository`, `ReminderRepository`, `FileStorage`, `FeatureGating`, `EntitlementProviding`, `Clock`, `IDGenerator` |
| **Errors** | `.validation(VehicleValidationError)`, `.subscription(.vehicleLimitReached)`, `.persistence`, `.document(.fileWriteFailed)` |
| **Business rules** | 1. `FeatureGating.evaluate(.multipleVehicles)` is consulted **before** validation; free tier with ≥1 existing vehicle → `.vehicleLimitReached` carrying a paywall context. 2. **If this is the first vehicle it becomes `isDefault = true`** and is set as selected. 3. If not the first, `isDefault = false`. 4. Exactly-one-default is re-asserted transactionally. 5. An `OdometerReading(source: .manual)` is written for `initialOdometer`. 6. Photo bytes go to `FileStorage`; only the `FileRef` is persisted. 7. A default reminder set is seeded from `ReminderTemplate.defaults(for: fuelType)` — oil change, inspection, insurance — all `isActive: false` until the user opts in, so we never spam notifications for a car we know nothing about. |

### `UpdateVehicle` · `DeleteVehicle` ⓟ
`DeleteVehicle` rules: cascade per `03 §3.1`; enqueue every referenced `FileRef` for orphan GC;
cancel all pending notifications for that vehicle; **if the deleted vehicle was the default, promote
the most recently updated remaining vehicle**; if none remain, clear `SelectedVehicleStore` and route
to the empty-garage state.

### `SetDefaultVehicle` ⓟ
Transactionally clears `isDefault` on all others. Writes the ID to preferences so it survives
relaunch. Updates `SelectedVehicleStore`. Errors: `.validation(.vehicleNotFound)`.

### `LoadGarage`
Returns `[VehicleSummary]` — each carrying `currentOdometer`, `health`, counts of fuel/service/docs
(the screenshot-07 "12 records / 48 fill-ups / 6 active"). Uses aggregate count fetches, **not** full
object loads.

### `UpdateOdometer`
Appends an `OdometerReading(source: .manual)`, then calls `RescheduleRemindersForVehicle`.
Rule: a value lower than the current max is accepted but returns `.warning(.odometerRegression)` in
the output so the editor can confirm with the user.

### `RecognizeLicensePlate` (A-15) — Premium
`TextRecognizer` → `PlateRecognizer` (region format validation) → `VehicleDraft` prefill.
**No registry lookup.** Errors: `.permission(.cameraDenied)`, `.validation(.plateNotRecognized)`.

---

## 2. Fuel

### `AddFuelEntry` ⓟ
| | |
|---|---|
| **Input** | `FuelEntryDraft(vehicleID, date, odometer, volume, pricePerUnit?, totalCost?, fuelType, station?, isFullTank, missedPreviousFillUp, paymentTagID?, note?, receiptData?, source)` |
| **Output** | `FuelEntry` + `[FuelWarning]` |
| **Dependencies** | `FuelRepository`, `OdometerRepository`, `FileStorage`, `RescheduleRemindersForVehicle`, `Clock`, `IDGenerator` |
| **Errors** | `.validation(.nonPositiveVolume / .negativeCost / .futureDate)`, `.persistence` |
| **Business rules** | 1. Exactly two of {volume, pricePerUnit, totalCost} required; the third is computed. All three persisted (`03 §2.3`). 2. Deviation > 2% between `volume × pricePerUnit` and `totalCost` → **warning, not error**. 3. Writes a linked `OdometerReading(source: .fuelEntry(id))` in the same transaction. 4. Odometer below the vehicle max → `.odometerRegression` warning. 5. Triggers reminder rescheduling because a new odometer changes every mileage projection (A-10). 6. **Does not** create an `Expense` (`03 §4`). |

### `UpdateFuelEntry` · `DeleteFuelEntry` ⓟ
Both must update/delete the linked `OdometerReading` in the same transaction, then reschedule
reminders. `UpdateFuelEntry` changing `isFullTank` invalidates cached fuel statistics.

### `CalculateFuelStatistics` ⓟ
| | |
|---|---|
| **Responsibility** | Fetch, then delegate to the pure `FuelConsumptionCalculator`. Contains zero maths itself. |
| **Input** | `vehicleID`, `AnalyticsPeriod` |
| **Output** | `FuelStatistics` (avg L/100km, cost/100km, avg price, total volume, total cost, `[FuelSegment]`, `ConsumptionTrend`, `[DataQualityIssue]`) |
| **Dependencies** | `FuelRepository`, `FeatureGate` (period clamping, A-06), `Calendar` |
| **Business rules** | Full algorithm in `09-analytics.md §1`. The use case's only rules: clamp the period for free tier; return `.insufficientData` (not an error) when fewer than two full-tank entries exist. |

---

## 3. Service

### `AddServiceRecord` ⓟ
| | |
|---|---|
| **Input** | `ServiceRecordDraft(vehicleID, date, odometer?, items[≥1], workshop?, totalCost, note?, attachments[], source)` |
| **Output** | `ServiceRecord` + `[ReminderID]` (which reminders were auto-completed) |
| **Dependencies** | `ServiceRepository`, `OdometerRepository`, `ReminderRepository`, `CompleteReminder`, `FileStorage`, `Clock`, `IDGenerator` |
| **Errors** | `.validation(.noServiceItems / .negativeCost)`, `.persistence` |
| **Business rules** | 1. ≥1 item required. 2. `totalCost` is authoritative; if item costs sum higher, warn. 3. Writes the linked `OdometerReading`. 4. **Auto-completes every active reminder whose `kind.satisfyingServiceTypes` intersects the record's item types** — this is why the record is multi-item (`03 §2.4 / A-26`). Auto-completion is *proposed* in the output and applied only if the user did not opt out in the editor; the use case takes `autoCompleteReminders: Bool`. 5. Reschedules reminders. |

### `QueryServiceHistory`
Input: `ServiceQuery(vehicleID, dateRange?, odometerRange?, types: Set<ServiceType>?, nature?, searchText?, sort, page)`.
Output: `Page<ServiceRecord>`. Satisfies the spec's "query by vehicle / date / mileage / type".
Backed by a compound `FetchDescriptor` with `#Index` on `(vehicleID, date)` and `(vehicleID, odometer)`.

---

## 4. Expenses

### `AddExpense` ⓟ / `UpdateExpense` / `DeleteExpense` / `LoadExpenses`
`AddExpense` rules: title non-empty; `cost >= 0`; writes a linked `OdometerReading` **only if**
odometer supplied; receipt image via `FileStorage`; **does not create fuel or service records**.
`LoadExpenses` returns `Page<Expense>` plus, for screen 13, a `CategoryBreakdown` obtained from
`BuildAnalyticsReport` — the expenses screen does **not** compute its own totals.

---

## 5. Reminders

### `CreateReminder` ⓟ / `UpdateReminder` / `DeleteReminder`
| | |
|---|---|
| **Input** | `ReminderDraft(vehicleID, title, kind, trigger, recurrence, leadTime, note?)` |
| **Output** | `Reminder` |
| **Dependencies** | `ReminderRepository`, `OdometerRepository`, `NotificationScheduling`, `MileageProjector`, `Clock` |
| **Errors** | `.validation(.emptyTitle / .pastDueDate / .nonPositiveInterval / .triggerMismatch)`, `.permission(.notificationsDenied)` |
| **Business rules** | 1. `.mileage` trigger requires `baselineOdometer` — defaults to the vehicle's current reading (A-17). 2. `.seasonal` requires ≥1 month (A-18). 3. `.everyDistance` recurrence with a `.date`-only trigger is a `.triggerMismatch`. 4. Scheduling is delegated, never performed here — the domain never sees `UNUserNotificationCenter`. 5. Denied notification permission does **not** fail creation; the reminder is created and a `PermissionError` is returned as a *warning* so the UI can offer Settings. |

### `EvaluateReminderTriggers` ⓟ — the core reminder use case
| | |
|---|---|
| **Responsibility** | Determine, exactly and in-app, which reminders are due/overdue/upcoming right now |
| **Input** | `vehicleID?` (nil = all vehicles), `now: Date` |
| **Output** | `[ReminderEvaluation]` — `{ reminder, status, progress, dueDateEstimate?, remainingDistance? }` |
| **Dependencies** | `ReminderRepository`, `OdometerRepository`, `ReminderEvaluator` (pure), `MileageProjector` (pure), `Clock` |
| **Business rules** | Delegates entirely to `ReminderEvaluator.evaluate(reminder:context:)`. The rules themselves: <br>· `.date` → overdue if `now > dueDate`; upcoming if `now >= dueDate - leadTime.days`. <br>· `.mileage` → overdue if `current >= dueOdometer`; upcoming if `current >= dueOdometer - leadTime.distance`. <br>· **`.whicheverFirst` → `min` of the two by *actual occurrence*, not by projection.** Precisely: overdue if *either* condition is overdue; otherwise upcoming if *either* is upcoming; the surfaced "reason" is whichever is closer in normalised terms (days-to-due vs. projected-days-to-due). This is the case the spec calls out and it gets its own test matrix (`13-testing.md §3`). <br>· Inactive reminders are excluded. <br>· A vehicle with no odometer reading yields `.indeterminate` for mileage triggers — never "overdue". |

### `CompleteReminder` ⓟ
Sets `lastCompletedAt/Odometer`; applies `RecurrenceCalculator.next(after:)` to roll the trigger
forward (`.everyDistance` rebases `baselineOdometer` to the completion odometer — this is what makes
the screenshot-15 progress bar restart correctly); deactivates non-recurring reminders; reschedules
notifications. Can be invoked by the user **or** automatically by `AddServiceRecord`.

### `RescheduleRemindersForVehicle`
Internal use case called after **every** odometer-producing write and on app foreground.
Recomputes mileage projections and re-registers `UNNotificationRequest`s. Idempotent by design:
it cancels the vehicle's pending requests and re-adds from scratch, keyed
`reminder.<id>.<occurrenceIndex>`.

---

## 6. Documents

### `AddDocument` ⓟ
| | |
|---|---|
| **Input** | `DocumentDraft(vehicleID?, name, type, startDate?, expirationDate?, note?, fileData or sourceURL, createExpiryReminder: Bool)` |
| **Output** | `DocumentMetadata` |
| **Dependencies** | `DocumentRepository`, `FileStorage`, `ThumbnailGenerating`, `CreateReminder`, `Clock`, `IDGenerator` |
| **Errors** | `.document(.unsupportedType / .fileTooLarge / .fileWriteFailed)`, `.validation(.expirationBeforeStart)` |
| **Business rules** | 1. Bytes → `FileStorage` **first**; metadata row is written only on success, so a failed write never leaves a dangling row. 2. Max 50 MB; allowed UTIs: PDF, JPEG, PNG, HEIC. 3. Thumbnail generated asynchronously; absence is not an error. 4. `expirationDate` present && `createExpiryReminder` → creates a `.custom` reminder with `leadTime.days = 30` (and 14/7/1 escalation notifications), linked via `DocumentMetadata.reminderID`. |

### `EvaluateDocumentExpiries` ⓟ
Pure delegation to `DocumentExpiryEvaluator`. Output `[DocumentExpiry]` with
`.valid / .expiringSoon(daysRemaining) / .expired(daysAgo)`. Feeds the Documents grid badges
(screenshot 06: "Expires 14 Nov 2025" vs "Until 2024"), the Home *Upcoming* list and the Alerts
inbox. `expirationDate == nil` → `.noExpiry`, never `.expired`.

### `QueryDocuments` · `OpenDocumentFile` · `DeleteDocument`
`QueryDocuments` supports the screenshot-06 search bar: free-text over `name` + `note` + type
display name. `OpenDocumentFile` resolves `FileRef` → `URL`, triggering an iCloud download with
progress if the file is not local (`11 §File storage`). `DeleteDocument` deletes the metadata row and
its expiry reminder, and enqueues the file for GC.

---

## 7. Home & Analytics

### `LoadHomeDashboard` ⓟ — the composite use case
| | |
|---|---|
| **Responsibility** | Assemble everything screen 02-Home shows, in one call, in parallel |
| **Input** | `vehicleID`, `now: Date` |
| **Output** | `HomeDashboard { vehicle, health, currentOdometer, nextService: NextServiceInfo?, latestFuelEntry?, fuelStatistics, currentMonthSpend: Money, monthOverMonthDelta: Double?, upcomingEvents: [UpcomingEvent], recentActivity: [ActivityItem], insights: [AIInsight], unreadNotificationCount: Int }` |
| **Dependencies** | `LoadVehicle`, `CalculateFuelStatistics`, `BuildAnalyticsReport`, `EvaluateReminderTriggers`, `EvaluateDocumentExpiries`, `LoadRecentActivity`, `AIInsightRepository`, `VehicleHealthScorer`, `Clock` |
| **Business rules** | 1. Runs its sub-queries concurrently in a `TaskGroup`; total latency ≈ the slowest, not the sum. 2. **Reads only cached AI insights** — never triggers a network call. Home must render offline. 3. `upcomingEvents` merges reminder evaluations and document expiries into one sorted feed (`UpcomingEvent` — the screenshot shows "Oil change · Due in 520 km" beside "Insurance renewal · Expires in 14 days"; these come from two different entities). 4. `recentActivity` merges the five most recent fuel/service/expense/document writes into `[ActivityItem]`. 5. `health` from the deterministic `VehicleHealthScorer` (A-14), never from AI. |

### `BuildAnalyticsReport` ⓟ
| | |
|---|---|
| **Input** | `vehicleID?` (nil = all vehicles), `AnalyticsPeriod` |
| **Output** | `AnalyticsReport` (see `09-analytics.md §3`) |
| **Dependencies** | `FuelRepository`, `ServiceRepository`, `ExpenseRepository`, `OdometerRepository`, `VehicleRepository`, `CostLedger`, `StatisticsEngine`, `FeatureGate`, `Calendar` |
| **Business rules** | 1. Free tier: period clamped to 12 months (A-06), and the report carries `wasClampedByEntitlement: true` so the UI can offer an upgrade instead of silently lying. 2. Mixed currencies are **grouped, never summed** (A-13). 3. Fully deterministic: same inputs + same `now` ⇒ byte-identical output. |

### `LoadUserStatistics`
Cheap counts for screen 08-Profile ("1 Vehicle · 48 Fill-ups · 12 Services"). Count-only fetches.

---

## 8. AI

### `AskAI` ⓟ — the streaming use case
| | |
|---|---|
| **Responsibility** | Append the user turn, build context, stream the assistant turn, persist on completion |
| **Input** | `AskAIInput(conversationID: ConversationID?, vehicleID: VehicleID?, text: String, attachments: [FileRef])` |
| **Output** | `AsyncThrowingStream<AIStreamEvent, Error>` where `AIStreamEvent = .conversationCreated(ID) \| .userMessageSaved(AIMessage) \| .delta(String) \| .assistantCompleted(AIMessage) \| .usage(AIUsage)` |
| **Dependencies** | `AIConversationRepository`, `BuildAIContext`, `AIProvider`, `FeatureGate`, `Connectivity`, `Clock`, `IDGenerator` |
| **Errors** | `.ai(.quotaExceeded(resetAt:))` → paywall, `.ai(.offline)`, `.ai(.providerUnavailable)`, `.ai(.cancelled)`, `.ai(.contentFiltered)`, `.subscription(.requiresPremium)` |
| **Business rules** | 1. **Gate first**: `FeatureGate.evaluate(.aiChat)`; `.locked` short-circuits before any network call. 2. The **user message is persisted immediately**, before the request — so a crash or cancel never loses what the user typed. 3. Context is built by `BuildAIContext` (`08 §Context`), bounded and deterministic; the raw database is never sent. 4. On cancellation the partial assistant text is persisted with `isPartial = true`. Users lose nothing. 5. On failure the assistant message is persisted with `failure` set, so the thread renders the error inline and offers retry — the transcript is never silently truncated. 6. Server quota response (A-08) overrides the local counter. |

### `LoadConversation` · `ListConversations` · `DeleteConversation`
`ListConversations` powers screen 07-AI "RECENT CHATS". `DeleteConversation` removes attachments'
`FileRef`s via GC.

### `ScanReceipt` ⓟ
| | |
|---|---|
| **Responsibility** | Capture → OCR → AI → **`.awaitingReview`**. Stops there. Cannot persist a financial record. |
| **Input** | `imageData`, `vehicleID` |
| **Output** | `ReceiptScan` in `.awaitingReview` |
| **Dependencies** | `ImagePreprocessing`, `TextRecognizer`, `VisionAnalysisProvider`, `FileStorage`, `FeatureGate`, `Clock` — **no financial repository** |
| **Errors** | `.ai(.structuredOutputInvalid)`, `.ai(.quotaExceeded)`, `.permission(.cameraDenied)`, `.validation(.noTextFound)` |
| **Business rules** | 1. Premium-gated. 2. Image is downscaled and **EXIF/GPS-stripped before upload** (privacy — `12 §Security`). 3. On-device OCR runs first: it reduces tokens, improves accuracy, and its text is retained for audit. 4. Every extracted field is a `FieldSuggestion` with confidence; nothing is silently trusted. 5. **The output type makes persistence impossible** (`03 §5`). |

### `ConfirmReceiptScan` ⓟ
| | |
|---|---|
| **Input** | `ConfirmedReceipt` — unconstructible without a user review pass |
| **Output** | `RecordRef` (`.fuel(id)` / `.service(id)` / `.expense(id)`) |
| **Dependencies** | `AddFuelEntry`, `AddServiceRecord`, `AddExpense`, `ReceiptScanRepository` |
| **Business rules** | 1. Writes **exactly one** record, of the kind in `ConfirmedReceipt.kind` (`03 §4.3`). 2. `source: .receiptScan(scanID)` for provenance and future de-dup. 3. Marks the scan `.confirmed`. 4. Attaches the receipt image to the created record. 5. Idempotent: confirming an already-confirmed scan returns the existing `RecordRef`. |

### `ScanDashboard` ⓟ · `AnalyzeDamage` ⓟ
Both: premium-gated, EXIF-stripped, structured-output validated, **return a result carrying a
non-optional `AIDisclaimer`**, require `DisclaimerAcknowledgement` for the current disclaimer
version, and **write no vehicle records**. `AnalyzeDamage` returns `CostEstimateRange`, never a
scalar price (`03 §6`).

### `GenerateAIInsights` ⓟ — the grounded one
| | |
|---|---|
| **Responsibility** | Produce insights that provably reference real, computed metrics |
| **Input** | `vehicleID`, `AnalyticsPeriod` |
| **Output** | `[AIInsight]` |
| **Dependencies** | `BuildAnalyticsReport`, `CalculateFuelStatistics`, `BuildAIContext`, `AIProvider`, `AIInsightRepository`, `FeatureGate`, `Clock` |
| **Business rules** | 1. Input is the **`AnalyticsReport`, not raw rows** — the AI never aggregates. 2. The prompt supplies a closed allowlist of `MetricID`s that were actually computed. 3. **Post-validation: any returned insight citing a `MetricID` not in the allowlist, or a value differing from the computed value beyond float tolerance, is DISCARDED before persistence.** This is the mechanical answer to "do not allow AI to invent missing statistics". 4. If the report has `insufficientData` for a metric, that metric is omitted from the allowlist entirely — so an insight about it cannot survive validation. 5. Cached with `validUntil`; regenerated at most once per day per vehicle, or on demand. 6. Never blocks Home rendering. |

### `BuildAIContext`
Pure-ish assembly (repositories in, value out). Detailed in `08-ai-architecture.md §4`.

---

## 9. Subscription

### `LoadProducts` · `PurchasePremium` ⓟ · `RestorePurchases` ⓟ · `RefreshEntitlement`
`PurchasePremium`: input `ProductID`; output `PurchaseOutcome` (`.success(Entitlement)` /
`.userCancelled` / `.pending`). Rules: verification via `VerificationResult` — **an unverified
transaction never grants entitlement**; `.pending` (Ask to Buy) is a first-class outcome, not an
error; the transaction is finished only after the entitlement is persisted; intro-offer eligibility
(A-22) is resolved before display, not after tap.
`RestorePurchases`: `AppStore.sync()` then re-derive from `Transaction.currentEntitlements`; returns
`.restored(Entitlement)` or `.nothingToRestore` — the latter is **not** an error.

---

## 10. Authentication

### `RestoreSession` ⓟ
Reads the Keychain token; refreshes if expired; on any failure falls back to **`.anonymous`**, never
to a blocking error screen (A-04). Runs at launch, non-blocking; the garage renders regardless.

### `SignIn` / `SignUp` / `SignInWithApple` / `SignInWithGoogle` / `SignOut` / `DeleteAccount`
`SignOut`: clears Keychain + `AuthSessionStore`, **does not delete local or iCloud data** (A-03),
and returns the app to `.anonymous`.
`DeleteAccount`: deletes the *backend account only*, requires re-authentication, and returns a
result prompting the separate, explicitly-confirmed `DeleteAllData`.

---

## 11. Data management

### `ExportVehicleHistoryPDF` ⓟ (Premium)
Input `vehicleID`, `AnalyticsPeriod`, sections. Renders via `DocumentExporting` off the main actor.
Output: a temporary-directory `URL` for the share sheet. Errors `.document(.exportFailed)`.

### `ExportDataArchive` / `ImportDataArchive` / `DeleteAllData`
Archive = JSON of all entities + the file blobs, zipped, versioned with the schema version.
`ImportDataArchive` is **additive with conflict resolution by `id`**, never destructive.
`DeleteAllData` requires typed confirmation, wipes SwiftData + file storage + pending notifications
+ the AI conversation store, and is the **only** destructive operation in the app.

---

## 12. Use-case dependency matrix (validated — no cycles)

```
CreateVehicle ─────► VehicleRepo, OdometerRepo, ReminderRepo, FileStorage, FeatureGating
AddFuelEntry ──────► FuelRepo, OdometerRepo, FileStorage, RescheduleReminders
AddServiceRecord ──► ServiceRepo, OdometerRepo, ReminderRepo, CompleteReminder, RescheduleReminders
AddExpense ────────► ExpenseRepo, OdometerRepo, FileStorage
AddDocument ───────► DocumentRepo, FileStorage, CreateReminder
CreateReminder ────► ReminderRepo, NotificationScheduling, MileageProjector
LoadHomeDashboard ─► CalculateFuelStatistics, BuildAnalyticsReport, EvaluateReminderTriggers,
                     EvaluateDocumentExpiries, AIInsightRepository, VehicleHealthScorer
BuildAnalyticsReport ► Fuel/Service/Expense/Odometer repos, CostLedger, StatisticsEngine, FeatureGate
AskAI ─────────────► AIConversationRepo, BuildAIContext, AIProvider, FeatureGate
BuildAIContext ────► BuildAnalyticsReport, CalculateFuelStatistics, EvaluateReminderTriggers, repos
GenerateAIInsights ► BuildAnalyticsReport, BuildAIContext, AIProvider, AIInsightRepo
ScanReceipt ───────► TextRecognizer, VisionAnalysisProvider, FileStorage, FeatureGate   [NO fin. repo]
ConfirmReceiptScan ► AddFuelEntry | AddServiceRecord | AddExpense
```

Use cases may compose other use cases **downward only** (`ConfirmReceiptScan → AddFuelEntry`).
A use case may never call a use case that transitively calls it. `LoadHomeDashboard` and
`BuildAIContext` are the only two composite use cases and both are leaves-upward.
