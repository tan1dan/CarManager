# 01 · Executive Architecture Summary, Diagram, Dependency Rules

---

## 1. Executive Architecture Summary

**The choice: pragmatic Clean Architecture with feature-based MVVM, four layers, one module.**

```
Presentation (SwiftUI + @Observable ViewModels)
        ↓
Application  (Use Cases, Routers, App State, Feature Gate)
        ↓
Domain       (Entities, Value Objects, Calculators, Protocols)   ← depends on nothing
        ↑
Data/Infra   (SwiftData, CloudKit, StoreKit, AI, Vision, Files)  → implements Domain protocols
```

The dependency arrow into Domain is inverted at the bottom: **Domain declares protocols,
Infrastructure implements them.** Domain imports `Foundation` and nothing else.

### The five decisions that define this codebase

1. **Domain models are `Sendable` value types; SwiftData `@Model` classes never leave the Data
   layer.** This is not Clean-Architecture dogma — it is forced by Swift 6. `@Model` instances are
   reference types bound to a `ModelContext` and are not `Sendable`. If they leak into ViewModels
   you get either compiler errors or, worse, `@unchecked Sendable` and cross-actor crashes.
   Repositories map `@Model` ↔ `struct` at the boundary. The mapping is mechanical and buys you a
   fully framework-free, instantly testable Domain. → ADR-006

2. **There is no unified `Expense` table. There is a unified `CostEntry` *projection*.**
   `FuelEntry`, `ServiceRecord` and `Expense` stay separate, normalised entities. A domain service,
   `CostLedger`, projects all three into a single `[CostEntry]` stream that Analytics consumes.
   Storage cannot double-count because a receipt scan writes exactly **one** record of exactly one
   kind. → ADR-006

3. **`OdometerReading` is a first-class append-only entity.** Mileage arrives from fuel entries,
   service records, expenses, manual updates and (later) OBD. `Vehicle.currentOdometer` is a
   *derived* value, never an authoritative field. This kills two whole classes of bug: editing an
   old fuel entry corrupting current mileage, and CloudKit last-writer-wins clobbering the odometer
   when two devices sync. Append-only rows are conflict-free by construction. → ADR-006

4. **CloudKit via SwiftData's built-in mirroring is the entire sync layer. No hand-rolled sync
   metadata, no `syncStatus`, no `remoteID`, no tombstones.** The spec asks for those fields; they
   are the correct answer for a *custom backend* and the wrong answer for
   `NSPersistentCloudKitContainer`, which already maintains all of it and would fight you. What
   remains ours: file-blob sync, orphan-file GC, and a `SyncStatusMonitor` reading
   `NSPersistentCloudKitContainer.Event`. → ADR-003

5. **A backend exists, and its scope is exactly one thing: the AI.** It holds the model-provider API
   key, proxies and streams completions, enforces AI quota (A-08), and stores nothing about the
   user's vehicles. All *data* is CloudKit. This is the minimum backend that lets you ship an AI
   feature without shipping your API key inside the IPA. → ADR-008

### Why not the alternatives

| Candidate | Verdict |
|---|---|
| **Plain feature-based MVVM** | Rejected. Fuel-consumption segmentation, the "date OR mileage" reminder rule, health scoring and cost-of-ownership are genuine business logic with genuine edge cases. Without a Domain layer they end up in ViewModels, untestable without a `ModelContainer`, and duplicated between Home / Fuel / Analytics / AI-context. |
| **TCA** | Rejected. Excellent for this problem shape, but: a large third-party dependency for a solo developer, a reducer-per-feature ceremony tax on ~25 screens, awkward SwiftData interop, and its main payoff (exhaustive state testing) is largely obtainable here by testing pure calculators and use cases directly. → ADR-001 |
| **Textbook Clean with modules per layer** | Rejected for MVP. SPM module boundaries are the *enforcement* mechanism, not the architecture. Start single-target with folder discipline + an automated dependency lint; extract `Domain` and `AICore` into SPM packages in Phase 10 when the boundaries have stopped moving. |

### Testability posture

Everything that can be a **pure function of value types** is one: fuel segmentation, cost per km,
reminder evaluation, health scoring, analytics aggregation, feature gating, AI-context assembly.
These need no mocks, no `ModelContainer`, no async. Use cases need only protocol fakes. ViewModels
need only fake use cases. There is exactly one place that needs a real `ModelContainer`
(repository tests, in-memory) and exactly one that needs StoreKit (`.storekit` config tests).

---

## 2. Architecture Diagram

### 2.1 Layer & dependency graph

```
┌───────────────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                                  │
│                                                                               │
│  Views (SwiftUI)      ──observes──►  ViewModels  (@MainActor @Observable)     │
│  · zero business logic                · own ViewState<T>                       │
│  · zero formatting maths              · own a Task for cancellation            │
│  · reads @Environment(\.dependencies) · call use cases, never repositories     │
└───────────────┬───────────────────────────────────────────────────────────────┘
                │ calls (async)
┌───────────────▼───────────────────────────────────────────────────────────────┐
│ APPLICATION                                                                   │
│                                                                               │
│  Use Cases (structs, Sendable)   AppRouter / TabRouters   SelectedVehicleStore │
│  FeatureGate                     AuthSessionStore         EntitlementStore     │
│  · orchestration + transactions  · typed navigation state  · global app state  │
│  · enforce cross-entity rules                                                  │
└───────────────┬───────────────────────────────────────────────────────────────┘
                │ uses protocols + pure calculators
┌───────────────▼───────────────────────────────────────────────────────────────┐
│ DOMAIN                       (import Foundation — nothing else)               │
│                                                                               │
│  Entities: Vehicle, FuelEntry, ServiceRecord, Expense, Reminder,              │
│            DocumentMetadata, OdometerReading, AIConversation, …               │
│  Value objects: Money, Distance, Volume, Odometer, DateRange, VIN, Plate      │
│  Calculators (pure): FuelConsumptionCalculator, CostLedger, StatisticsEngine, │
│                      ReminderEvaluator, VehicleHealthScorer, MileageProjector │
│  Protocols: *Repository, AIProvider, FileStorage, NotificationScheduler, …    │
│  Errors: DomainError tree                                                      │
└───────────────▲───────────────────────────────────────────────────────────────┘
                │ implements (dependency inversion)
┌───────────────┴───────────────────────────────────────────────────────────────┐
│ DATA / INFRASTRUCTURE                                                         │
│                                                                               │
│  Persistence   SwiftData @Model + PersistenceActor(@ModelActor) + Mappers     │
│  Sync          CloudKit mirroring, SyncStatusMonitor, FileSyncCoordinator     │
│  AI            BackendAIProvider (SSE stream) · MockAIProvider                │
│  Vision        VisionTextRecognizer (OCR) · ImagePreprocessor                 │
│  Store         StoreKitSubscriptionService (actor) + Transaction.updates      │
│  Files         FileStorageActor (App Support + iCloud ubiquity container)     │
│  Notify        UNUserNotificationCenterScheduler                              │
│  Auth          AppleAuthProvider · GoogleAuthProvider · EmailAuthProvider     │
│  Support       KeychainStore, NetworkMonitor, TelemetryService, PDFRenderer   │
└───────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 The two runtime write paths

```
WRITE (offline-first, never awaits the cloud)

 View ─intent─► ViewModel ─► UseCase ─► Repository ─► PersistenceActor ─► SQLite
                                │                                          │
                                ├─► NotificationScheduler (reschedule)     │
                                ├─► FileStorage (blob write)               │
                                └─► returns domain value ◄─────────────────┘
                                            │
                     ViewState updated ◄────┘        (UI is done here — no network)

                                            ⋮ later, independently ⋮
                              NSPersistentCloudKitContainer export ──► iCloud
                                            │
                              SyncStatusMonitor ──► SyncState (a badge, never a blocker)
```

```
READ (change-feed, no @Query)

 SQLite ─didSave / remote-change notification─► PersistenceActor
                                                     │
                                       Repository.changes: AsyncStream<Void>
                                                     │
                                ViewModel re-fetches ─► ViewState<[DomainValue]>
                                                     │
                                                   View
```

---

## 3. Dependency Rules

### 3.1 The rule table

| Layer | MAY import | MUST NOT import | MAY depend on layers |
|---|---|---|---|
| **Domain** | `Foundation` only | SwiftUI, SwiftData, CloudKit, StoreKit, UserNotifications, Vision, UIKit, Combine, any 3rd party | *(none)* |
| **Application** | `Foundation`, `Observation` | SwiftUI, SwiftData, StoreKit, UserNotifications, Vision, UIKit | Domain |
| **Data / Infrastructure** | anything Apple + vetted 3rd party | *(may not import Presentation or Application)* | Domain |
| **Presentation** | SwiftUI, `Observation`, `Charts`, `PhotosUI`, `VisionKit`, `AuthenticationServices` | SwiftData, CloudKit, StoreKit, `URLSession`, any `*Repository` implementation | Application, Domain |
| **App (composition root)** | everything | — | all |

### 3.2 Rules stated as prohibitions (these are the ones that get violated)

1. **No SwiftUI `View` may import `SwiftData`.** Corollary: **`@Query` is banned.** → ADR-002
2. **No `View` may hold a repository, a service, or `AppDependencies` in full.** Views read only the
   ViewModel they were handed.
3. **No ViewModel may hold a repository.** ViewModels hold **use cases**. The single exception is
   the three observable Application stores (`SelectedVehicleStore`, `EntitlementStore`,
   `AuthSessionStore`), which are read directly.
4. **No `View` may import `StoreKit`.** Paywall reads `EntitlementStore` + `ProductCatalog`
   presentation models.
5. **No Domain type may be `class`** unless there is a written justification. All entities are
   `struct`, `Sendable`, `Equatable`, and where sensible `Identifiable`.
6. **No use case may import `SwiftData`.** It talks to `…Repository` protocols.
7. **No Domain type may reference `PersistentIdentifier`.** Domain IDs are typed `UUID` wrappers
   (`VehicleID`, `FuelEntryID`, …).
8. **No feature may import another feature.** Cross-feature communication goes through Application
   (routers, stores) or Domain. `Features/Fuel` may not `import` anything from `Features/Home`.
9. **No `DispatchQueue`, no `NotificationCenter` observers in Presentation, no Combine** except in
   the thin Infrastructure adapters that bridge Apple APIs into `AsyncStream`.
10. **No secret in the bundle.** No API key, no `.plist` credential, no hard-coded token.

### 3.3 Enforcing them mechanically

A dependency test suite fails the build on violation (see `13-testing.md §Architecture tests`):

```swift
@Test func domainImportsOnlyFoundation() throws {
    let offenders = try SourceScanner.imports(in: "Core/Domain")
        .filter { $0.module != "Foundation" }
    #expect(offenders.isEmpty, "Domain must not import \(offenders)")
}

@Test func viewsDoNotImportPersistenceOrStoreKit() throws {
    let banned: Set = ["SwiftData", "StoreKit", "CloudKit"]
    #expect(try SourceScanner.imports(inFilesMatching: "*View.swift")
        .allSatisfy { !banned.contains($0.module) })
}

@Test func featuresAreMutuallyIsolated() throws { /* Features/A must not reference Features/B */ }
```

`SourceScanner` is ~60 lines of regex over the source tree, run as a unit test. It is the cheapest
architecture enforcement available and it survives refactors, unlike code review.
