# 18 · Risks, Technical Debt, Extension Points, Recommended Next Step

---

## 1. Risks

Ranked by expected cost (likelihood × impact).

### R-01 · The auth/CloudKit identity split confuses users — **HIGH**
A user signs in with Google on a new device and finds an empty garage, because data follows the
**iCloud** account (A-03). This is not a bug we can fix in code; it is a consequence of using
CloudKit for data and third-party auth for identity.
**Mitigation.** Explicit, non-euphemistic UI copy at three points: sign-in ("your garage stays on
this iCloud account"), sign-out, and account deletion. Detect and warn when the device's iCloud
account changes or is absent. **Contingency:** if support volume proves this untenable, the fix is a
real backend as system-of-record — a `Core/Data` rewrite that leaves Domain, Application and
Presentation untouched (`07 §6.2`). Budget: 4–6 weeks, and it is the single largest latent cost in
this architecture.

### R-02 · CloudKit mirroring schema constraints discovered late — **HIGH**
A non-optional property or a `@Attribute(.unique)` makes `NSPersistentCloudKitContainer` fail to
initialise mirroring — often **silently**, presenting as "sync just doesn't work".
**Mitigation.** `CloudKitSchemaTests` (`13 §3.11`) asserts all five constraints by reflection from
Phase 1. Enable the container with CloudKit in Phase 1, not Phase 9. Deploying the CloudKit schema
dev→prod is a **release-checklist item**, not something to remember.

### R-03 · Mileage-based reminder projections are wrong for irregular drivers — **MEDIUM-HIGH**
A user who drives 2,000 km in one week and nothing for two months gets bad projections (A-10).
**Mitigation.** Copy never states a date for a mileage trigger ("due in ~520 km"). Re-projection on
every odometer write and a daily `BGAppRefreshTask`. `.whicheverFirst` schedules both triggers so the
date half still fires correctly. **The in-app evaluation is exact and is the truth** (`11 §3.3`).
**Residual risk accepted:** notifications for mileage-only reminders will sometimes be early or late.
The alternative (background location) is privacy-hostile and would be worse.

### R-04 · AI cost per user exceeds subscription revenue — **MEDIUM-HIGH**
Vision requests (receipt, dashboard, damage) are expensive; a heavy user can outspend €4.99/month.
**Mitigation.** Server-side quota is authoritative (A-08). On-device OCR reduces receipt tokens.
Context is bounded and deterministic, enabling prompt caching. `purpose`-based model selection lets
cheap models handle cheap tasks without an app release. **Monitor cost-per-active-subscriber from
day one** — it is the metric most likely to invalidate the pricing in screenshot 20.

### R-05 · AI gives unsafe automotive advice — **MEDIUM likelihood, HIGH impact**
Dashboard scan says "safe to drive" about a failing brake system.
**Mitigation, structural rather than editorial:** `AIDisclaimer` is a non-optional field on both
result types; `drivingSafety` **defaults to `.unknown`** on unparseable output so the failure mode is
never "safe"; acknowledgement is required before first use per disclaimer version; there is no
"save as service record" shortcut from a scan result (`03 §6`). Backend system prompts are versioned
so guidance can be tightened without an App Store release. Have the disclaimer copy reviewed by
someone qualified before launch.

### R-06 · Free-tier AI quota is bypassed — **MEDIUM**
Reinstall, clock change, jailbreak.
**Mitigation.** Server-side enforcement keyed to the account; anonymous users get a device-scoped,
rate-limited token. Accepted residual: a determined user can farm anonymous tokens. Cap anonymous
quota low enough that this is not worth their time.

### R-07 · Mixed-currency data produces confusing analytics — **MEDIUM**
A car bought in Germany, fuelled in Sweden (the screenshots are Swedish with € prices — this is not
hypothetical).
**Mitigation.** `AnalyticsReport.totals` is keyed by currency and **never summed** (A-13); a
`hasMixedCurrencies` flag drives a disclosure. **Accepted debt:** no FX conversion in MVP. If this
proves common, add a `CurrencyConverter` port with cached historical rates — an additive change to
`StatisticsEngine`.

### R-08 · Repository change-feed re-fetching is slow at scale — **MEDIUM**
Rejecting `@Query` means re-fetching on change. A CloudKit import burst could trigger many refreshes.
**Mitigation.** 250 ms debounce, entity-scoped filtering, paged queries, `#Index` on every sort key,
in-memory analytics cache keyed by `dataVersion`. **Escape hatch:** granular change events carrying
changed IDs, so a list can patch a single row instead of re-fetching. Profile with a seeded 5-year,
3-vehicle garage in Phase 10.

### R-09 · Notification 64-request cap silently drops reminders — **MEDIUM**
5 vehicles × 8 reminders × multiple occurrences exceeds the cap; iOS drops without an error.
**Mitigation.** Only the next 3 occurrences per reminder are scheduled (`11 §3.4`). Add a runtime
assertion that `pending().count < 60` and report overflow via telemetry.

### R-10 · SwiftData bugs or behaviour changes across iOS releases — **MEDIUM**
Historically the riskiest Apple framework in this stack.
**Mitigation.** Repository boundary means a fallback to Core Data (same store format) touches only
`Core/Data`. `SchemaV1` + a migration plan exist from day one. Pin the deployment target
deliberately (A-27) and test each iOS beta against the repository suite.

### R-11 · Receipt-scan extraction quality disappoints — **MEDIUM**
Crumpled thermal receipts in many languages.
**Mitigation.** Every field is a `FieldSuggestion` with confidence; low-confidence fields are shown
unaccepted so the user must look at them; the manual editor is always one tap away; the captured
image is always attached to the created record regardless. The flow **degrades to "a faster way to
attach a receipt"**, which is still useful.

### R-12 · Solo-developer scope — **HIGH (project risk, not architectural)**
The MVP is 15 feature areas across 10 phases.
**Mitigation.** The roadmap is dependency-ordered so each phase ships something demonstrable.
**Recommendation: cut Damage Analysis and PDF Export from MVP v1.** Both are additive, neither is on
the critical path, and both can ship in v1.1 without an architectural change. That removes roughly
two weeks with no structural cost.

---

## 2. Accepted technical debt

Debt taken **knowingly**, with the repayment condition stated.

| # | Debt | Why accepted now | Repay when |
|---|---|---|---|
| D-01 | Single Xcode target instead of SPM modules | Boundaries are still moving; lint tests enforce them meanwhile (`01 §3.3`) | Phase 10, or when build times exceed ~90 s |
| D-02 | ~15 mapper files of mechanical `@Model` ↔ struct code | The price of Swift 6 safety + a framework-free Domain (ADR-006a) | Never — this is a correct cost, not a defect |
| D-03 | No FX conversion | Complexity and a rate-source dependency for an uncommon case | When telemetry shows mixed currency is common (R-07) |
| D-04 | No offline AI queueing (typed message is kept as a draft, not auto-sent on reconnect) | Adds an outbox and retry semantics for modest benefit | If offline AI attempts are frequent |
| D-05 | Analytics recomputed, never materialised | Correctness over speed; recomputation is milliseconds | If profiling shows >100 ms at realistic scale (`09 §6`) |
| D-06 | Scans (`ReceiptScan`, `DashboardScan`, `DamageAnalysis`) persisted as audit rows and purged at 30 days | Cheap provenance and debuggability | Purge policy configurable if storage complaints appear |
| D-07 | No certificate pinning | Breaks under CDN rotation; a common cause of app-wide outages | If the threat model changes |
| D-08 | `VehicleHealthScorer` weights are hard-coded constants | No data yet to tune them | After launch, once real distributions are visible; move to a remote-configurable table |
| D-09 | UI-level undo (deferred write) rather than a domain undo stack | Covers the actual need (accidental delete) at ~5% of the cost | If multi-step undo is ever requested |
| D-10 | No `CKShare` / family data sharing | A-07 scoped it out; `Vehicle.ownershipScope` reserves the field | If family data sharing is prioritised (a large project) |

---

## 3. Extension points for the deferred iOS features

Each is designed to be **additive** — none requires changing an existing layer.

| Feature | Hook | Work required |
|---|---|---|
| **Home / Lock Screen widgets** | `LoadHomeDashboard` + `EvaluateReminderTriggers` are already pure use cases over repositories | Add a widget extension + App Group; move the store to the shared container; reuse the use cases verbatim. **Plan the App Group in Phase 1** — relocating the store later is a migration. |
| **Live Activities** | `ReminderEvaluation`/`ServiceRecord` are `Codable` values | ActivityKit attributes over existing domain types |
| **App Intents / Siri** | Use cases are already `Sendable` structs with typed input/output — the exact shape an `AppIntent` needs | One `AppIntent` per use case: "log a fill-up", "what's my consumption" |
| **Apple Watch** | Repositories + use cases are platform-agnostic; only Presentation is iOS-specific | A watchOS target sharing `Core/`; this is the payoff of D-01's eventual repayment |
| **Push notifications** | `ScheduledNotification` and the `AppDestination` payload are transport-agnostic | Add an APNs implementation of `NotificationScheduling` alongside the local one |
| **OBD-II** | **`OdometerSource.obd` already exists**; `RecordSource.automatic` already exists | An `OBDProviding` port writing `OdometerReading`s and `FuelEntry`s. The model change is *zero*. |
| **Custom backend for data** | Repository protocols | Swap implementations in `Core/Data`; `SyncMetadata` shape pre-specified (`07 §6.2`) |
| **On-device AI** | `AIProvider` | A Foundation Models implementation; one line in the composition root |
| **CarPlay** | Presentation-only | New target reusing Application + Domain |

The consistent theme: **the extension points are ports and value types that already exist**, not
hypothetical abstractions added "just in case". `OdometerSource.obd` costs one enum case today and
saves a data migration later — that is the standard applied throughout.

---

## 4. Open questions for the product owner

Answering these changes work; none blocks starting Phase 1.

1. **A-05:** Confirm iCloud sync moves out of the paywall. (Recommendation: yes.)
2. **A-03:** Is "my garage follows my app account, not my iCloud account" a launch requirement? If
   yes, the persistence decision changes now rather than later — this is the one answer that would
   alter Phase 1.
3. **A-01:** Confirm the tab bar is Home/Garage/[+]/AI/Profile with Analytics as a destination.
4. **A-06:** Confirm the free tier keeps all raw history and is limited only in analytics window.
5. **R-12:** Approve cutting Damage Analysis and PDF Export from v1.
6. Which markets/languages at launch? Drives plate-format validation (A-15) and OCR languages.
7. Who owns the backend, and is the AI provider chosen? Not needed until Phase 7.
8. Minimum iOS version (A-27) — 18.0 assumed.

---

## 5. Recommended next step

**Build Phase 1 — but only these five things, in this order, in roughly one focused week:**

1. **`PersistenceStack` with CloudKit mirroring enabled and `CloudKitSchemaTests` green.**
   Do this before any entity exists beyond `Vehicle`. Discovering a mirroring constraint in Phase 9
   is R-02, the second-highest risk on the list.
2. **`ClockProviding` + `FixedClock`, and a lint rule banning `Date()` outside Infrastructure.**
   The highest-leverage hour in the project. Every reminder, expiry, recurrence and analytics test
   depends on it, and it cannot be retro-fitted cheaply.
3. **`ArchitectureRuleTests`.** ~60 lines of source scanning. It will fail usefully for the entire
   project life and is the only dependency enforcement that survives a tired evening.
4. **`AppDependencies` + `AppRouter` + `AppDestination` + `RouteGuard`** (guard decisions stubbed to
   `.allow`). Wiring the router last is how apps end up with navigation scattered across views.
5. **The domain primitives** — `Money`, `Distance`, `Volume`, `Odometer`, typed IDs, `Metric<T>`,
   the `DomainError` tree — with their arithmetic tests.

**Then, immediately after Phase 1, write `FuelConsumptionCalculator` and its 17 tests — before any
fuel UI exists.** It is the highest-value, most-commonly-wrong logic in the entire product category,
it needs no persistence, no UI and no network, and having it proven correct on day one is what
separates this app from the competitors that quietly report the wrong number.

**Do not start with the UI.** The screenshots are a strong, well-resolved design and it is tempting
to begin there. But every screen in them is a thin projection of the domain specified in this
blueprint, and building the projection before the thing being projected is how the fuel calculation
ends up in three ViewModels disagreeing with each other.
