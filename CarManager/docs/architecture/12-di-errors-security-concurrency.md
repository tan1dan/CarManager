# 12 · Dependency Injection · Error Handling · Security · Concurrency

---

# Part A — Dependency Injection

## 1. The mechanism: a plain composed container, no framework

```swift
struct AppDependencies: Sendable {
    // Persistence
    let vehicles: any VehicleRepository
    let odometer: any OdometerRepository
    let fuel: any FuelRepository
    let services: any ServiceRepository
    let expenses: any ExpenseRepository
    let reminders: any ReminderRepository
    let documents: any DocumentRepository
    let conversations: any AIConversationRepository
    let insights: any AIInsightRepository
    let inbox: any NotificationInboxRepository
    let scans: any ScanRepository

    // Ports
    let ai: any AIProvider
    let vision: any VisionAnalysisProvider
    let textRecognizer: any TextRecognizer
    let imagePreprocessor: any ImagePreprocessing
    let files: any FileStorage
    let notifications: any NotificationScheduling
    let auth: any AuthProviding
    let subscriptions: any SubscriptionProviding
    let exporter: any DocumentExporting
    let preferences: any PreferencesProviding
    let syncStatus: any SyncStatusProviding
    let connectivity: any ConnectivityProviding
    let telemetry: any TelemetryProviding
    let clock: any ClockProviding
    let ids: any IDGenerating

    static func live() throws -> AppDependencies
    static func preview(_ overrides: (inout AppDependencies) -> Void = { _ in }) -> AppDependencies
    static func testing(_ overrides: (inout AppDependencies) -> Void = { _ in }) -> AppDependencies
}
```

**No third-party DI library. No property-wrapper magic. No service locator. No singletons.**
`AppDependencies` is constructed exactly once, in `CarManagerApp.init()`. Everything else receives
what it needs.

Rejected alternatives:
- *Swinject / Factory / Needle* — runtime resolution converts a missing dependency from a compile
  error into a crash, for a solo-developer app with ~30 dependencies. Not worth it.
- *`@Environment`-only injection with `EnvironmentKey` per dependency* — 30 keys, each with a
  `defaultValue` that is either a fatal error or a silent stub. Both are bad.
- *Singletons (`.shared`)* — untestable, ordering-dependent, and forbidden by the brief.

## 2. How things receive dependencies

| Consumer | Mechanism |
|---|---|
| **Use cases** | Constructor injection of *only* what they use — `AddFuelEntry` takes 4 things, not 30 |
| **ViewModels** | Constructor injection of **use cases** + the global stores. Never a repository. |
| **Views** | `@Environment(\.dependencies)` — used **only** to construct child ViewModels via factories, never to call anything |
| **Global stores** | Constructed in `AppDependencies.live()` and held by `AppLifecycleCoordinator` |

```swift
// Feature-local factory keeps init lists out of call sites and keeps wiring in one place.
extension AppDependencies {
    @MainActor func makeFuelHistoryViewModel(vehicleID: VehicleID) -> FuelHistoryViewModel {
        FuelHistoryViewModel(
            loadHistory: LoadFuelHistory(repo: fuel),
            calculateStatistics: CalculateFuelStatistics(repo: fuel, gate: featureGate, clock: clock),
            deleteEntry: DeleteFuelEntry(fuel: fuel, odometer: odometer, files: files),
            router: router(for: .home)
        )
    }
}
```

Every ViewModel's dependency list is thus **visible and finite**, which is precisely what makes the
test setup `FuelHistoryViewModel(loadHistory: .fake, …)` a two-line affair.

## 3. Test and preview substitution

`AppDependencies.testing()` returns all-fake implementations with a mutation closure:

```swift
let deps = AppDependencies.testing {
    $0.clock = FixedClock(now: Date(timeIntervalSince1970: 1_760_000_000))
    $0.subscriptions = FakeSubscriptionProviding(entitlement: .premium)
}
```

`FixedClock` is the highest-leverage fake in the codebase: every reminder, expiry, analytics-period
and recurrence test becomes deterministic because **no production code calls `Date()`**.

---

# Part B — Error Handling

## 4. The error model

```swift
enum DomainError: Error, Sendable, Equatable {
    case validation(ValidationError)
    case persistence(PersistenceError)
    case network(NetworkError)
    case ai(AIError)
    case authentication(AuthenticationError)
    case subscription(SubscriptionError)
    case document(DocumentError)
    case sync(SyncError)
    case permission(PermissionError)
    case cancelled
    case unexpected(description: String)          // logged; never shown raw to a user
}
```

Each case is its own enum with **specific, actionable** cases — never a `message: String`:

```swift
enum ValidationError: Error, Sendable, Equatable {
    case emptyField(FieldID)
    case negativeAmount(FieldID)
    case nonPositiveVolume
    case futureDate(FieldID)
    case expirationBeforeStart
    case odometerRegression(previous: Double, attempted: Double)
    case invalidVIN
    case noServiceItems
    case nonPositiveInterval
    case triggerMismatch
}

enum PermissionError: Error, Sendable, Equatable {
    case cameraDenied, photoLibraryDenied, notificationsDenied, iCloudUnavailable
}
```

Typed cases carrying `FieldID` are what let the editor **highlight the offending field** instead of
showing a generic alert. A `String` message cannot do that, cannot be localised properly, and cannot
be asserted on in a test.

**Swift 6 typed throws** are used where the error surface is closed:
`func insert(_:) async throws(PersistenceError)`. Use cases that span families throw `DomainError`.

## 5. Warnings are not errors

Several rules must inform without blocking (`04`): odometer regression, price/total mismatch,
notification permission denied. These are returned **in the output**, not thrown:

```swift
struct AddFuelEntryOutput: Sendable { let entry: FuelEntry; let warnings: [DomainWarning] }
```

A thrown error means "the operation did not happen". Anything else is a warning. Conflating them is
how apps end up refusing to save a fill-up because the receipt rounded to the cent.

## 6. Error → presentation

```swift
enum ViewState<T: Sendable>: Sendable {
    case idle, loading
    case loaded(T)
    case failed(ErrorPresentation)
}

struct ErrorPresentation: Sendable, Equatable {
    let titleKey: LocalizedKey
    let messageKey: LocalizedKey
    let arguments: [String]
    let style: Style                   // .inline | .alert | .fullScreen | .toast | .fieldLevel(FieldID)
    let actions: [RecoveryAction]      // .retry | .openSettings | .upgrade(PaywallContext)
                                       // | .signIn | .dismiss | .contactSupport
}

@MainActor
struct ErrorPresenter {
    let telemetry: any TelemetryProviding
    func present(_ error: Error) -> ErrorPresentation
}
```

`ErrorPresenter` is the **single** mapping point, in Presentation. The Domain never knows a
localisation string, never knows what an alert is.

### 6.1 The mapping policy

| Domain error | Style | Actions |
|---|---|---|
| `.validation(.emptyField(f))` | `.fieldLevel(f)` | — (inline, as the user types) |
| `.permission(.cameraDenied)` | `.alert` | Open Settings |
| `.permission(.notificationsDenied)` | `.inline` banner | Open Settings, Dismiss |
| `.subscription(.requiresPremium)` / `.ai(.quotaExceeded)` | **not an error at all** | → `router.present(.paywall(context))` |
| `.ai(.offline)` | `.inline` in the composer | Retry when online |
| `.ai(.structuredOutputInvalid)` | `.inline` on the review screen | Retry scan, Enter manually |
| `.persistence(_)` | `.alert` | Retry, Contact Support (+ telemetry) |
| `.sync(_)` | `.toast`, never blocking | Dismiss |
| `.cancelled` | **swallowed** | none — user intent, not a failure |
| `.unexpected` | `.alert` generic copy | Contact Support (+ telemetry with full detail) |

Only `.unexpected` and `.persistence` reach `TelemetryProviding.recordError`. Logging expected
outcomes (cancellation, offline, quota, `.nothingToRestore`) as errors makes real crash reports
unreadable.

---

# Part C — Security

## 7. Storage matrix

| Data | Store | Protection |
|---|---|---|
| Auth access/refresh tokens | **Keychain** | `kSecAttrAccessibleAfterFirstUnlock`, **`kSecAttrSynchronizable = false`** (a refresh token must not roam) |
| Apple/Google identity tokens (transient) | Memory only | Exchanged and discarded |
| Passwords | **Never stored.** Sent once over TLS, exchanged for tokens | — |
| Units, currency, appearance, language, onboarding flag, default vehicle | **UserDefaults** | Non-sensitive |
| Cached entitlement + `lastVerifiedAt` | UserDefaults | Non-sensitive; server/StoreKit is authoritative |
| Vehicles, fuel, service, expenses, reminders, document metadata, conversations | **SwiftData** (+ CloudKit private DB) | File protection `.completeUntilFirstUserAuthentication` |
| Documents, photos, receipts | **File storage** (`11 §8`) | Same protection class |
| **VIN, license plate** | SwiftData | Treated as personal identifiers: **never sent to AI** (`08 §4.3`), never in telemetry, never in logs |
| API keys of any kind | **Nowhere in the client** | See §8 |

## 8. Secrets — the hard rules

1. **No AI provider key in the app.** Ever. Not in `Info.plist`, not obfuscated, not in the Keychain
   at first launch, not fetched-then-cached. The client calls **our backend**, which holds the key
   (`07 §5`). Any scheme that puts a provider key on the device is equivalent to publishing it.
2. **No Google OAuth client secret.** PKCE flow via `ASWebAuthenticationSession`; the code exchange
   happens on the backend (`06 §3.2`).
3. **No backend API key either.** The client authenticates with its **user session token**. There is
   no shared app-level secret to leak.
4. Anonymous users get a device-scoped token minted by the backend, rate-limited, and rotated. It
   grants only the free AI quota.
5. Certificate pinning: **deferred**, deliberately. It breaks under CDN rotation and is a common
   cause of app-wide outages. Revisit if the threat model changes.

## 9. Privacy

| Rule | Enforcement |
|---|---|
| **EXIF and GPS stripped from every image before upload** | `ImagePreprocessing.prepareForUpload` is the *only* path to the vision provider; the provider protocol takes `Data` that has already been through it |
| No VIN / plate / notes / workshop names in AI context | **Structural** — `AIVehicleContext.VehicleFacts` has no such fields (`08 §4.4`) |
| Backend stores no vehicle data | Stated non-responsibility (`07 §5`) |
| Telemetry is opt-in | Screenshot 21's `Analytics · On` toggle → `PreferencesProviding.telemetryEnabled`; `TelemetryService` is a no-op when false |
| Telemetry never carries user content | Event payloads are enums + counts. No free text, no IDs that map to content. |
| No card data is ever collected | Screenshot 21's "Payment method" **deep-links to the App Store billing page**. `PaymentMethodTag` (A-12) is a user-typed label with an optional last-4 the user chose to write; it is never validated, never transmitted, never sent to AI. |
| Required usage descriptions | `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`, and — importantly — **no** location or contacts permission is requested anywhere in this app |
| Data deletion | `DeleteAllData` wipes SwiftData, files, ubiquity container, pending notifications and the entitlement cache (`04 §11`) |

## 10. App Store / legal

- Privacy manifest (`PrivacyInfo.xcprivacy`) declaring `UserDefaults` API usage and any tracking
  domains (there are none if telemetry is first-party).
- Sign in with Apple is **mandatory** because Google sign-in ships (guideline 4.8).
- Account deletion is reachable in-app (guideline 5.1.1(v)) — `Settings → Account → Delete account`.
- Terms of Use and Privacy Policy are linked from Sign-up (screenshot 03), Profile and Settings, and
  the subscription paywall must show price, period, and auto-renewal terms plus both links
  (guideline 3.1.2).
- The AI disclaimers (`03 §6`) are a review consideration as well as an ethical one — automotive
  safety advice from a model needs an unmissable, acknowledged disclaimer.

---

# Part D — Concurrency (Swift 6, strict, language mode 6)

## 11. The isolation map

| Component | Isolation | Reason |
|---|---|---|
| Views | `@MainActor` (implicit) | UI |
| ViewModels | `@MainActor @Observable` | They mutate UI state directly; no hopping, no `await MainActor.run` |
| Global stores (5) | `@MainActor @Observable` | Read by UI on every frame |
| Use cases | **nonisolated `Sendable` structs** | Run wherever called from; they `await` into actors. They must NOT be `@MainActor` — that would drag repository work onto the main thread. |
| Domain calculators | **nonisolated, pure, synchronous** | No isolation needed; they can be called from anywhere, including inside actors |
| `PersistenceActor` | `@ModelActor` | The single owner of `ModelContext` (`07 §2`) |
| Repositories | `Sendable` structs over the actor | Cheap to copy, safe to pass |
| `StoreKitSubscriptionService` | `actor` | I/O + crypto off the main thread |
| `FileStorageActor` | `actor` | Serialises path access |
| `BackendAuthService` | `actor` | Coalesces token refresh (`06 §3.4`) |
| `AIProvider` implementations | `Sendable` structs | Stateless; `URLSession` handles its own concurrency |
| `NetworkMonitor`, `SyncStatusMonitor`, `ChangeFeed` | `Sendable` final classes wrapping `AsyncStream` | Bridge callback APIs into structured concurrency |

**All domain types are `Sendable` value types**, so nothing needs `@unchecked Sendable`. If a
`@unchecked` appears in a review, it is a design error, not a workaround.

## 12. Task ownership and cancellation

| Work | Owner | Cancellation |
|---|---|---|
| AI streaming | `AIChatViewModel.streamTask` | `.cancel()` on new turn / screen exit / Stop button; partial persisted (`08 §2.2`) |
| Screen loads | SwiftUI `.task` modifier | Automatic on disappear |
| Change-feed observation | ViewModel's `observationTask` | Cancelled in `deinit`/teardown |
| `Transaction.updates` | `Task.detached`, app-lifetime | Never cancelled while running (`10 §2.1`) |
| Sync monitoring, network monitoring | App-lifetime detached tasks | Never |
| OCR / image analysis | Awaited inside the use case | Propagates structured cancellation |
| PDF export | `Task(priority: .userInitiated)` | Cancellable from the progress UI |
| GC, insight refresh, reschedule | `Task(priority: .background)` at launch/foreground | Best-effort |

**Concurrency in `LoadHomeDashboard`:** a `withThrowingTaskGroup` fans out fuel statistics, analytics,
reminder evaluation, document expiries, recent activity and cached insights. Total latency is the
slowest child, not the sum — the difference between a Home screen that appears instantly and one that
visibly assembles.

## 13. `AsyncStream` usage, and where it is *not* used

| Stream | Producer | Consumer |
|---|---|---|
| `AsyncThrowingStream<AIStreamEvent>` | `AIProvider` | `AIChatViewModel` |
| `AsyncStream<EntityChange>` | `ChangeFeed` | Repositories → ViewModels |
| `AsyncStream<Entitlement>` | `SubscriptionProviding` | `EntitlementStore` |
| `AsyncStream<SyncState>` | `SyncStatusMonitor` | `SyncStatusStore` |
| `AsyncStream<Bool>` | `NetworkMonitor` | `ConnectivityStore` |
| `AsyncStream<PreferenceKey>` | `UserPreferencesStore` | Formatters, feature ViewModels |

Every stream that wraps a callback API sets `onTermination` to tear down its underlying observer.
A leaked `NSMetadataQuery` or `NWPathMonitor` is a real battery bug.

**Not used:** Combine (nothing needs it), `DispatchQueue` (nothing needs it), `NSOperationQueue`,
`@Published`, `ObservableObject`. The only `DispatchQueue` permitted anywhere is inside a
third-party API bridge we do not control, wrapped immediately into `async`.

## 14. Main-actor discipline

The rule that prevents the most common Swift 6 mistake in SwiftData apps:

> **Never make a use case or a repository `@MainActor` "to make the compiler happy."**

When a `@MainActor` ViewModel calls a nonisolated use case, the use case runs off the main actor,
awaits the persistence actor, and returns a `Sendable` value which the compiler hops back to the main
actor automatically. Annotating the use case `@MainActor` instead would run every fetch and every
mapping loop on the main thread — which compiles cleanly, passes tests, and drops frames on a real
garage.
