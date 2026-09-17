# 13 · Testing Architecture

**Framework: `swift-testing` (`import Testing`)** for everything new — parameterised `@Test(arguments:)`
is a direct fit for the trigger matrices below. XCTest is retained only for UI tests.

---

## 1. The pyramid, sized for a solo developer

```
                    ╱╲          UI tests (XCUITest) — ~8 critical journeys only
                   ╱──╲         (slow, brittle, expensive to maintain)
                  ╱    ╲
                 ╱      ╲       ViewModel tests — every VM's state machine, with fake use cases
                ╱────────╲
               ╱          ╲     Use-case tests — with in-memory repos + fakes
              ╱────────────╲
             ╱              ╲   Repository tests — in-memory ModelContainer
            ╱────────────────╲
           ╱                  ╲ DOMAIN tests — pure functions, no mocks, no async, microseconds
          ╱────────────────────╲  ◄── the bulk of the suite, and the bulk of the value
```

The architecture is shaped so that **the highest-risk logic sits in the cheapest tier**. Fuel
segmentation, reminder evaluation, cost aggregation, health scoring and feature gating are all pure
functions of value types. They need no container, no mocks, no async, no simulator.

---

## 2. Test doubles

| Double | Kind | Notes |
|---|---|---|
| `FixedClock` | Fake | **The most important one.** Production code never calls `Date()`, so every date-sensitive test is deterministic. |
| `SequentialIDGenerator` | Fake | Predictable UUIDs → readable assertions and golden fixtures |
| `InMemoryVehicleRepository` etc. | **Fakes, not mocks** | Real behaviour over a dictionary. Prefer these to verify-call-count mocks: they let use-case tests assert on *outcomes*. |
| `SpyNotificationScheduler` | Spy | Records `[ScheduledNotification]` — the only place call-verification is the right tool, because scheduling *is* the side effect |
| `ScriptedAIProvider` | Fake | Yields a scripted `[AIStreamEvent]` with configurable delay, mid-stream failure, and cancellation observation |
| `StubVisionAnalysisProvider` | Stub | Returns fixture `ReceiptDraft` / findings, incl. malformed output |
| `FakeSubscriptionProviding` | Fake | Any `Entitlement` + a controllable `entitlementUpdates` stream |
| `InMemoryFileStorage` | Fake | Dictionary-backed; tracks GC enqueues |
| `FakePreferences` | Fake | In-memory `PreferencesProviding` |
| `TestModelContainer` | Real | `ModelConfiguration(isStoredInMemoryOnly: true)` — used **only** for repository tests |
| `SKTestSession` + `Configuration.storekit` | Real | Subscription integration tests |

**Policy: fakes over mocks.** Verifying that `repository.insert` was called once proves nothing about
correctness. Asserting that `repo.all().count == 1` and that the stored entity has the right values
proves the behaviour and survives refactoring.

---

## 3. The required test suites (the spec's list, made concrete)

### 3.1 Fuel consumption — `FuelConsumptionCalculatorTests`

The single highest-value suite in the app.

| Test | Expectation |
|---|---|
| `emptyHistory` | `.insufficientData(fullTankCount: 0)` |
| `singleFullTank` | `.insufficientData(fullTankCount: 1)` — never 0.0 |
| `twoFullTanks` | `(volumeOfSecond / distance) × 100`; **the first entry's volume is excluded** |
| `fullPartialFull` | Segment volume = partial + closing full; opening full excluded |
| `chainedSegments_F_P_F_P_P_F` | Exactly 2 segments; the worked example in `09 §1.3` → **6.67 L/100km** |
| `weightedNotArithmeticMean` | A 50 km and a 900 km segment: result ≠ mean of the two averages |
| `leadingPartialsDiscarded` | Partials before the first full tank contribute to cost totals but not to consumption |
| `trailingOpenSegmentIgnored` | Volume after the last full tank is never attributed to a distance |
| `missedFillUpBreaksSegment` | `missedPreviousFillUp` splits, does not merge |
| `odometerRegressionDiscarded` | Segment dropped + `DataQualityIssue.odometerRegression` raised |
| `zeroDistanceDiscarded` | Duplicate odometer → dropped, no division by zero |
| `implausibleConsumptionDiscarded` | 200 L/100km → dropped with an issue |
| `sortsByOdometerNotDate` | Two same-day fill-ups ordered by odometer |
| `averagePriceIsVolumeWeighted` | 60 L @ €1.60 + 5 L @ €2.10 → **€1.638**, not €1.85 |
| `electricVehicleUsesKWh` | Unit carried through as kWh/100km |
| `monthlyAttributedToClosingEntry` | `09 §1.6` policy |
| `mixedCurrencyDoesNotAffectConsumption` | Volume/distance unaffected; cost bucketed per currency |

### 3.2 Cost per km — `StatisticsEngineTests`

`costPerKm` uses odometer readings (not fuel entries) for distance; `.insufficientData` when
`distanceDriven <= 0` or fewer than 2 readings; cost-of-ownership includes purchase price and
**excludes depreciation**; mixed currencies are grouped and never summed; monthly buckets are dense
and mark empty months as `isEmpty` rather than `€0`.

### 3.3 Reminders — `ReminderEvaluatorTests` (parameterised)

```swift
@Test(arguments: ReminderTriggerCase.allCases)
func evaluatesTrigger(_ c: ReminderTriggerCase) { … }
```

| Group | Cases |
|---|---|
| **Date trigger** | before lead time → `.upcoming(nil)`; inside lead time → `.upcoming(days)`; on due date → `.due`; after → `.overdue(days)` |
| **Mileage trigger** | below lead distance → upcoming; at `dueOdometer` → `.due`; beyond → `.overdue(distance)`; **no odometer reading → `.indeterminate`, never `.overdue`** |
| **`.whicheverFirst`** | date due first → status + reason `.date`; mileage due first → reason `.mileage`; **both overdue → `.overdue` with the earlier-occurring reason**; one overdue + one upcoming → `.overdue`; neither → `.upcoming` with the nearer of the two |
| **Recurrence** | `.everyMonths` rolls the due date; `.everyDistance` **rebases `baselineOdometer` to the completion odometer** (drives the screenshot-15 progress bar); `.both` rolls both; `.seasonal(Apr/Nov)` wraps to the next listed month, and across the year boundary; `.none` deactivates |
| **Progress** | `ReminderProgress.fraction` for the screenshot's `82,120 → 82,540 / 15,000 km` case; clamped to `0...1`; `nil` for date-only triggers |
| **Inactive** | excluded from every evaluation |

### 3.4 Premium restrictions — `FeatureGatingTests`

Full matrix: every `PremiumFeature` × `.free`/`.premium` × quota exhausted/available ×
anonymous/authenticated. Plus: free tier with 0 vehicles may create one; with 1 vehicle gets
`.locked(.requiresPremium)`; `clampedPeriod(.allTime)` returns 12 months for free and `.allTime` for
premium; expired entitlement within the 7-day grace window still grants access; beyond it does not.
**No StoreKit is involved** — `FeatureGating` is a pure function.

### 3.5 First vehicle becomes default — `CreateVehicleTests`

`firstVehicleBecomesDefault`; `secondVehicleDoesNotBecomeDefault`;
`freeTierSecondVehicleThrowsVehicleLimitReached`; `defaultVehicleIsSelectedInStore`;
`deletingDefaultPromotesAnother`; `deletingLastVehicleClearsSelection`;
`exactlyOneDefaultInvariantHoldsAfterConcurrentCreates`; `initialOdometerReadingIsWritten`;
`standardRemindersSeededInactive`.

### 3.6 Receipt confirmation — `ReceiptScanFlowTests`

The critical safety suite.

| Test | Expectation |
|---|---|
| `scanReceiptNeverPersistsFinancialRecords` | After `ScanReceipt`, all three financial fakes have **zero** rows |
| `scanReceiptStopsAtAwaitingReview` | Terminal state is `.awaitingReview` |
| `confirmedReceiptCannotBeBuiltFromUnreviewedDraft` | `ConfirmedReceipt.init?` returns `nil` when a required field is unaccepted |
| `confirmCreatesExactlyOneRecord` | For each `RecordKind`: exactly one row, in exactly one repository |
| `confirmIsIdempotent` | Confirming twice returns the same `RecordRef`, creates no duplicate |
| `discardLeavesNoTrace` | No financial rows; the image is enqueued for GC |
| `failedAnalysisLeavesNoDraft` | `.structuredOutputInvalid` → no partially-populated draft is offered |
| `userEditsOverrideAIValues` | `wasEditedByUser` values survive confirmation |
| `sourceIsReceiptScan` | Created record carries `.receiptScan(scanID)` provenance |

Plus a **compile-time** assertion in the architecture suite: `ScanReceipt`'s stored properties
include no `FuelRepository`/`ServiceRepository`/`ExpenseRepository`.

### 3.7 Document expiration — `DocumentExpiryEvaluatorTests`

`nil` expiration → `.noExpiry` (never `.expired`); today → `.expiringSoon(0)`; within lead window →
`.expiringSoon(n)`; past → `.expired(n)`; **timezone boundary** (23:59 CET vs UTC) resolves via the
injected calendar; escalation produces 4 notifications at 30/14/7/1 days; deleting the document
cancels them and removes the linked reminder.

### 3.8 Analytics — `AnalyticsReportTests` + `CostLedgerTests`

`CostLedger` categorisation table (`03 §4.2`) exhaustively; **no double counting**: fuel + service +
expense produce exactly `n` entries with unique IDs; a manual `.fuel` expense contributes to
`AnalyticsReport` but **not** to `FuelStatistics`; `CostEntry` set-deduplication; period boundaries
inclusive/exclusive; `metricValues` contains only metrics with real data (feeding `08 §5.3`).

### 3.9 Grounding — `GenerateAIInsightsTests`

`insightCitingUnknownMetricIsDiscarded`; `insightWithWrongValueIsDiscarded`;
`insightWithNoSupportingMetricsIsDiscarded`; `insufficientDataMetricsAreNotInAllowlist`;
`validInsightIsPersisted`; `rejectionsAreReportedToTelemetry`.

### 3.10 Navigation — `RouteGuardTests` + `DeepLinkParserTests`

Every URL in `06 §1.4` round-trips; unknown URLs return `nil` (no crash); an anonymous user hitting
`.aiChat` gets `.present(.authentication)` with the destination stored and replayed; a free user
hitting `.camera(.receipt)` gets `.present(.paywall(.feature(.receiptScan)))`; onboarding
incomplete blocks everything; restoring into a now-locked route lands on the paywall;
`AppDestination` `Codable` round-trip.

### 3.11 Sync — `SyncStatusMonitorTests` + `CloudKitSchemaTests`

`CKContainer` events map to the right `SyncState`; `SchemaCloudKitCompatibilityTests` asserts by
reflection that every `@Model` property is optional-or-defaulted, no `.unique`, all relationships
optional with inverses, no `.deny` rules (`07 §1.2`). This test is what prevents shipping a build
where mirroring silently never initialises.

### 3.12 Streaming — `AskAITests`

User message persisted **before** the request; deltas accumulate in order; **no per-delta
persistence** (assert the repository write count == 2 for a full turn); cancellation persists a
partial with `isPartial == true`; mid-stream error persists text + `failure`; `.quotaExceeded` short-
circuits with zero provider calls when the gate denies; `MockAIProvider` cancellation is observed.

### 3.13 Architecture — `ArchitectureRuleTests`

The lint suite from `01 §3.3`: Domain imports only `Foundation`; no `View` imports SwiftData/StoreKit/
CloudKit; no ViewModel holds a repository; `Features/A` never references `Features/B`; no
`@unchecked Sendable` anywhere; no `DispatchQueue` outside `Core/Infrastructure`.

---

## 4. ViewModel testing

ViewModels are `@MainActor @Observable` with fake use cases. Tests assert on the **`ViewState`
sequence**, which is where the real bugs live:

```swift
@MainActor @Test
func showsPaywallWhenFreeUserScansReceipt() async {
    let vm = ReceiptScanViewModel(scan: .failing(with: .subscription(.requiresPremium)), router: spy)
    await vm.capture(imageData)
    #expect(spy.presentedModals == [.paywall(.feature(.receiptScan))])
    #expect(vm.state == .idle)                     // NOT .failed — a paywall is not an error
}
```

Covered per ViewModel: initial `.loading` → `.loaded`; empty state distinct from loading; error
mapping to the right `ErrorPresentation.style`; cancellation on teardown; change-feed refresh; no
duplicate concurrent loads.

## 5. UI tests — the eight that earn their keep

1. Onboarding → add first vehicle → Home renders with that vehicle
2. Add fuel → appears in Fuel history → consumption updates on the second full tank
3. Add service with two items → both matching reminders auto-complete
4. Create a mileage reminder → progress bar reflects the current odometer
5. Free user taps Scan Receipt → paywall appears (not the camera)
6. Purchase (StoreKit test session) → paywall dismisses → the originally-tapped screen opens
7. Add a document with an expiry → it appears in Documents and in Home *Upcoming*
8. AI chat: send → stream renders → cancel mid-stream → partial message persists across relaunch

## 6. CI

Per PR: build + unit tests + architecture-lint tests (fast, no simulator boot for the domain tier).
Nightly: UI tests, StoreKit integration, and a CloudKit-schema compatibility run.

**Coverage targets, weighted by tier:** Domain **≥ 95%** (it is pure; there is no excuse),
Application/use cases ≥ 85%, ViewModels ≥ 70%, Infrastructure ≥ 40% (thin adapters — integration-
tested, not unit-tested), Views 0% (not tested by unit tests, by design).
