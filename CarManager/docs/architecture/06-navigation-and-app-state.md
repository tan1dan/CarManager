# 06 · Navigation Model, Application State, Authentication

---

## 1. Navigation model

### 1.1 The route universe — one `Codable` enum tree

Everything is a value type, so navigation state is snapshot-able, restorable, deep-linkable and
testable **without instantiating a single View**.

```swift
enum AppTab: String, CaseIterable, Codable, Sendable, Hashable {
    case home, garage, ai, profile          // A-01. The [+] is NOT a tab.
}

/// Pushed destinations. One case set per tab stack, unified so deep links can target any of them.
enum AppRoute: Hashable, Codable, Sendable {
    // Garage / Vehicle
    case vehicleDetail(VehicleID)
    case vehicleEditor(VehicleEditorMode)          // .create | .edit(VehicleID)
    // Records
    case fuelHistory(VehicleID)
    case fuelEntryDetail(FuelEntryID)
    case serviceHistory(VehicleID, filter: ServiceHistoryFilter = .init())
    case serviceRecordDetail(ServiceRecordID)
    case expenses(VehicleID, period: AnalyticsPeriod = .year)
    case expenseDetail(ExpenseID)
    case documents(VehicleID?)
    case documentDetail(DocumentID)
    case reminders(VehicleID)
    case reminderDetail(ReminderID)
    // Analytics
    case analytics(VehicleID?, period: AnalyticsPeriod)
    case analyticsDetail(AnalyticsSection)         // .consumption | .costs | .categories | .ownership
    // AI
    case aiChat(ConversationID?)                   // nil = new conversation
    case aiInsightDetail(InsightID)
    case dashboardScanResult(UUID)
    case damageAnalysisResult(UUID)
    // Alerts
    case alerts
    // Profile / Settings
    case settings
    case settingsSection(SettingsSection)          // .units | .notifications | .data | .about | .account
    case manageVehicles
    case about
}

/// Sheets. Dismissible, non-committal, may stack (a paywall over an editor).
enum ModalRoute: Hashable, Codable, Sendable, Identifiable {
    case quickLog                                   // screenshot 04 — the [+] menu
    case fuelEditor(FuelEditorMode)
    case serviceEditor(ServiceEditorMode)
    case expenseEditor(ExpenseEditorMode)
    case reminderEditor(ReminderEditorMode)
    case documentPicker(vehicleID: VehicleID?)
    case vehiclePicker                              // switch active vehicle
    case paywall(PaywallContext)                    // carries WHY it appeared
    case disclaimerAcknowledgement(DisclaimerKind)
    case receiptReview(ReceiptScanID)               // the review step — a sheet, never auto-saved
    case shareExport(URL)
    case legal(LegalDocument)                       // .privacyPolicy | .termsOfUse
    var id: Self { self }
}

/// Full-screen covers. Immersive or blocking flows.
enum FullScreenRoute: Hashable, Codable, Sendable, Identifiable {
    case onboarding
    case authentication(AuthEntryPoint)             // .signIn | .signUp
    case camera(CameraPurpose)                      // .receipt | .dashboard | .damage | .plate | .vehiclePhoto
    case documentViewer(DocumentID)                 // QuickLook
    var id: Self { self }
}

/// The single addressable unit for deep links, notifications and tests.
struct AppDestination: Hashable, Codable, Sendable {
    var tab: AppTab?
    var path: [AppRoute]
    var modal: ModalRoute?
    var fullScreen: FullScreenRoute?
}
```

**`PaywallContext` carries the trigger** — `.vehicleLimit`, `.aiQuota(resetAt:)`, `.feature(.receiptScan)`,
`.settingsUpgrade` — so the paywall can lead with the relevant benefit and so conversion can be
attributed per trigger. A context-free paywall is a wasted paywall.

### 1.2 Routers

```swift
@MainActor @Observable
final class TabRouter {
    let tab: AppTab
    private(set) var path: [AppRoute] = []
    func push(_ r: AppRoute); func pop(); func popToRoot(); func replace(with: [AppRoute])
}

@MainActor @Observable
final class AppRouter {
    private(set) var selectedTab: AppTab = .home
    private(set) var modalStack: [ModalRoute] = []       // an array: paywall CAN cover an editor
    private(set) var fullScreen: FullScreenRoute?
    let routers: [AppTab: TabRouter]

    private let guardEvaluator: RouteGuard

    /// THE single entry point. Every navigation in the app goes through here.
    func navigate(to destination: AppDestination) { … }
    func present(_ modal: ModalRoute) { … }
    func dismissModal(); func dismissAll()
    func handle(_ deepLink: URL)
    func handle(notificationResponse: NotificationPayload)
}
```

SwiftUI binds `NavigationStack(path:)` to `TabRouter.path` and `.sheet(item:)` /
`.fullScreenCover(item:)` to the router's published values. **Views never construct a destination
themselves and never call `dismiss()` for flow control** — they call router intents. That is what
makes flows testable without UI.

### 1.3 Route guards — where auth and premium gating actually live

```swift
@MainActor
struct RouteGuard {
    let auth: AuthSessionStore
    let featureGate: FeatureGate

    enum Decision { case allow, redirect(AppDestination), present(ModalRoute) }

    func evaluate(_ destination: AppDestination) -> Decision
}
```

Rules, in order:

1. **Onboarding not completed** → `redirect(.fullScreen(.onboarding))`. Everything else is blocked.
2. **Destination requires an account** (`.aiChat`, `.settingsSection(.account)`) **and state is
   `.anonymous`** → `present(.authentication(.signIn))`, and the original destination is stored as
   `pendingDestination`, replayed on success. This is the "authentication redirect" requirement.
3. **Destination requires premium** → `featureGate.evaluate(feature)`:
   - `.allowed` / `.allowedWithQuota` → `allow`
   - `.locked(reason)` → `present(.paywall(context(from: reason)))`
4. **Destination requires a selected vehicle** (most record routes) and none exists →
   `redirect(.garage + .vehicleEditor(.create))`.
5. **Destination requires disclaimer acknowledgement** (`.camera(.dashboard)`, `.camera(.damage)`)
   → `present(.disclaimerAcknowledgement(kind))`, replayed on acknowledgement.

Because `RouteGuard` is a pure-ish function over value types, the entire gating matrix is unit-tested
with no UI: *"an anonymous free user tapping Scan Receipt from a deep link sees the paywall, not the
camera."*

### 1.4 Deep links

Scheme `carmanager://`, plus Universal Links later.

| URL | Destination |
|---|---|
| `carmanager://vehicle/<uuid>` | `.garage` + `[.vehicleDetail(id)]` |
| `carmanager://vehicle/<uuid>/fuel/add` | `.home`, modal `.fuelEditor(.create(vehicleID))` |
| `carmanager://reminder/<uuid>` | `.home` + `[.reminders(vid), .reminderDetail(id)]` |
| `carmanager://document/<uuid>` | `.home` + `[.documents(vid), .documentDetail(id)]` |
| `carmanager://ai/chat?conversation=<uuid>` | `.ai` + `[.aiChat(id)]` |
| `carmanager://alerts` | `.home` + `[.alerts]` |
| `carmanager://premium?source=…` | modal `.paywall(context)` |
| `carmanager://settings/units` | `.profile` + `[.settings, .settingsSection(.units)]` |

`DeepLinkParser` is pure: `URL → AppDestination?`. Notification payloads carry a `Codable`
`AppDestination` in `userInfo`, so **a notification tap and a URL take the identical code path** —
one parser, one guard evaluation, one navigate call. No duplicated routing logic.

### 1.5 The `[+]` central action

`ModalRoute.quickLog` presents screenshot 04's menu. Each row dispatches `router.present(...)` for a
subsequent modal, and the guard runs per row — so *Scan Receipt* shows the paywall for a free user
while *Add Fuel* opens the editor. The quick-log sheet is dismissed as the next sheet is presented
(`modalStack` replacement, not stacking, for this specific transition).

### 1.6 State restoration

`AppRouter` encodes `AppDestination` to `SceneStorage`. On relaunch it decodes, re-runs
`RouteGuard.evaluate` (entitlement or auth may have changed since), and navigates. Restoring into a
now-locked premium screen therefore lands on the paywall rather than a broken screen.

---

## 2. Application state — what is global and what is not

**Rule: something is global only if two or more unrelated features must observe it and it changes
outside their control.** Five things qualify. Everything else is feature-local.

### 2.1 The five global stores

| Store | Type | Owns | Why global |
|---|---|---|---|
| `AuthSessionStore` | `@MainActor @Observable` | `AuthState`, `UserProfile?` | Root view, route guard, AI, profile |
| `SelectedVehicleStore` | `@MainActor @Observable` | `selectedVehicleID`, cached `Vehicle`, `[VehicleSummary]` | Home, Garage, every editor, AI context |
| `EntitlementStore` | `@MainActor @Observable` | `Entitlement`, `[SubscriptionProduct]`, intro eligibility | Route guard, paywall, profile, every gated feature |
| `SyncStatusStore` | `@MainActor @Observable` | `SyncState` | Settings, a global status badge |
| `ConnectivityStore` | `@MainActor @Observable` | `isOnline` | AI composer ("Online" chip, A-24), sync UI |

```swift
enum AuthState: Sendable, Equatable {
    case restoring                       // launch, before Keychain check. Root shows a splash.
    case anonymous                       // A-04. FULLY FUNCTIONAL for local features.
    case authenticated(UserProfile)
    case signedOut                       // explicit sign-out; distinct from .anonymous for copy
}

enum SyncState: Sendable, Equatable {
    case unavailable(reason: CloudUnavailableReason)   // no iCloud account, disabled by user
    case idle(lastSyncedAt: Date?)
    case syncing(progress: Double?)
    case failed(SyncError, willRetry: Bool)
}
```

### 2.2 `SelectedVehicleStore` — the ActiveVehicle concept, decoupled from UI

This is the spec's explicit requirement. It lives in **Application**, imports only `Foundation` +
`Observation`, and has no idea SwiftUI exists.

```swift
@MainActor @Observable
final class SelectedVehicleStore {
    private(set) var summaries: [VehicleSummary] = []
    private(set) var selected: Vehicle?
    private(set) var state: LoadState = .loading

    private let vehicleRepo: any VehicleRepository
    private let preferences: any PreferencesProviding
    private var observationTask: Task<Void, Never>?

    func bootstrap() async                       // load, resolve selection, start change observation
    func select(_ id: VehicleID) async           // updates preferences.defaultVehicleID
    func refresh() async
}
```

**Selection resolution order** (deterministic, tested):
1. `preferences.defaultVehicleID` if it still exists
2. else the vehicle with `isDefault == true`
3. else the most recently updated vehicle
4. else `nil` → empty-garage state

It subscribes to `vehicleRepo.changes` so a CloudKit merge that deletes the selected vehicle on
another device re-resolves selection automatically rather than crashing on a dangling ID.

### 2.3 What is deliberately NOT global

| Not global | Where it lives | Why |
|---|---|---|
| Analytics period picker | `AnalyticsViewModel` | One screen's filter |
| Expenses year selector (screen 13) | `ExpensesViewModel` | ditto |
| Draft form state for every editor | The editor's ViewModel | Discarded on cancel |
| Fuel history pagination cursor | `FuelHistoryViewModel` | |
| AI streaming buffer & partial text | `AIChatViewModel` | Belongs to one conversation |
| Receipt scan state machine instance | `ReceiptScanViewModel` (definition in Domain) | One flow |
| Camera permission prompt state | The camera feature | |
| Unit system / currency / appearance | `PreferencesProviding` | **Not a store** — a persisted settings service. Features read it through their `Formatter`. This is the spec's "separate user preferences from application state". |
| Onboarding completion | `PreferencesProviding` | A durable flag, not live state |

**There is no `AppState` type in this codebase.** Five small stores with narrow, testable
responsibilities, each independently fakeable.

---

## 3. Authentication

### 3.1 The identity split (A-03) restated as architecture

```
┌───────────────────────────┐         ┌────────────────────────────┐
│  ACCOUNT identity         │         │  DATA identity             │
│  Apple / Google / email   │         │  device iCloud account     │
│  ↓                        │         │  ↓                         │
│  AuthSessionStore         │         │  CloudKit private database │
│  Keychain (tokens)        │         │  SwiftData + mirroring     │
│  Gates: AI, support,      │         │  Gates: nothing            │
│         cross-device      │         │                            │
│         subscription      │         │  Sign-out does NOT touch   │
│         restore           │         │  this. Ever.               │
└───────────────────────────┘         └────────────────────────────┘
```

### 3.2 Provider strategy

`AuthProviding` has one live implementation, `BackendAuthService`, which delegates credential
acquisition to three strategies:

| Strategy | Mechanism | Notes |
|---|---|---|
| Apple | `AuthenticationServices` / `SignInWithAppleButton` | Yields an identity token, exchanged at the backend for our session. **Mandatory** if Google or email sign-in ships (App Review guideline 4.8). |
| Google | **`ASWebAuthenticationSession` + PKCE — not the Google SDK** | Avoids a heavyweight closed-source dependency, avoids its `UIViewController` coupling, keeps the client secret on the backend. The SDK buys convenience we don't need. |
| Email | Backend endpoints | Password **never** stored locally. Sent once over TLS, exchanged for tokens. |

All three return an `AuthSession { accessToken, refreshToken, expiresAt, profile }`. Tokens go to the
**Keychain** (`kSecAttrAccessibleAfterFirstUnlock`, no iCloud Keychain sync for refresh tokens).

### 3.3 Session restoration (launch)

```
launch → AuthState = .restoring          (root shows splash; does NOT block the garage)
       → RestoreSession
           Keychain read
             ├─ none                     → .anonymous
             ├─ valid                    → .authenticated(profile)
             └─ expired → refresh
                           ├─ ok         → .authenticated(profile)
                           └─ fail       → .anonymous   (never an error screen)
```

Restoration is **non-blocking**: `RootView` renders the tab bar and Home as soon as
`SelectedVehicleStore.bootstrap()` completes, independently of auth. A network hiccup at launch must
never keep a user out of their own offline data.

### 3.4 Token refresh under concurrency

`BackendAuthService` is an **actor**. Concurrent 401s from parallel AI requests coalesce into a
single refresh via a stored `Task<AuthSession, Error>`; late callers await the in-flight task. This
prevents the classic refresh-token stampede that invalidates the token for everyone.

### 3.5 Sign-out and account deletion (two separate, differently-scoped operations)

| Action | Clears Keychain | Clears local data | Clears iCloud data | Deletes backend account |
|---|---|---|---|---|
| **Sign out** | ✅ | ❌ | ❌ | ❌ |
| **Delete account** | ✅ | ❌ | ❌ | ✅ |
| **Delete all data** *(separate button, typed confirmation)* | ❌ | ✅ | ✅ | ❌ |

Both destructive actions require re-authentication and a second confirmation. The UI must state
plainly that deleting the account does not delete the garage, and vice versa — the consequence of
A-03, surfaced honestly rather than hidden.
