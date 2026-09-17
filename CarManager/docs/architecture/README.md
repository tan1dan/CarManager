# AI Car Assistant — Architecture Blueprint

**Status:** design complete, ready for implementation · **Date:** 2026-09-06
**Scope:** architecture only. No UI, no layouts, no colours, no typography, no components.
**Stack:** Swift 6 · SwiftUI · Swift Concurrency · SwiftData · CloudKit · StoreKit 2

---

## Read in this order

| # | Document | Covers |
|---|---|---|
| 0 | [Ambiguities & Assumptions](00-assumptions-and-ambiguities.md) | **Start here.** Contradictions between the spec and the screenshots, and the 31 explicit assumptions (`A-01`…`A-31`) the rest of the blueprint depends on |
| 1 | [Executive Summary](01-executive-summary.md) | The 5 decisions that define the codebase, layer diagram, dependency rules |
| 2 | [Project Structure](02-project-structure.md) | Xcode tree, per-directory responsibilities, feature structure |
| 3 | [Domain Model](03-domain-model.md) | Entities, value objects, ERD, **the Expense decision**, **the Receipt state machine**, **the Disclaimer model** |
| 4 | [Use Cases](04-use-cases.md) | ~60 use cases with responsibility / input / output / dependencies / errors / business rules |
| 5 | [Repositories & Services](05-repositories-and-services.md) | All repository and port protocols, and what was deliberately *not* abstracted |
| 6 | [Navigation & App State](06-navigation-and-app-state.md) | Typed routes, route guards, deep links, the 5 global stores, authentication |
| 7 | [Persistence & Sync](07-persistence-and-sync.md) | SwiftData, offline-first, CloudKit, and why there is **no hand-rolled sync metadata** |
| 8 | [AI Architecture](08-ai-architecture.md) | Provider abstraction, streaming, context builder, **grounding enforcement** |
| 9 | [Analytics](09-analytics.md) | **The precise fuel-consumption algorithm**, cost per km, health score |
| 10 | [Subscription](10-subscription.md) | StoreKit 2, entitlements, the feature-gate capability system |
| 11 | [Notifications & Files](11-notifications-and-files.md) | Reminder scheduling separated from domain; document/file storage |
| 12 | [DI · Errors · Security · Concurrency](12-di-errors-security-concurrency.md) | Container, error taxonomy, secrets, Swift 6 isolation map |
| 13 | [Testing](13-testing.md) | Test architecture, fakes, and every required test suite |
| 14 | [Screen → Architecture Mapping](14-screen-mapping.md) | All 15 screenshot screens + 13 implied screens |
| 15 | [Data Flows](15-data-flows.md) | All 22 required flows |
| 16 | [Architecture Decision Records](16-adr.md) | 13 ADRs: decision · reason · alternative · why rejected |
| 17 | [Implementation Roadmap](17-roadmap.md) | 10 dependency-ordered phases |
| 18 | [Risks & Next Step](18-risks-and-next-step.md) | 12 risks, 10 accepted debts, extension points, **what to build first** |

---

## Where each of the 33 required output sections lives

| Required section | Document |
|---|---|
| 1 Executive Architecture Summary | `01 §1` |
| 2 Architecture Diagram | `01 §2` |
| 3 Dependency Rules | `01 §3` |
| 4 Project Structure | `02 §1–6` |
| 5 Feature Structure | `02 §7` |
| 6 Domain Model | `03 §1–2` |
| 7 Entity Relationship Model | `03 §3` |
| 8 Use Cases | `04` |
| 9 Repository Interfaces | `05 §1–2` |
| 10 Service Interfaces | `05 §3` |
| 11 Navigation Model | `06 §1` |
| 12 Application State | `06 §2` |
| 13 Authentication | `06 §3` |
| 14 Persistence | `07 §1–2` |
| 15 Offline-first Architecture | `07 §3` |
| 16 Cloud Sync | `07 §4–6` |
| 17 AI Architecture | `08 §1–3, §6–7` |
| 18 AI Context Architecture | `08 §4–5` |
| 19 Analytics Architecture | `09` |
| 20 Subscription Architecture | `10` |
| 21 Notification Architecture | `11` Part A |
| 22 Document/File Storage | `11` Part B |
| 23 Dependency Injection | `12` Part A |
| 24 Error Handling | `12` Part B |
| 25 Security | `12` Part C |
| 26 Concurrency | `12` Part D |
| 27 Testing | `13` |
| 28 Screen-to-Architecture Mapping | `14` |
| 29 Data Flow Diagrams | `15` |
| 30 Architecture Decision Records | `16` |
| 31 Implementation Roadmap | `17` |
| 32 Risks and Technical Debt | `18 §1–2` |
| 33 Recommended Next Step | `18 §5` |

---

## The architecture in one page

**Pattern.** Pragmatic Clean Architecture (Presentation → Application → Domain ← Data/Infrastructure)
with feature-based MVVM. Single target, folder discipline, enforced by an automated lint test suite.
Not TCA (dependency + ceremony cost for a solo dev); not plain MVVM (this app has real business
logic that four surfaces share).

**The five defining decisions**

1. **Domain is `Sendable` value types; SwiftData `@Model` never leaves `Core/Data`.** Forced by
   Swift 6 — `PersistentModel` is not `Sendable`. Buys a framework-free Domain that tests in
   microseconds. (`ADR-006a`)
2. **No unified Expense table — a `CostEntry` *projection* instead.** Fuel, service and expenses stay
   three normalised entities; `CostLedger` merges them for analytics. Each write flow produces
   exactly one record, so double-counting is structurally impossible. (`ADR-006b`, `03 §4`)
3. **`OdometerReading` is a first-class, append-only entity.** Current mileage is derived, never a
   mutable column. Kills both "editing an old entry corrupts current mileage" and CloudKit
   last-writer-wins clobbering the odometer. (`ADR-006c`)
4. **CloudKit mirroring is the entire sync layer — no `syncStatus`, no tombstones, no `remoteID`.**
   Those fields are correct for a custom backend and actively harmful with
   `NSPersistentCloudKitContainer`. The escape hatch is specified but not built. (`ADR-003`)
5. **A backend exists for exactly one thing: the AI.** It holds the model key, streams completions,
   and enforces quota. It stores **no** vehicle data. (`07 §5`)

**Three correctness guarantees made structural rather than editorial**

- A receipt scan **cannot** persist a financial record: `ScanReceipt` holds no financial repository,
  and `ConfirmedReceipt` cannot be constructed without a user review pass. (`03 §5`)
- The AI **cannot** surface a statistic we did not compute: insights citing an unknown `MetricID`,
  or restating a computed value incorrectly, are discarded before persistence. (`08 §5`)
- A damage estimate **cannot** be a guaranteed price and a scan result **cannot** lack a disclaimer:
  there is no `Money` field, only `CostEstimateRange`, and `AIDisclaimer` is non-optional. (`03 §6`)

**Start here:** [`18 §5 — Recommended Next Step`](18-risks-and-next-step.md#5-recommended-next-step).
