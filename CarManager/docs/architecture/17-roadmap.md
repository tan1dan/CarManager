# 17 · Implementation Roadmap

Ordered by **dependency**, not by visible progress. Each phase lists models, protocols, use cases,
services, repositories, tests and what it depends on. Phase estimates assume one developer.

---

## Phase 1 — Foundation *(no user-visible output; do not skip)*

| | |
|---|---|
| **Models** | `Identifiers`, `Money`, `CurrencyCode`, `Distance`, `Volume`, `Odometer`, `DateRange`, `AnalyticsPeriod`, `VIN`, `LicensePlate`, `RecordSource`, `FileRef`, `ViewState`, `Metric<T>`, the full `DomainError` tree |
| **Protocols** | `ClockProviding`, `IDGenerating`, `PreferencesProviding`, `TelemetryProviding`, `ConnectivityProviding`, `Repository` base |
| **Use cases** | — |
| **Services** | `SystemClock`, `UUIDGenerator`, `UserPreferencesStore`, `NetworkMonitor`, `TelemetryService`, `KeychainStore` |
| **Repositories** | — |
| **Infrastructure** | `PersistenceStack` (ModelContainer + CloudKit config), `PersistenceActor`, `SchemaV1`, empty `MigrationPlan`, `ChangeFeed` |
| **Application** | `AppDependencies` (+ `.live/.preview/.testing`), `AppEnvironment`, `AppDestination`/`AppRoute`/`ModalRoute`/`FullScreenRoute`, `AppRouter`, `TabRouter`, `RouteGuard` (stubbed decisions), `DeepLinkParser`, `AppLifecycleCoordinator` |
| **Tests** | `Money`/`Distance`/`Volume` arithmetic and rounding · `AnalyticsPeriod.range` across DST and year boundaries · `AppDestination` `Codable` round-trip · `DeepLinkParser` for every URL in `06 §1.4` · **`ArchitectureRuleTests`** (the lint suite — write it now, it will fail usefully all project long) |
| **Depends on** | nothing |
| **Exit criteria** | The app launches to a black screen with a working container, a router that can navigate to nothing, and a green architecture-lint suite. |

> Writing `ArchitectureRuleTests` and `FixedClock` in Phase 1 is the highest-leverage hour in the
> project. Both get harder to introduce with every subsequent phase.

---

## Phase 2 — Authentication & Onboarding

| | |
|---|---|
| **Models** | `UserProfile`, `AuthSession`, `AuthCredentials`, `AuthRegistration`, `AuthState`, `AuthenticationError`, `OnboardingState` |
| **Protocols** | `AuthProviding` |
| **Use cases** | `RestoreSession`, `SignIn`, `SignUp`, `SignInWithApple`, `SignInWithGoogle`, `SignOut`, `DeleteAccount`, `RequestPasswordReset` |
| **Services** | `BackendAuthService` (actor, with refresh coalescing), `AppleAuthProvider`, `GoogleAuthProvider` (ASWebAuthenticationSession + PKCE), `EmailAuthProvider` |
| **Repositories** | — |
| **State** | `AuthSessionStore` |
| **Features** | `Onboarding`, `Authentication` |
| **Tests** | Restore → `.anonymous` on every failure path · token-refresh coalescing under concurrent 401s · sign-out does **not** touch local data (A-03) · `RouteGuard` auth redirect + `pendingDestination` replay |
| **Depends on** | Phase 1 |
| **Note** | Ship `.anonymous` working end-to-end (A-04) **before** any sign-in UI. Onboarding must be able to reach Phase 3 without an account. |

---

## Phase 3 — Vehicle, Garage, Home *(the first real product)*

| | |
|---|---|
| **Models** | `Vehicle`, `VehicleSummary`, `VehicleDraft`, `FuelType`, `OwnershipScope`, **`OdometerReading`**, `OdometerSource`, `VehicleHealth`, `HealthFactor`, `UpcomingEvent`, `ActivityItem`, `HomeDashboard` |
| **Protocols** | `VehicleRepository`, `OdometerRepository`, `FileStorage` |
| **Use cases** | `CreateVehicle`, `UpdateVehicle`, `DeleteVehicle`, `SetDefaultVehicle`, `LoadGarage`, `LoadVehicleDetail`, `UpdateOdometer`, `LoadHomeDashboard` (initially thin), `LoadRecentActivity`, `LoadUserStatistics` |
| **Services** | `FileStorageActor`, `FileLocationResolver`, `ThumbnailGenerator` |
| **Repositories** | Vehicle, Odometer (`SDVehicle`, `SDOdometerReading` + mappers) |
| **Domain services** | `VehicleValidator`, `VehicleHealthScorer` (with only the factors available so far) |
| **State** | `SelectedVehicleStore` |
| **Features** | `Garage`, `VehicleDetail`, `VehicleEditor`, `Home` (partial), `QuickLog` (shell) |
| **Tests** | **`CreateVehicleTests`** (first-vehicle-becomes-default, exactly-one-default invariant, initial odometer reading, seeded inactive reminders) · delete promotes another default · `SelectedVehicleStore` resolution order · odometer regression warning · `VehicleHealthScorer` indeterminate for sparse data |
| **Depends on** | Phase 1 |
| **Exit criteria** | Add a vehicle, see it on Home and in Garage, switch between two vehicles, edit and delete. |

---

## Phase 4 — Fuel, Service, Expenses *(the data core)*

| | |
|---|---|
| **Models** | `FuelEntry`, `FuelSegment`, `FuelStatistics`, `ConsumptionTrend`, `DataQualityIssue`, `ServiceRecord`, `ServiceItem`, `ServiceType`, `ServiceNature`, `PartUsage`, `Expense`, `ExpenseCategory`, `CostEntry`, `CostOrigin`, `PaymentMethodTag` |
| **Protocols** | `FuelRepository`, `ServiceRepository`, `ExpenseRepository` |
| **Use cases** | `AddFuelEntry`, `UpdateFuelEntry`, `DeleteFuelEntry`, `LoadFuelHistory`, **`CalculateFuelStatistics`**, `AddServiceRecord`, `UpdateServiceRecord`, `DeleteServiceRecord`, `QueryServiceHistory`, `AddExpense`, `UpdateExpense`, `DeleteExpense`, `LoadExpenses` |
| **Domain services** | **`FuelConsumptionCalculator`**, **`CostLedger`**, `FuelEntryValidator`, `ServiceRecordValidator` |
| **Repositories** | Fuel, Service, Expense (+ `#Index` per `07 §1.3`) |
| **Features** | `Fuel`, `Service`, `Expenses`, `QuickLog` (complete) |
| **Tests** | **`FuelConsumptionCalculatorTests` — all 17 cases in `13 §3.1`, written FIRST** · `CostLedgerTests` categorisation + no-double-count · volume-weighted average price · odometer readings written and cleaned up on every add/update/delete · multi-item service record |
| **Depends on** | Phase 3 |
| **Exit criteria** | Log a fill-up, see a correct L/100km after the second full tank, log a service, log an expense, and see all three in one recent-activity feed. |

> **Write `FuelConsumptionCalculator` test-first.** It is the most-used, most-wrong-in-competitors,
> and cheapest-to-test piece of logic in the product.

---

## Phase 5 — Reminders, Notifications, Documents

| | |
|---|---|
| **Models** | `Reminder`, `ReminderKind`, `ReminderTrigger`, `DateTrigger`, `MileageTrigger`, `RecurrenceRule`, `ReminderLeadTime`, `ReminderStatus`, `ReminderProgress`, `ReminderEvaluation`, `DocumentMetadata`, `DocumentType`, `DocumentExpiry`, `AppNotification`, `ScheduledNotification` |
| **Protocols** | `ReminderRepository`, `DocumentRepository`, `NotificationInboxRepository`, `NotificationScheduling` |
| **Use cases** | `CreateReminder`, `UpdateReminder`, `DeleteReminder`, **`EvaluateReminderTriggers`**, `CompleteReminder`, `RescheduleRemindersForVehicle`, `RescheduleAllReminders`, `AddDocument`, `DeleteDocument`, `QueryDocuments`, `OpenDocumentFile`, `EvaluateDocumentExpiries`, `LoadNotificationInbox`, `MarkNotificationRead`, `ClearNotifications` |
| **Domain services** | **`ReminderEvaluator`**, `RecurrenceCalculator`, `MileageProjector`, `NotificationPlanner`, `DocumentExpiryEvaluator` |
| **Services** | `UNNotificationScheduler`, `NotificationContentBuilder`, `NotificationCategoryRegistry`, `FileSyncCoordinator`, `FileGarbageCollector` |
| **Features** | `Reminders`, `Documents`, `Alerts` |
| **Tests** | **`ReminderEvaluatorTests`** — the full parameterised matrix in `13 §3.3`, including every `.whicheverFirst` combination and `.seasonal` year-wrap · `.everyDistance` rebases the baseline on completion · `SpyNotificationScheduler`: ≤3 occurrences scheduled, identifiers deterministic, rescheduling idempotent · `DocumentExpiryEvaluatorTests` incl. timezone boundary · GC grace window |
| **Depends on** | Phase 3 (odometer), Phase 4 (service auto-completes reminders) |
| **Exit criteria** | A mileage reminder shows a correct progress bar, a service record auto-completes it, and a document expiry produces both an OS notification and an inbox row. |

---

## Phase 6 — Analytics

| | |
|---|---|
| **Models** | `AnalyticsReport`, `PeriodTotals`, `CategoryBreakdown`, `MonthlyBucket`, `CostOfOwnership`, `MetricID`, `UserStatistics` |
| **Protocols** | — (no new ones; this phase is pure domain + one use case) |
| **Use cases** | `BuildAnalyticsReport`, `LoadUserStatistics` (completed) |
| **Domain services** | **`StatisticsEngine`** |
| **Services** | in-memory `AnalyticsCache` keyed by `(vehicle, period, dataVersion)` |
| **Features** | `Analytics`; Home stat tiles and Expenses overview completed |
| **Tests** | `AnalyticsReportTests` (`13 §3.2`, `13 §3.8`) · dense monthly buckets with `isEmpty` months · mixed-currency grouping never summing · `costPerKm` from odometer readings, `.insufficientData` guards · determinism: identical inputs ⇒ byte-identical report |
| **Depends on** | Phase 4 (`CostLedger`, `FuelStatistics`), Phase 3 (odometer) |
| **Exit criteria** | Screenshot 13 renders from real data, and Home's `This month €342` matches the Analytics figure exactly. |

---

## Phase 7 — AI

| | |
|---|---|
| **Models** | `AIConversation`, `AIMessage`, `AIInsight`, `MetricReference`, `AIVehicleContext`, `DataCoverage`, `ReceiptScan`, `ReceiptDraft`, `FieldSuggestion`, `ConfirmedReceipt`, `ReceiptScanState`, `DashboardScan`, `DashboardFinding`, `DamageAnalysis`, `DamageFinding`, `CostEstimateRange`, **`AIDisclaimer`**, `AIError` |
| **Protocols** | `AIProvider`, `VisionAnalysisProvider`, `TextRecognizer`, `ImagePreprocessing`, `AIConversationRepository`, `AIInsightRepository`, `ScanRepository` |
| **Use cases** | `AskAI`, `LoadConversation`, `ListConversations`, `DeleteConversation`, **`BuildAIContext`**, `ScanReceipt`, **`ConfirmReceiptScan`**, `ScanDashboard`, `AnalyzeDamage`, **`GenerateAIInsights`**, `RecognizeLicensePlate` |
| **Services** | `BackendAIProvider` + `SSEDecoder` + `StructuredOutputDecoder`, `MockAIProvider`, `VisionTextRecognizer`, `ImagePreprocessor` (**EXIF/GPS stripping**), `PlateRecognizer` |
| **Features** | `AIHub`, `AIChat`, `ReceiptScan`, `DashboardScan`, `DamageAnalysis` |
| **Tests** | `AskAITests` (`13 §3.12`): user message persisted first, **exactly 2 repository writes per turn**, cancellation persists a partial, gate short-circuits with zero provider calls · **`ReceiptScanFlowTests`** (`13 §3.6`) incl. the compile-time assertion that `ScanReceipt` holds no financial repository · `GenerateAIInsightsTests` grounding rejections (`13 §3.9`) · `BuildAIContext` golden fixture + **assert VIN/plate/notes are absent** |
| **Depends on** | Phase 6 (insights consume `AnalyticsReport`), Phase 4 (context needs fuel/service/expenses), **backend AI proxy available** |
| **Exit criteria** | Streaming chat that answers "how much did I spend this month?" with the *same* number Analytics shows; a receipt scan that reaches review and cannot save without confirmation. |

> Build `MockAIProvider` first and develop the entire AI UI against it. The backend can land in
> parallel; nothing in Phases 1–6 depends on it.

---

## Phase 8 — StoreKit / Premium

| | |
|---|---|
| **Models** | `Entitlement`, `EntitlementSource`, `SubscriptionTier`, `PremiumFeature`, `FeatureAccess`, `LockReason`, `SubscriptionProduct`, `ProductID`, `IntroOffer`, `PurchaseOutcome`, `RestoreOutcome`, `AIUsageSnapshot`, `PaywallContext`, `SubscriptionError` |
| **Protocols** | `SubscriptionProviding` |
| **Use cases** | `LoadProducts`, `PurchasePremium`, `RestorePurchases`, `RefreshEntitlement` |
| **Domain services** | **`FeatureGating`** (pure) |
| **Services** | `StoreKitSubscriptionService` (actor), `ProductCatalog`, `ReceiptEntitlementMapper` |
| **State** | `EntitlementStore`, `FeatureGate` |
| **Features** | `Premium` (paywall), `Profile` |
| **Wiring** | Turn on the real `RouteGuard` premium decisions; add `requirePremium` to gated use cases |
| **Tests** | **`FeatureGatingTests`** — the full matrix (`13 §3.4`), no StoreKit involved · `SKTestSession`: purchase / renew / expire / refund / revoke / family-shared / Ask-to-Buy pending · offline grace window · paywall → purchase → `pendingDestination` replay · `.nothingToRestore` is neutral |
| **Depends on** | Phase 7 (there must be something worth gating), Phase 2 (account linkage) |
| **Note** | Gating is added **last among features and first among release blockers.** Building it earlier means every feature is developed behind a lock, which slows everything down. |

---

## Phase 9 — Cloud synchronization

| | |
|---|---|
| **Models** | `SyncState`, `SyncError`, `CloudUnavailableReason`, `FileAvailability` |
| **Protocols** | `SyncStatusProviding` |
| **Use cases** | `ExportDataArchive`, `ImportDataArchive`, `DeleteAllData`, `ExportVehicleHistoryPDF` |
| **Services** | `CloudKitConfiguration`, `SyncStatusMonitor`, `FileSyncCoordinator` (completed), `PDFExporter`, `ArchiveExporter` |
| **State** | `SyncStatusStore` |
| **Features** | `Settings` (Data section) completed |
| **Tests** | **`CloudKitSchemaTests`** — reflection-based compliance with all five constraints in `07 §1.2` · `SyncStatusMonitor` event mapping · remote-change → `ChangeFeed` → ViewModel refresh · `SelectedVehicleStore` re-resolves when the selected vehicle is deleted remotely · file download progress and checksum verification · archive round-trip |
| **Depends on** | all data phases |
| **Note** | The CloudKit **entitlement and container are configured in Phase 1**; only *verification, status
surfacing and file sync* land here. Turning mirroring on late would risk a schema change after ship. Deploy the CloudKit schema dev→prod as a **release-checklist item**. |

---

## Phase 10 — Testing & production hardening

| | |
|---|---|
| **Work** | Fill coverage to the `13 §6` targets · the 8 UI journeys · localisation pass (every `LocalizedKey` resolved, RTL check) · accessibility (Dynamic Type, VoiceOver labels on every stat tile and chart) · performance profiling with a seeded 5-year, 3-vehicle garage · memory + leak checks on `AsyncStream` teardown · `PrivacyInfo.xcprivacy` · App Store metadata, subscription disclosure copy, in-app account deletion (`12 §10`) · crash + telemetry dashboards · **extract `Domain` and `AICore` into SPM packages** now that the boundaries have stopped moving |
| **Tests** | Everything above; CI: unit + lint per PR, UI + StoreKit + CloudKit-schema nightly |
| **Depends on** | Phases 1–9 |

---

## Dependency graph

```
P1 Foundation
 ├─► P2 Auth/Onboarding ──────────────┐
 └─► P3 Vehicle/Garage/Home           │
        └─► P4 Fuel/Service/Expenses  │
             ├─► P5 Reminders/Docs    │
             └─► P6 Analytics         │
                    └─► P7 AI ◄───────┘   (also needs: backend AI proxy)
                         └─► P8 Premium
                              └─► P9 Sync
                                   └─► P10 Hardening
```

**Critical path:** P1 → P3 → P4 → P6 → P7 → P8.
**Parallelisable:** P2 can run alongside P3 (the app works anonymously). P5 can run alongside P6.
The backend AI proxy can be built at any time before P7 — develop against `MockAIProvider` until it
exists.

---

## What must be right the first time (rework here is expensive)

| Decision | Why it is hard to change later |
|---|---|
| `@Model` ↔ struct boundary (P1/P3) | Retro-fitting means touching every repository, use case and ViewModel |
| `OdometerReading` as an entity (P3) | Adding it later requires a data migration that reconstructs history from three tables |
| CloudKit-compatible schema (P1) | A post-launch schema change means a migration **and** a CloudKit prod schema deployment |
| `CostEntry` projection instead of a shared table (P4) | Reversing it means a data migration and re-deriving analytics |
| `ConfirmedReceipt` unconstructible-without-review (P7) | This is a correctness guarantee, not a UI nicety — bolting it on later means auditing every call site |
| `FixedClock` + no `Date()` in production code (P1) | Every date-dependent test written before this becomes flaky and needs rewriting |
