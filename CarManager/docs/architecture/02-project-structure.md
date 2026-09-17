# 02 · Project Structure & Feature Structure

Single Xcode target for MVP (`CarManager`), plus `CarManagerTests` and `CarManagerUITests`.
Folder discipline + the architecture lint tests (`01 §3.3`) enforce boundaries. SPM extraction is
scheduled for Phase 10, not Phase 1 — see ADR-001.

---

## 1. Top-level tree

```
CarManager/
├── App/                        composition root — the ONLY place that knows everything
├── Core/
│   ├── Domain/                 pure Swift. imports Foundation. the heart of the app
│   ├── Application/            use cases, routers, global stores, feature gate
│   ├── Data/                   repository implementations + SwiftData models + mappers
│   ├── Infrastructure/         every Apple/3rd-party boundary adapter
│   └── DesignKit/             reusable view primitives (NOT part of this deliverable)
├── Features/                   one folder per screen-cluster; mutually isolated
├── Resources/
└── SupportingFiles/
```

---

## 2. `App/` — composition root

| Responsibility | Build the object graph, own the root scene, wire app lifecycle |
|---|---|
| **May depend on** | everything |
| **Depended on by** | nothing |

```
App/
├── CarManagerApp.swift              @main. builds AppDependencies. one Scene.
├── RootView.swift                   switches on AuthState/OnboardingState → root destination
├── AppDependencies.swift            the container (struct, Sendable). .live / .preview / .testing
├── AppDependencies+Live.swift       live factory: builds PersistenceStack, actors, providers
├── AppEnvironment.swift             EnvironmentKey/EnvironmentValues plumbing
├── AppLifecycleCoordinator.swift    launch/foreground tasks: session restore, entitlement refresh,
│                                    reminder re-evaluation, notification rescheduling, file GC
├── DeepLinkHandler.swift            URL / UNNotificationResponse → AppDestination
└── Launch/
    ├── PersistenceStack.swift       ModelContainer construction + CloudKit config + migrations
    └── BackgroundTasks.swift        BGAppRefreshTask registration (reminder re-projection)
```

**Important:** `AppDependencies` is constructed **once**, in `CarManagerApp.init()`. Nothing else in
the app calls `.live`. There are no singletons; `AppDependencies` is passed down explicitly.

---

## 3. `Core/Domain/` — the heart

| Responsibility | Entities, value objects, pure business rules, protocol definitions, error taxonomy |
|---|---|
| **May import** | `Foundation` |
| **Must not import** | everything else, including `Observation` |
| **Depended on by** | Application, Data, Infrastructure, Presentation |

```
Core/Domain/
├── Primitives/
│   ├── Identifiers.swift          VehicleID, FuelEntryID, ServiceRecordID, … (UUID wrappers)
│   ├── Money.swift                Money(amount: Decimal, currency: CurrencyCode) + arithmetic
│   ├── CurrencyCode.swift
│   ├── Distance.swift             canonical kilometres; `.miles` conversion is presentation-only
│   ├── Volume.swift               canonical litres
│   ├── Odometer.swift             Distance newtype with monotonicity semantics
│   ├── DateRange.swift            + AnalyticsPeriod → DateRange resolution (calendar-aware)
│   ├── VIN.swift                  validated 17-char value object (ISO 3779 checksum)
│   ├── LicensePlate.swift         normalised, region-tagged
│   └── RecordSource.swift         .manual | .receiptScan | .imported | .automatic(String)
├── Entities/
│   ├── Vehicle.swift
│   ├── OdometerReading.swift
│   ├── FuelEntry.swift
│   ├── ServiceRecord.swift        + ServiceItem
│   ├── Expense.swift
│   ├── Reminder.swift             + ReminderTrigger, RecurrenceRule, ReminderStatus
│   ├── DocumentMetadata.swift
│   ├── AppNotification.swift      the in-app inbox item (≠ UNNotificationRequest)
│   ├── AIConversation.swift       + AIMessage, AIMessageRole
│   ├── AIInsight.swift            + MetricReference (the anti-hallucination allowlist)
│   ├── ReceiptScan.swift          + ReceiptDraft, ScanConfidence
│   ├── DashboardScan.swift        + DashboardFinding, Severity, DrivingSafety
│   ├── DamageAnalysis.swift       + DamageFinding, CostEstimateRange
│   ├── UserProfile.swift
│   └── Entitlement.swift          + PremiumFeature, FeatureAccess
├── ValueObjects/
│   ├── CostEntry.swift            the ledger projection type
│   ├── FuelSegment.swift          a closed full-to-full interval
│   ├── FuelStatistics.swift
│   ├── AnalyticsReport.swift      + CategoryBreakdown, MonthlySeries, CostOfOwnership
│   ├── VehicleHealth.swift        + HealthFactor
│   ├── ReminderProgress.swift
│   ├── UpcomingEvent.swift        unified reminder+document-expiry feed item
│   ├── ActivityItem.swift         unified recent-activity feed item
│   └── AIVehicleContext.swift     the bounded AI context snapshot
├── Services/                      PURE domain services (no I/O, no async)
│   ├── FuelConsumptionCalculator.swift
│   ├── CostLedger.swift
│   ├── StatisticsEngine.swift
│   ├── ReminderEvaluator.swift
│   ├── RecurrenceCalculator.swift
│   ├── MileageProjector.swift
│   ├── VehicleHealthScorer.swift
│   ├── DocumentExpiryEvaluator.swift
│   └── FeatureGating.swift        pure entitlement→access function
├── Repositories/                  PROTOCOLS ONLY
│   ├── VehicleRepository.swift
│   ├── FuelRepository.swift
│   ├── ServiceRepository.swift
│   ├── ExpenseRepository.swift
│   ├── OdometerRepository.swift
│   ├── ReminderRepository.swift
│   ├── DocumentRepository.swift
│   ├── AIConversationRepository.swift
│   ├── AIInsightRepository.swift
│   └── NotificationInboxRepository.swift
├── Ports/                         PROTOCOLS for outbound infrastructure
│   ├── AIProvider.swift
│   ├── VisionAnalysisProvider.swift
│   ├── TextRecognizer.swift
│   ├── FileStorage.swift
│   ├── NotificationScheduling.swift
│   ├── AuthProviding.swift
│   ├── SubscriptionProviding.swift
│   ├── DocumentExporting.swift
│   ├── SyncStatusProviding.swift
│   ├── PreferencesProviding.swift
│   ├── ConnectivityProviding.swift
│   ├── ClockProviding.swift       ← injected clock. never call Date() in domain/use cases
│   └── TelemetryProviding.swift
└── Errors/
    ├── DomainError.swift          the umbrella
    ├── ValidationError.swift
    ├── PersistenceError.swift
    ├── AIError.swift
    ├── SubscriptionError.swift
    ├── SyncError.swift
    ├── DocumentError.swift
    ├── AuthenticationError.swift
    └── PermissionError.swift
```

---

## 4. `Core/Application/` — orchestration

| Responsibility | Use cases (transactions across repositories), navigation state, global app stores, gating |
|---|---|
| **May import** | `Foundation`, `Observation` |
| **Must not import** | SwiftUI, SwiftData, StoreKit, UserNotifications, Vision |

```
Core/Application/
├── UseCases/
│   ├── Vehicle/          CreateVehicle, UpdateVehicle, DeleteVehicle, SetDefaultVehicle,
│   │                     LoadGarage, UpdateOdometer, RecognizeLicensePlate
│   ├── Fuel/             AddFuelEntry, UpdateFuelEntry, DeleteFuelEntry,
│   │                     LoadFuelHistory, CalculateFuelStatistics
│   ├── Service/          AddServiceRecord, UpdateServiceRecord, DeleteServiceRecord,
│   │                     QueryServiceHistory
│   ├── Expense/          AddExpense, UpdateExpense, DeleteExpense, LoadExpenses
│   ├── Reminder/         CreateReminder, UpdateReminder, DeleteReminder,
│   │                     EvaluateReminderTriggers, CompleteReminder, RescheduleAllReminders
│   ├── Document/         AddDocument, DeleteDocument, QueryDocuments, OpenDocumentFile,
│   │                     EvaluateDocumentExpiries
│   ├── Home/             LoadHomeDashboard
│   ├── Analytics/        BuildAnalyticsReport, LoadUserStatistics
│   ├── AI/               AskAI, LoadConversation, ListConversations, DeleteConversation,
│   │                     ScanReceipt, ConfirmReceiptScan, ScanDashboard, AnalyzeDamage,
│   │                     GenerateAIInsights, BuildAIContext
│   ├── Subscription/     LoadProducts, PurchasePremium, RestorePurchases, RefreshEntitlement
│   ├── Auth/             RestoreSession, SignIn, SignUp, SignInWithApple, SignInWithGoogle,
│   │                     SignOut, DeleteAccount
│   ├── Notification/     LoadNotificationInbox, MarkNotificationRead, ClearNotifications
│   └── Data/             ExportVehicleHistoryPDF, ExportDataArchive, ImportDataArchive,
│                         DeleteAllData
├── State/
│   ├── SelectedVehicleStore.swift   @MainActor @Observable — the ActiveVehicle concept
│   ├── AuthSessionStore.swift       @MainActor @Observable
│   ├── EntitlementStore.swift       @MainActor @Observable — the ONLY StoreKit-facing state
│   ├── SyncStatusStore.swift        @MainActor @Observable
│   ├── ConnectivityStore.swift      @MainActor @Observable
│   └── OnboardingState.swift        value type persisted in preferences
├── Navigation/
│   ├── AppDestination.swift         the whole typed route universe (Codable)
│   ├── AppRouter.swift              @MainActor @Observable — tabs, modals, guards
│   ├── TabRouter.swift              one stack per tab
│   ├── RouteGuard.swift             auth + premium interception
│   └── DeepLinkParser.swift         URL/notification payload → AppDestination
├── Gating/
│   └── FeatureGate.swift            @MainActor @Observable façade over pure FeatureGating
└── Support/
    ├── UseCaseProtocols.swift       (only where a fake is needed for VM tests)
    └── ViewState.swift              .idle/.loading/.loaded/.failed — shared VM state enum
```

**Note on `ViewState`:** it lives in Application, not Presentation, so ViewModels (Presentation) and
their tests share it without Presentation types leaking down. It carries no SwiftUI types.

---

## 5. `Core/Data/` — persistence & repositories

| Responsibility | SwiftData schema, the persistence actor, repository implementations, mappers |
|---|---|
| **May import** | `Foundation`, `SwiftData`, `CloudKit` |
| **Must not import** | SwiftUI, Application, Features |

```
Core/Data/
├── Persistence/
│   ├── PersistenceActor.swift        @ModelActor. the single writer. all SwiftData lives here
│   ├── SchemaV1.swift                VersionedSchema
│   ├── MigrationPlan.swift           SchemaMigrationPlan (empty for V1, exists from day one)
│   └── ChangeFeed.swift              didSave / remote-change → AsyncStream<EntityChange>
├── Models/                           @Model classes. CloudKit-compatible (all optional/defaulted)
│   ├── SDVehicle.swift  SDOdometerReading.swift  SDFuelEntry.swift  SDServiceRecord.swift
│   ├── SDExpense.swift  SDReminder.swift  SDDocumentMetadata.swift
│   ├── SDAIConversation.swift  SDAIMessage.swift  SDAIInsight.swift
│   └── SDAppNotification.swift  SDPaymentMethodTag.swift
├── Mappers/                          SDVehicle ↔ Vehicle, one file per entity, bidirectional
├── Repositories/                     …RepositoryImpl. actors or Sendable structs over the actor
└── Sync/
    ├── CloudKitConfiguration.swift
    ├── SyncStatusMonitor.swift       NSPersistentCloudKitContainer.Event → SyncState
    └── FileSyncCoordinator.swift     ubiquity container download/upload + orphan GC
```

---

## 6. `Core/Infrastructure/` — the outside world

| Responsibility | One adapter per Apple/3rd-party API. Implements Domain `Ports`. |
|---|---|
| **May import** | anything Apple, vetted 3rd party |
| **Must not import** | Application, Features |

```
Core/Infrastructure/
├── AI/
│   ├── BackendAIProvider.swift       URLSession + SSE → AsyncThrowingStream<AIStreamEvent>
│   ├── SSEDecoder.swift
│   ├── AIRequestDTO.swift  AIResponseDTO.swift
│   ├── StructuredOutputDecoder.swift schema-validated JSON → typed domain results
│   └── MockAIProvider.swift          scripted; used by Previews, UI tests, offline dev
├── Vision/
│   ├── VisionTextRecognizer.swift    Vision framework OCR
│   ├── ImagePreprocessor.swift       downscale, orient, strip EXIF/GPS, JPEG-encode
│   └── PlateRecognizer.swift         OCR + per-region plate format validation
├── Subscriptions/
│   ├── StoreKitSubscriptionService.swift   actor. Transaction.updates listener
│   ├── ProductCatalog.swift                typed product IDs; no string literals at call sites
│   └── ReceiptEntitlementMapper.swift      Transaction → Entitlement
├── Notifications/
│   ├── UNNotificationScheduler.swift       implements NotificationScheduling
│   ├── NotificationContentBuilder.swift    localized content from domain payloads
│   └── NotificationCategoryRegistry.swift  actions: "Mark done", "Snooze"
├── Files/
│   ├── FileStorageActor.swift        implements FileStorage
│   ├── FileLocationResolver.swift    local vs. ubiquity container
│   └── ThumbnailGenerator.swift      QuickLookThumbnailing
├── Auth/
│   ├── AppleAuthProvider.swift       AuthenticationServices
│   ├── GoogleAuthProvider.swift      ASWebAuthenticationSession (no SDK — see §Security)
│   ├── EmailAuthProvider.swift       backend
│   └── KeychainStore.swift
├── Export/
│   ├── PDFExporter.swift             ImageRenderer / Core Graphics
│   └── ArchiveExporter.swift         JSON + files → .zip
├── Preferences/
│   └── UserPreferencesStore.swift    UserDefaults-backed; implements PreferencesProviding
└── Support/
    ├── NetworkMonitor.swift          NWPathMonitor → AsyncStream
    ├── SystemClock.swift             implements ClockProviding
    └── TelemetryService.swift        implements TelemetryProviding (opt-in, screen 21)
```

---

## 7. `Features/` — screen clusters

Every feature folder has the same shape. **No feature imports another feature.**

```
Features/<Name>/
├── <Name>View.swift              SwiftUI. dumb. binds to the ViewModel.
├── <Name>ViewModel.swift         @MainActor @Observable. holds ViewState. owns Tasks.
├── <Name>PresentationModel.swift display-ready value types (already formatted/derived)
├── Components/                   feature-private subviews
└── <Name>Formatter.swift         domain values → strings, using UnitSettings + Locale
```

The feature list:

```
Features/
├── Onboarding/          screens 01
├── Authentication/      screens 02, 03  (SignIn, SignUp, ForgotPassword)
├── Home/                screen 02-Home  (+ HomeDashboard presentation model)
├── Alerts/              screen 05       (notification inbox)
├── Garage/              screen 03-Garage
├── VehicleDetail/       screen 07
├── VehicleEditor/       screen 08       (Add + Edit share one editor)
├── QuickLog/            screen 04       (the [+] menu)
├── Fuel/                screens 05-Fuel, 10  (History + Editor)
├── Service/             screen 11 + service history timeline
├── Expenses/            screen 13 + expense editor
├── Reminders/           screen 15 + reminder editor
├── Documents/           screen 06 + document viewer + document editor
├── AIHub/               screen 07-AI
├── AIChat/              screen 18
├── ReceiptScan/         capture → review → confirm  (3 steps, 1 feature)
├── DashboardScan/       screen 17
├── DamageAnalysis/      capture → result
├── Analytics/           the statistics surfaces
├── Premium/             screen 20 (paywall)
├── Profile/             screen 08-Profile
└── Settings/            screen 21 + sub-screens (Units, Notifications, Data, About)
```

### 7.1 Feature-internal rules

- The **PresentationModel** is where derivation ends. A `HomeVehicleCard` presentation model already
  contains `mileageText: String`, `healthStatus: VehicleHealth.Status`, `nextServiceText: String`.
  The View performs **no** `if`-on-domain-enums beyond choosing an icon, and **no** arithmetic.
- A ViewModel exposes `private(set) var state: ViewState<XPresentationModel>` plus intent methods
  (`func onAppear() async`, `func save() async`). Nothing else is public.
- ViewModels are constructed by the feature's own `…Factory` extension on `AppDependencies`,
  keeping `init` parameter lists out of the call sites.

### 7.2 Shared feature infrastructure

`Core/DesignKit/` holds cross-feature view primitives (cards, rows, chart wrappers, camera
container, empty states). **It is explicitly out of scope for this architecture deliverable** —
listed only so it has a home and does not get scattered into `Features/`.
