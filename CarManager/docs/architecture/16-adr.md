# 16 · Architecture Decision Records

Format: **Decision · Reason · Alternative considered · Why the alternative was rejected.**

---

## ADR-001 — Architecture pattern

**Decision.** Pragmatic **Clean Architecture (4 layers) + feature-based MVVM**, single Xcode target,
`@Observable` ViewModels, use cases as `Sendable` structs, protocols only at external boundaries.

**Reason.** This app has genuine, edge-case-heavy business logic — full/partial-tank fuel
segmentation, "date OR mileage, whichever first" with recurrence rebasing, cost-ledger projection
across three tables, deterministic health scoring, entitlement gating. That logic is consumed by
**four different surfaces** (Home, the feature screen, Analytics, the AI context builder). It must
live in one tested place. A Domain layer of pure value types gives that, tests in microseconds, and
— critically for Swift 6 — sidesteps `Sendable` problems entirely.

**Alternatives considered.**

- *Plain feature-based MVVM.* **Rejected:** the logic above would land in ViewModels, requiring a
  `ModelContainer` to test and being duplicated across the four consumers. The consumption
  calculation alone would be written three times and would disagree with itself.
- *TCA.* **Rejected:** genuinely well-suited to this problem, but it is a large third-party
  dependency for a solo developer, imposes reducer ceremony across ~25 screens, has awkward SwiftData
  interop, and its headline benefit (exhaustive state testing) is largely achieved here by testing
  pure calculators and use cases directly. The cost/benefit does not clear the bar.
- *Textbook Clean with an SPM module per layer from day one.* **Rejected for MVP:** module
  boundaries are an enforcement mechanism, and enforcement is cheaper as a lint test (`01 §3.3`)
  while the boundaries are still moving. Extract `Domain` and `AICore` in Phase 10.
- *VIPER.* **Rejected:** presenter/interactor/router-per-screen is ~5× the file count for a solo dev.

---

## ADR-002 — Persistence

**Decision.** **SwiftData** with `@Model` classes confined to `Core/Data`, accessed through a single
`@ModelActor` `PersistenceActor`, mapped to `Sendable` domain structs at the repository boundary.
**`@Query` is banned**; UI updates flow from a repository change feed.

**Reason.** SwiftData is Apple-native, gives one-flag CloudKit mirroring, `#Index`, a versioned
migration plan, and a first-class `@ModelActor` concurrency story. The struct boundary is *forced* by
Swift 6: `PersistentModel` is not `Sendable`, so returning `@Model` from an actor is either a compile
error or an `@unchecked Sendable` data race.

**Alternatives considered.**

- *Core Data.* **Rejected:** same engine, more boilerplate, worse strict-concurrency ergonomics, no
  compensating advantage for this feature set.
- *SQLite / GRDB.* **Rejected:** better queries and observability — genuinely attractive for the
  analytics workload — but it forfeits CloudKit mirroring, turning sync into a project larger than
  the rest of the app.
- *SwiftData with `@Query` in views (the idiomatic path).* **Rejected:** it puts persistence into
  Views, which the brief forbids; it makes those views untestable without a container; it cannot
  express the paged, filtered, cross-entity queries this app needs (the cost ledger merges three
  entities); and it re-introduces `@Model` on the main actor. Cost of rejecting it: we write a change
  feed (~80 lines) and re-fetch on change. Accepted.
- *`@Model` classes used directly as domain models.* **Rejected:** the `Sendable` problem above, plus
  it would make every domain test require a `ModelContainer`, plus it couples the Domain to SwiftData
  permanently — the one dependency the brief explicitly forbids.

---

## ADR-003 — Cloud sync

**Decision.** **`NSPersistentCloudKitContainer` mirroring to the CloudKit private database, and
nothing else.** No custom sync engine, no `syncStatus`/`remoteID`/`version`/`deletedAt` columns. We
own only: sync-status observation, file-blob sync via the ubiquity container, and orphan-file GC.
A backend exists **for AI only** (`07 §5`).

**Reason.** Free, private-by-default, zero server cost, zero GDPR data-controller burden for vehicle
data, and it handles the genuinely hard parts (change tokens, batching, retry, throttling, delete
propagation). The domain model was deliberately shaped — append-only `OdometerReading`, UUID keys,
no contested mutable scalars — so that CloudKit's last-writer-wins policy is *safe by construction*
rather than needing to be made safe.

**Alternatives considered.**

- *Hand-rolled sync metadata + outbox, per the spec's field list.* **Rejected:** `syncStatus` is
  actively harmful here — `NSPersistentCloudKitContainer` neither exposes per-row sync state nor
  consults ours, so the column would be written by us, never updated by the framework, and would lie
  within seconds. Tombstones would add a `deletedAt == nil` clause to every predicate in the app,
  which *will* be forgotten in exactly one analytics query. The full escape-hatch shape is specified
  in `07 §6.2` for the day a real backend arrives; building it now is pure cost.
- *A custom backend as the system of record.* **Rejected for MVP:** server cost, ops, auth
  complexity and privacy obligations, for data that is inherently single-user and private.
- *CloudKit direct (`CKRecord`) instead of mirroring.* **Rejected:** we would write the local cache
  and the merge policy ourselves — the same work as a custom sync engine, with less flexibility.
- *Gating iCloud sync behind Premium (as the spec's paywall implies).* **Rejected — A-05:** it
  requires two store configurations and a destructive store migration on every entitlement change
  (purchase, lapse, refund, Family Sharing revocation). Highest-risk code in the app, for a feature
  users read as "don't lose my data". Recommend selling export + full-history analytics instead.

---

## ADR-004 — Navigation

**Decision.** **Typed, `Codable` route enums** (`AppRoute`, `ModalRoute`, `FullScreenRoute`, unified
as `AppDestination`) driven by `@Observable` routers, with **all** navigation passing through
`AppRouter.navigate(to:)` and a pure `RouteGuard` handling auth, premium and disclaimer
interception.

**Reason.** Deep links, notification taps, paywall-then-replay, auth-then-replay and state
restoration are all the *same* operation on the same value type. Making destinations `Codable`
values means one parser, one guard, one navigate call — and the entire gating matrix is unit-testable
with no UI.

**Alternatives considered.**

- *`NavigationLink(destination:)` with view-owned navigation.* **Rejected:** cannot express premium
  gating or auth redirects without scattering `if isPremium` through views; not restorable; not
  testable.
- *A single flat `NavigationPath` for the whole app.* **Rejected:** loses per-tab stack state, which
  the tab bar requires.
- *A coordinator per feature (UIKit-style).* **Rejected:** more objects, and cross-feature routing
  (Home → Paywall → Receipt scan) becomes a coordinator-negotiation problem. One router with a pure
  guard is smaller and more testable.

---

## ADR-005 — Dependency injection

**Decision.** A hand-written `AppDependencies` struct composed once in `CarManagerApp.init()`;
constructor injection into use cases and ViewModels; `@Environment` used only to reach feature
factories. **No DI framework, no singletons, no `.shared`.**

**Reason.** ~30 dependencies is well within what explicit composition handles. Compile-time safety —
a missing dependency is a build error, not a runtime crash. `AppDependencies.testing { $0.clock = … }`
makes substitution a one-liner.

**Alternatives considered.**

- *Swinject / Factory / Needle.* **Rejected:** trades compile-time errors for runtime crashes and
  adds a dependency, to solve a problem this app does not have.
- *`@Environment` key per dependency.* **Rejected:** 30 `EnvironmentKey`s each needing a
  `defaultValue` that is either `fatalError` or a silent stub — both bad — and it makes non-View
  code (use cases) unable to resolve dependencies at all.
- *Singletons.* **Rejected:** untestable, order-dependent, explicitly forbidden by the brief.

---

## ADR-006 — Domain modelling

Four sub-decisions, each explicitly demanded by the brief.

### 6a — Value-type domain, separate from `@Model`
**Decision.** Domain entities are `Sendable` structs; `@Model` classes live only in `Core/Data`;
repositories map between them.
**Reason.** Swift 6 `Sendable` (ADR-002), plus a Domain testable with zero framework setup.
**Alternative:** `@Model` as the domain model. **Rejected:** data races or `@unchecked Sendable`;
every domain test needs a container; permanent SwiftData coupling.

### 6b — No unified `Expense` table; a `CostEntry` projection instead
**Decision.** `FuelEntry`, `ServiceRecord` and `Expense` remain three normalised entities.
`CostLedger` (pure) projects all three into `[CostEntry]` for analytics. Each write flow produces
**exactly one** record.
**Reason.** No storage duplication ⇒ double-counting is structurally impossible, while analytics still
gets one vocabulary and one feed (screenshot 13 needs exactly this).
**Alternatives:** *(a) one `Transaction` table with subtypes* — **rejected:** single-table-inheritance
nulls, cross-feature coupling, awkward multi-row atomicity under CloudKit; *(b) fuel/service also
write an `Expense` row* — **rejected:** guaranteed double-count on the first edit or sync conflict,
the exact failure the brief warns about; *(c) ad-hoc summing in each analytics surface* —
**rejected:** Home and Analytics drift apart.

### 6c — `OdometerReading` as a first-class append-only entity
**Decision.** Mileage is never an authoritative `Vehicle` column; it is derived from append-only
readings written by fuel/service/expense/manual (and later OBD) sources.
**Reason.** Kills two bug classes at once: editing an old record corrupting current mileage, and
CloudKit last-writer-wins clobbering a contested odometer field. Append-only rows are conflict-free.
It also makes `distanceDriven` correct for periods with no fuel entries, and gives OBD a home.
**Alternative:** `Vehicle.currentMileage` as a mutable column. **Rejected:** it is the single most
likely source of silent data corruption in this app.

### 6d — Hard delete, no tombstones
**Decision.** Cascade/nullify deletes per `03 §3.1`; no `deletedAt` anywhere; undo is a UI-level
deferred-write buffer; files are swept by a GC with a 7-day grace window.
**Reason.** CloudKit propagates deletes natively; tombstones would add a `deletedAt == nil` predicate
to every query in the app.
**Alternative:** soft delete. **Rejected:** doubles row count, and one forgotten predicate produces
ghost rows in a report.

---

## ADR-007 — Analytics

**Decision.** A **deterministic, pure** `StatisticsEngine` + `FuelConsumptionCalculator` +
`CostLedger` producing an `AnalyticsReport` of `Metric<T>` values, computed on demand off the main
actor, cached in memory by `(vehicle, period, dataVersion)`. **No precomputed totals in the
database.** AI consumes the report, never raw rows.

**Reason.** Determinism is testable and explainable; a number a user can't reproduce is a support
ticket. `Metric<T>` forces every screen to handle "no data" explicitly instead of rendering a
fabricated `€0` or `0.0 L/100km` — which is the same class of error as letting the AI invent
statistics, and is refused for the same reason.

**Alternatives considered.**

- *Denormalised rollup tables in SwiftData.* **Rejected:** derived data in the database goes stale,
  and with CloudKit mirroring it goes stale *on another device*. Recomputation is milliseconds.
  Escape hatch documented in `09 §6` if a garage ever exceeds ~50k rows.
- *Computing in ViewModels or views.* **Rejected:** explicitly forbidden, and it would be written
  four times over (Home, Fuel, Analytics, AI context).
- *Letting the AI compute statistics from raw records.* **Rejected:** non-deterministic, expensive,
  and it is precisely what the brief prohibits.

---

## ADR-008 — AI abstraction

**Decision.** Two Domain ports — `AIProvider` (streaming + structured) and `VisionAnalysisProvider`
(one provider, three request types). All requests go through **our backend**, which holds the model
key, owns the system prompts, selects the model from a `purpose`, and enforces quota. Grounding is
enforced by a **post-validation metric allowlist**, not by prompt instructions.

**Reason.** Provider replacement is a one-line change in the composition root. Model selection and
prompts ship without an App Store release. The key cannot leak because it is never on the device.
And "the AI must not invent statistics" becomes a filter (which bites) rather than a prompt (which
is advisory).

**Alternatives considered.**

- *Direct provider SDK in the app.* **Rejected:** ships the API key, hard-codes a vendor, and puts
  prompt fixes behind App Store review.
- *Three separate protocols for receipt/dashboard/damage.* **Rejected:** they share transport, auth,
  quota, retry and error handling. Three protocols would triple the mock surface for no benefit.
  One protocol, three request cases.
- *On-device Foundation Models for everything.* **Rejected for MVP:** insufficient for damage-cost
  estimation and receipt extraction quality, and it constrains the deployment target. Retained as a
  future implementation of the same port (`08 §1`) — a genuine, cheap extension point.
- *Sending raw records to the model and letting it aggregate.* **Rejected:** token cost, latency,
  non-determinism, privacy, and hallucinated statistics.

---

## ADR-009 — Subscription architecture

**Decision.** **StoreKit 2** behind `SubscriptionProviding`; one `actor` service; an app-lifetime
`Transaction.updates` listener; a single `@MainActor` `EntitlementStore`; a **pure** `FeatureGating`
function wrapped by `FeatureGate`. Enforcement at exactly three points: `RouteGuard`, use cases, and
(display-only) presentation. **Exactly one file imports StoreKit.**

**Reason.** Premium state is centralised and observable; the gating matrix — where product bugs
actually live — is a pure function testable without StoreKit; and no view can accidentally become an
enforcement point.

**Alternatives considered.**

- *Views querying StoreKit directly.* **Rejected:** explicitly forbidden, untestable, and it
  scatters entitlement logic.
- *A boolean `isPremium` flag.* **Rejected:** cannot express `.allowedWithQuota` (the free AI taste),
  grace periods, billing retry, Family Sharing source, or intro-offer eligibility — all of which this
  product needs.
- *A receipt-validation backend as the entitlement source of truth.* **Deferred:** StoreKit 2's
  on-device verification is cryptographically sound. The backend verifies transactions only to gate
  *its own* AI quota (`07 §5`), not to gate the client UI.
- *Client-enforced AI quota.* **Rejected — A-08:** trivially bypassed. The server is authoritative;
  the client counter is optimistic UI only.

---

## ADR-010 — Notification architecture

**Decision.** Pure Domain (`ReminderEvaluator`, `RecurrenceCalculator`, `MileageProjector`,
`NotificationPlanner`) emitting plain `ScheduledNotification` values; a single Infrastructure adapter
is the only file importing `UserNotifications`. Mileage triggers are **projected to dates** and
rescheduled on every odometer write; `.whicheverFirst` schedules **both**; only the next 3
occurrences are scheduled (iOS 64-request cap).

**Reason.** The brief requires the separation, and it pays off immediately: every hard part —
occurrence dates, escalation, identifiers, recurrence rebasing — is unit-tested with no permissions
and no waiting. The in-app evaluation is exact and authoritative; the OS notification is an
explicitly best-effort nudge (`11 §3.3`).

**Alternatives considered.**

- *Scheduling directly from ViewModels.* **Rejected:** couples the domain to `UNUserNotificationCenter`,
  untestable, and duplicated across three features.
- *Scheduling all recurring occurrences.* **Rejected:** silently exceeds the 64-request cap for a
  multi-vehicle garage and drops notifications with no error.
- *Background location or significant-change monitoring to infer mileage.* **Rejected:** a
  privacy-hostile permission for an estimate we can derive from the user's own fill-up cadence.

---

## ADR-011 — File storage

**Decision.** `DocumentMetadata` + `FileRef` (id, **relative** path, SHA-256); bytes on disk under
`Application Support/Files/` behind a `FileStorage` actor; cross-device sync via the **iCloud
ubiquity container**; sweep-based GC with a 7-day grace window; `FileAvailability` is a first-class
UI state.

**Reason.** Keeps blobs out of the SwiftData/CloudKit record graph, gives on-demand download with
progress, and makes the Documents list render instantly offline because metadata is always local.
Relative paths avoid the classic "all attachments vanished after the update" bug.

**Alternatives considered.**

- *`@Attribute(.externalStorage)`.* **Rejected:** with mirroring on, blobs become `CKAsset`s coupled
  to record sync — they re-upload on unrelated edits, cannot be fetched on demand, expose no
  progress, and have no purge strategy. A 12 MB manual (screenshot 06) makes this concrete.
- *`Data` columns in SwiftData.* **Rejected:** the brief forbids it, and it would bloat every fetch.
- *CKAsset in a custom CloudKit zone.* **Rejected:** more control, but a second CloudKit integration
  with its own change tokens beside the mirrored store. The ubiquity container gets ~90% of the value
  for ~10% of the work.
- *Reference counting for file GC.* **Rejected:** a `FileRef` can legitimately be shared by two
  records; a sweep with a grace window is simpler and safe against sync races.

---

## ADR-012 — Concurrency

**Decision.** Swift 6 language mode, strict concurrency complete. `@MainActor @Observable` ViewModels
and the five global stores; **nonisolated `Sendable` use cases**; actors for persistence, files,
StoreKit and auth; `AsyncThrowingStream` for AI streaming; `AsyncStream` for every callback-API
bridge. **No Combine, no `DispatchQueue`, no `@unchecked Sendable`.**

**Reason.** All domain types are `Sendable` value types, so isolation boundaries are cheap and the
compiler proves the absence of data races. `AsyncThrowingStream` matches AI chat's shape exactly
(single-consumer, finite, cancellable, failable) and gives cancellation for free through structured
concurrency.

**Alternatives considered.**

- *Combine for streaming.* **Rejected:** reference-type publishers and cancellables leaking into the
  Application layer, and it does not compose with `async` use cases.
- *`@MainActor` on use cases "to satisfy the compiler".* **Rejected — and called out explicitly in
  `12 §14`** because it is the most common Swift 6 mistake in SwiftData apps: it compiles, passes
  tests, and runs every fetch and mapping loop on the main thread.
- *A callback/delegate AI API.* **Rejected:** pushes cancellation management into the ViewModel.
- *`@unchecked Sendable` on `@Model` types.* **Rejected:** converts a compile error into a crash.

---

## ADR-013 — Testing

**Decision.** `swift-testing`, an inverted-cost pyramid with the bulk of coverage on **pure domain
functions**, **fakes over mocks**, an injected `FixedClock` everywhere, in-memory `ModelContainer`
only for repository tests, `SKTestSession` for subscriptions, ~8 UI tests, and an
**architecture-lint test suite** enforcing the dependency rules.

**Reason.** The architecture deliberately concentrates risk into pure functions, so the cheapest
tests cover the most dangerous logic. `FixedClock` is what makes every reminder, expiry, recurrence
and period test deterministic — it is the single highest-leverage seam in the codebase.

**Alternatives considered.**

- *Heavy UI-test coverage.* **Rejected:** slow, brittle, and it would be testing arithmetic through a
  camera and a paywall. Reserved for the 8 journeys that cross layers.
- *Mock-verification style (assert `insert` was called).* **Rejected:** proves nothing about
  correctness and breaks on refactor. Fakes let tests assert on outcomes.
- *Code-review-enforced dependency rules.* **Rejected:** does not survive a tired evening. A ~60-line
  source scanner run as a unit test does.
- *Deferring tests until after the MVP.* **Rejected:** the fuel algorithm, the reminder matrix and the
  receipt-confirmation flow are exactly the things that must be right on day one, and they are the
  cheapest things in the app to test.
