# 07 · Persistence, Offline-First, Cloud Sync

---

## 1. The persistence decision

**SwiftData, backed by its private SQLite store, mirrored to the CloudKit private database by
`NSPersistentCloudKitContainer`.** No custom backend for user data.

| Option | Assessment |
|---|---|
| **SwiftData** ✅ | Apple-native, `@Model` macro, `#Index`, `SchemaMigrationPlan`, one-flag CloudKit mirroring, and — decisively — first-class Swift 6 concurrency via `@ModelActor`. Its historical rough edges (predicate limitations, migration gaps) are largely resolved at iOS 18 (A-27). |
| **Core Data** ❌ | Everything SwiftData has, plus `NSManagedObject` subclassing and KVO ceremony, plus a worse strict-concurrency story. SwiftData *is* Core Data with a better front end; picking Core Data means opting into the boilerplate without gaining anything this app needs. |
| **Raw SQLite / GRDB** ❌ | Better query power and observability, genuinely tempting for the analytics workload. Rejected because it forfeits CloudKit mirroring entirely — sync would become a hand-written project bigger than the rest of the app, for a solo developer. |
| **CloudKit as the primary store** ❌ | Not offline-first. Every read becomes a network round trip with a local cache you end up writing anyway. |
| **Custom backend as the primary store** ❌ | Server cost, ops burden, GDPR data-controller obligations, auth complexity — for an app whose data is single-user and private by nature. |

→ ADR-002

### 1.1 The `@Model` ↔ `struct` boundary (the rule that shapes everything)

```
SwiftData layer                 mapping                Domain layer
─────────────────               ───────                ────────────
@Model final class SDFuelEntry  ◄────FuelEntryMapper──► struct FuelEntry: Sendable
· reference type                                        · value type
· NOT Sendable                                          · Sendable
· bound to a ModelContext                               · context-free
· lives only inside                                     · crosses actors freely
  PersistenceActor
```

**Why this is not dogma.** In Swift 6 strict concurrency, `PersistentModel` is not `Sendable`.
Returning `SDFuelEntry` from an actor is a compile error; the only way to "make it work" is
`@unchecked Sendable`, which converts a compile error into a data race and eventually a crash
inside Core Data. Mapping to structs is the *supported* pattern, and it happens to give us a Domain
layer that tests in microseconds with no container. → ADR-006

Cost: ~15 mapper files, ~40 lines each, purely mechanical, generated once. That is the entire price.

### 1.2 CloudKit-imposed schema constraints (non-negotiable)

Every `@Model` in this app must obey, or mirroring silently fails at container init:

1. **Every property is optional or has a default value.** Non-optional required domain fields
   (`Vehicle.brand`) become `var brand: String = ""` in the `@Model` and are guaranteed non-empty by
   the domain validator + mapper, which throws on an invalid row rather than surfacing `""`.
2. **No `@Attribute(.unique)`.** Uniqueness is enforced in use cases and by UUID primary keys.
3. **All relationships are optional and have inverses.**
4. **No `.deny` delete rules.** `.cascade` and `.nullify` only — which is exactly what `03 §3.1`
   specifies.
5. **No `Codable` enums stored raw** — enums are persisted as `String`/`Int` raw values with a
   `nil`-safe mapping so an unknown future case decodes to `.other` instead of failing.

A `SchemaCloudKitCompatibilityTests` suite asserts all of the above by reflection, so a
non-compliant property is caught by a unit test rather than by a user's empty garage.

### 1.3 Indices

```swift
#Index<SDFuelEntry>([\.vehicleID, \.date], [\.vehicleID, \.odometerValue])
#Index<SDServiceRecord>([\.vehicleID, \.date], [\.vehicleID, \.odometerValue])
#Index<SDExpense>([\.vehicleID, \.date], [\.vehicleID, \.categoryRaw])
#Index<SDOdometerReading>([\.vehicleID, \.recordedAt])
#Index<SDDocumentMetadata>([\.vehicleID, \.expirationDate])
#Index<SDReminder>([\.vehicleID, \.isActive])
```

These are chosen from the actual query set: consumption segmentation sorts by
`(vehicleID, odometer)`; every history list sorts by `(vehicleID, date)`; the expiry sweep scans
`(vehicleID, expirationDate)`.

### 1.4 Migrations

`SchemaV1` and an empty `MigrationPlan` exist **from the first commit**. Adding a versioned schema
after shipping is far more expensive than starting with one. Lightweight migrations for additive
changes; custom stages for anything that reinterprets data.

---

## 2. Concurrency model for persistence

```swift
@ModelActor
actor PersistenceActor {
    // The ONE place a ModelContext exists at runtime. Every write is serialised here.
    func transaction<T: Sendable>(_ body: (ModelContext) throws -> T) throws -> T
}
```

- **One actor, one context, one writer.** No `context.mainContext` usage in views (there is no
  `@Query`, so there is no need).
- Repositories are `Sendable` structs holding the actor. They `await` into it, map inside, and return
  values out.
- **Reads that back the UI go through the actor too.** The alternative — a main-context read path —
  reintroduces `@Model` objects on the main actor and with them the whole `Sendable` problem.
- Batch operations (import, delete-all, GC) run in a single transaction to avoid thousands of
  individual CloudKit records.

### 2.1 The change feed (replacing `@Query`)

```swift
final class ChangeFeed: Sendable {
    /// Bridges ModelContext.didSave + .NSPersistentStoreRemoteChange into structured concurrency.
    var stream: AsyncStream<EntityChange> { get }
}
```

`NSPersistentStoreRemoteChange` is what fires when **CloudKit merges a change from another device**.
Wiring it into the same feed means a fuel entry added on an iPad appears on the iPhone with no extra
code path. Repositories filter the feed to their own entity and re-emit on `changes`; ViewModels
`for await` and re-fetch, debounced at ~250 ms to coalesce sync bursts.

→ ADR-002 covers why `@Query` was rejected despite being the idiomatic SwiftUI choice.

---

## 3. Offline-first architecture

### 3.1 The contract

> **No user-initiated write ever awaits the network. No screen except AI shows a spinner that
> depends on connectivity.**

```
User taps Save
   │
   ├─► ViewModel.state = .saving          (local, instant)
   ├─► UseCase validates                  (pure, µs)
   ├─► Repository → PersistenceActor      (SQLite write, ms)
   ├─► NotificationScheduler reschedules  (local, ms)
   ├─► ViewState updated, sheet dismissed ◄── USER IS DONE HERE
   │
   ⋮ asynchronously, invisibly ⋮
   └─► NSPersistentCloudKitContainer exports to iCloud when it feels like it
           └─► SyncStatusMonitor → SyncStatusStore → a small badge in Settings
```

### 3.2 What degrades offline, and how

| Feature | Offline behaviour |
|---|---|
| Home, Garage, Fuel, Service, Expenses, Reminders, Analytics | **Fully functional.** All computed locally. |
| Documents | Metadata fully available. A file not yet downloaded shows `FileAvailability.remote` with a tap-to-download affordance — never a broken viewer. |
| AI Chat | Composer disabled with an explicit "Offline" state (A-24). The transcript is fully readable. Optionally, the typed message is kept as a draft and offered for send on reconnect. |
| Receipt / Dashboard / Damage scan | Capture and **on-device OCR still work**; the AI step is queued or the user is told to retry. The captured image is never lost. |
| AI Insights | Cached insights render with their `generatedAt` date shown. |
| Paywall | Cached `[SubscriptionProduct]` renders; purchase requires network (StoreKit's own error is surfaced). |
| Entitlement | Cached in preferences with `lastVerifiedAt`. **A lapsed cache does not revoke access offline** — we grant a 7-day grace window rather than locking a paying user out on a plane. |

---

## 4. Cloud sync

### 4.1 What we build vs. what CloudKit builds

| Concern | Owner |
|---|---|
| Record upload/download, change tokens, batching, retry, throttling | **CloudKit / NSPersistentCloudKitContainer** |
| Conflict resolution | **CloudKit** (last-writer-wins, field-level merge from history) |
| Delete propagation | **CloudKit** |
| Schema deployment (dev → prod) | Manual, via CloudKit Dashboard, per release. **A release checklist item.** |
| Sync *status observation* | **Us** — `SyncStatusMonitor` |
| **File blob sync** | **Us** — `FileSyncCoordinator` (`11 §File storage`) |
| **Orphan file GC** | **Us** |
| Account-availability handling | **Us** — `CKAccountStatus` → `SyncState.unavailable` |

```swift
final class SyncStatusMonitor: Sendable {
    // Observes NSPersistentCloudKitContainer.eventChangedNotification
    // → .setup / .import / .export events with succeeded + error
    // → maps to SyncState, exposed as AsyncStream
}
```

### 4.2 Conflict resolution — and why the model makes it a non-issue

CloudKit mirroring resolves conflicts last-writer-wins. That is dangerous for **mutable scalar fields
that two devices race on**. This app has almost none, by design:

| Data | Conflict risk | Mitigation |
|---|---|---|
| Fuel/Service/Expense/Document rows | **None.** Different UUIDs, append-only in practice | — |
| `OdometerReading` | **None.** Append-only rows, never a contested field (`03 §2.2`) | The design *is* the mitigation |
| `Vehicle.isDefault` | Real: two devices could each set a different default | Converges: `SelectedVehicleStore` re-resolves after each merge; if >1 default is observed, the most recently `updatedAt` wins deterministically and the others are cleared |
| `Reminder.lastCompletedAt` | Real but benign | Later timestamp wins; a duplicate completion at worst pushes the next due date out once |
| Same record edited on two devices | LWW on the whole record | Accepted. Single-user app; the window is seconds. Not worth CRDTs. |

**Deliberate decision: no custom merge policy, no vector clocks, no CRDTs.** The model was shaped so
the default policy is safe, which is far cheaper than making a sophisticated policy correct.

### 4.3 Sync status surfaces

`SyncState` appears in exactly two places: the Settings → Data section ("Last synced 2 minutes ago"),
and a transient banner when `.failed` with a non-retryable reason (e.g. iCloud storage full, iCloud
signed out). It **never** blocks a screen, never shows a modal spinner, never gates a save button.

---

## 5. Does a backend need to exist?

**Yes — but only for AI. Never for user data.**

### Backend responsibilities (specified, not implemented)

| # | Responsibility | Why it cannot live in the client |
|---|---|---|
| 1 | **Hold the AI model-provider API key** | A key in an IPA is a public key. This is the single non-negotiable reason a backend exists. |
| 2 | **Proxy + stream chat completions (SSE)** | Follows from (1) |
| 3 | **Proxy vision analysis** (receipt / dashboard / damage) | Follows from (1) |
| 4 | **Enforce AI quota per account** (A-08) | Client-side counters are trivially bypassed |
| 5 | **Verify App Store transactions server-side** (`/verify`) | Ties the premium AI quota to a real subscription; prevents a jailbroken client from claiming premium |
| 6 | **Account identity**: email/password, Google OAuth token exchange, account deletion | Google's client secret cannot ship in the app |
| 7 | **Prompt & system-instruction versioning** | Lets prompts be fixed without an App Store release — a genuinely large operational win |
| 8 | **Abuse rate-limiting, cost control, provider failover** | Protects the developer's spend |

### Explicit non-responsibilities

The backend **never** stores vehicles, fuel entries, service records, expenses, documents, receipts,
VINs, license plates, or conversation transcripts. Images sent for analysis are processed and
**discarded within the request**, never persisted. This keeps the app's data-controller footprint
minimal, makes the privacy policy short and honest, and means a backend breach exposes nothing about
anyone's car.

Deployment shape: a single stateless function (Cloudflare Worker / Vercel / a small Swift service)
plus a managed database holding only `{ userID, authProvider, subscriptionStatus, quotaCounters }`.

---

## 6. Sync metadata — what we deliberately do NOT build (and what we would)

The specification asks about `localID`, `remoteID`, `updatedAt`, `deletedAt`, `version`,
`syncStatus`. Here is the explicit position.

### 6.1 Not built, with reasons

| Field | Verdict |
|---|---|
| `localID` / `remoteID` | ❌ Two ID systems, two sources of truth. `UUID` primary keys are already globally unique; CloudKit derives its record names from `PersistentIdentifier`. |
| `version` | ❌ Its only purpose is optimistic-concurrency detection, and the mirroring layer resolves conflicts before we could ever inspect a version. Dead weight. |
| `syncStatus` | ❌ **The critical one.** `NSPersistentCloudKitContainer` does not expose per-row sync state and does not consult ours. A `syncStatus` column would be written by us, never updated by the framework, and would lie within seconds — worse than no field at all. |
| `deletedAt` (tombstones) | ❌ CloudKit propagates deletes natively. Tombstones would add a `deletedAt == nil` clause to every predicate in the app, which will be forgotten somewhere, producing ghost rows in exactly one analytics query. |
| `createdAt` / `updatedAt` | ✅ **Built** — but for domain reasons (sorting, "recent activity", conflict *inspection* during support), not for sync. |

### 6.2 The escape hatch, specified for the day it is needed

If A-03 is ever resolved in favour of a real backend (data must follow a Google account, or team/
family data sharing ships), this is the migration target:

```swift
struct SyncMetadata: Hashable, Sendable, Codable {
    var remoteID: String?
    var lastSyncedAt: Date?
    var localVersion: Int          // bumped on every local mutation
    var remoteVersion: Int?        // last version acknowledged by the server
    var syncStatus: SyncStatus     // .synced | .pendingUpload | .pendingDelete | .conflicted
    var deletedAt: Date?           // tombstone; purged after the server confirms
}
```

Migration cost, honestly stated: one additive schema version, one `SyncCoordinator` actor, one
outbox table, one conflict-resolution policy per entity. It touches **only `Core/Data`**. The Domain,
Application and Presentation layers require **zero** changes — which is precisely the payoff of the
repository boundary, and the reason we can afford to defer this decision rather than pre-build it.

→ ADR-003
