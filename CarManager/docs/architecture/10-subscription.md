# 10 · Subscription Architecture (StoreKit 2)

```
      StoreKit 2                Infrastructure               Application            Presentation
      ──────────                ──────────────               ───────────            ────────────
   Product / Transaction ─► StoreKitSubscriptionService ─► EntitlementStore ─► FeatureGate ─► ViewModels
   Transaction.updates ────►      (actor)                   (@MainActor         (@MainActor        │
                                       │                     @Observable)        @Observable)      │
                                       ▼                          │                   │            ▼
                                 ProductCatalog                   │                   └──► RouteGuard
                                 (typed IDs)              cached to preferences              (06 §1.3)
```

**No `View` imports StoreKit. No ViewModel imports StoreKit.** There is exactly one file in the app
with `import StoreKit`: `StoreKitSubscriptionService.swift` (plus `ProductCatalog` for the IDs).

---

## 1. Product catalog

```swift
enum ProductID: String, CaseIterable, Sendable {
    case monthly = "app.carassistant.premium.monthly"     // €4.99  (screenshot 20)
    case yearly  = "app.carassistant.premium.yearly"      // €39    "BEST · 2 months free"
}

enum ProductCatalog {
    static let subscriptionGroupID = "premium"
    static let all = ProductID.allCases
    static let promoted: ProductID = .yearly
}

struct SubscriptionProduct: Sendable, Hashable {          // domain type; NOT StoreKit.Product
    let id: ProductID
    let displayName: String
    let displayPrice: String                              // localised by StoreKit
    let period: SubscriptionPeriod
    let introOffer: IntroOffer?                           // A-22: "7 days free"
    let isEligibleForIntroOffer: Bool
    let relativeSavingsPercent: Int?                      // yearly vs 12× monthly, computed
}
```

Both products live in **one subscription group**, which is what makes upgrade/downgrade/crossgrade
work correctly and gives the user a single active subscription. **Family Sharing is enabled on the
group** (A-07). `displayPrice` always comes from StoreKit — never hard-coded, never formatted by us,
so the App Store's localised pricing and tax display are correct in every storefront.

---

## 2. `StoreKitSubscriptionService` — an actor

```swift
actor StoreKitSubscriptionService: SubscriptionProviding {
    private var cachedProducts: [ProductID: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private let continuation: AsyncStream<Entitlement>.Continuation

    func start()                                          // called ONCE, at app launch
    func products() async throws(SubscriptionError) -> [SubscriptionProduct]
    func currentEntitlement() async -> Entitlement
    func purchase(_ id: ProductID) async throws(SubscriptionError) -> PurchaseOutcome
    func restore() async throws(SubscriptionError) -> RestoreOutcome
    func isEligibleForIntroOffer(_ id: ProductID) async -> Bool
    nonisolated var entitlementUpdates: AsyncStream<Entitlement> { … }
}
```

An actor, not `@MainActor`: product loading, verification and entitlement derivation are I/O and
crypto, and none of it belongs on the main thread. Only the final `Entitlement` — a small value —
crosses to the main actor.

### 2.1 The transaction listener

```swift
func start() {
    updatesTask = Task.detached(priority: .background) { [weak self] in
        for await update in Transaction.updates {          // long-lived, survives the whole session
            await self?.handle(update)
        }
    }
}
```

Started in `AppLifecycleCoordinator` at launch, **before** any UI needs entitlement, and never
cancelled while the app is alive. This is what catches: Ask-to-Buy approvals, renewals, refunds,
Family Sharing grants and revocations, subscriptions purchased on another device, and offer-code
redemptions. Missing this listener is the classic StoreKit 2 bug that produces "I paid but the app
says free".

### 2.2 Verification is mandatory

```swift
private func handle(_ result: VerificationResult<Transaction>) async {
    guard case .verified(let transaction) = result else {
        telemetry.recordError(SubscriptionError.unverifiedTransaction, context: …)
        return                       // an UNVERIFIED transaction NEVER grants entitlement
    }
    await recomputeEntitlement()
    await transaction.finish()       // finish only AFTER the entitlement is persisted
}
```

### 2.3 Entitlement derivation

```swift
private func recomputeEntitlement() async -> Entitlement {
    var latest: Entitlement = .free
    for await result in Transaction.currentEntitlements {
        guard case .verified(let t) = result,
              let id = ProductID(rawValue: t.productID),
              t.revocationDate == nil else { continue }
        latest = Entitlement(
            tier: .premium,
            source: t.ownershipType == .familyShared ? .familyShared : .direct,
            expiresAt: t.expirationDate,
            willAutoRenew: /* from Product.SubscriptionInfo.Status */,
            isInBillingRetry: /* from renewal state */,
            lastVerifiedAt: clock.now
        )
    }
    return latest
}
```

Renewal state comes from `Product.SubscriptionInfo.Status`, which distinguishes `.subscribed`,
`.inGracePeriod`, `.inBillingRetryPeriod`, `.expired`, `.revoked`. **Grace period and billing retry
keep the user premium** — locking out a subscriber whose card is being retried is a support disaster
and an App Store review risk.

---

## 3. `EntitlementStore` — the single source of premium truth

```swift
@MainActor @Observable
final class EntitlementStore {
    private(set) var entitlement: Entitlement = .free
    private(set) var products: [SubscriptionProduct] = []
    private(set) var productLoadState: LoadState = .idle
    private(set) var aiUsage: AIUsageSnapshot = .unknown       // optimistic; server is authoritative

    private let service: any SubscriptionProviding
    private let preferences: any PreferencesProviding

    func bootstrap() async        // load cache → apply → refresh from StoreKit → observe updates
    func purchase(_ id: ProductID) async -> PurchaseOutcome
    func restore() async -> RestoreOutcome
}
```

**Offline entitlement policy.** On launch, the cached `Entitlement` from preferences is applied
*immediately* so gated screens render correctly before StoreKit responds. A cached premium
entitlement whose `lastVerifiedAt` is older than **7 days** and cannot be re-verified degrades to
free — a bounded grace window that protects both the airplane user and the app.

---

## 4. `FeatureGate` — the capability system

The pure rule lives in the Domain and is trivially testable:

```swift
enum FeatureGating {
    static func evaluate(
        _ feature: PremiumFeature,
        entitlement: Entitlement,
        usage: UsageSnapshot,
        authState: AuthStateKind,
        now: Date
    ) -> FeatureAccess
}
```

The Application layer wraps it with live state:

```swift
@MainActor @Observable
final class FeatureGate {
    private let entitlements: EntitlementStore
    private let auth: AuthSessionStore
    private let clock: any ClockProviding

    func evaluate(_ feature: PremiumFeature) -> FeatureAccess
    func canUse(_ feature: PremiumFeature) -> Bool           // convenience over .evaluate
    func requirePremium(_ feature: PremiumFeature) throws(SubscriptionError)   // for use cases
    func clampedPeriod(_ requested: AnalyticsPeriod) -> AnalyticsPeriod        // A-06
    func vehicleLimit() -> Int?                                                // 1 or nil
}
```

### 4.1 The gating matrix

| Feature | Free | Premium |
|---|---|---|
| `multipleVehicles` | `.locked(.requiresPremium)` when count ≥ 1 | `.allowed` |
| `aiChat` | `.allowedWithQuota(n/day)` — a genuine taste, not a wall | `.allowed` |
| `receiptScan`, `dashboardScan`, `damageAnalysis` | `.locked(.requiresPremium)` | `.allowed` |
| `plateScan` | `.locked` | `.allowed` |
| `aiInsights` | `.locked` | `.allowed` |
| `advancedAnalytics` | `.allowed` but period clamped to 12 months (A-06) | `.allowed` |
| `pdfExport` | `.locked` | `.allowed` |
| Fuel, service, expenses, reminders, documents, **iCloud sync** | `.allowed` | `.allowed` |

**Deliberate product position:** the free tier gets a small number of real AI chat messages rather
than zero. A user who has never seen the assistant answer a question about *their* car has no reason
to buy it. `.allowedWithQuota` exists in the type system precisely to express this.

### 4.2 Three enforcement points, no more

1. **`RouteGuard`** (`06 §1.3`) — navigation-time. Prevents reaching a locked screen at all.
2. **Use cases** — `try featureGate.requirePremium(.receiptScan)` as the first statement. This is the
   authoritative check; it catches deep links, notification taps, restored navigation state and
   programmatic paths that bypass the router.
3. **Presentation** — a lock badge / upsell row, driven by `FeatureAccess`, for *affordance* only.
   Never the enforcement.

A View asking "am I premium?" to decide whether to *call* something is the anti-pattern this
structure removes: the view asks only how to *render*.

---

## 5. Purchase and restore flows

```
PURCHASE
  Paywall (PaywallContext carries WHY it appeared — 06 §1.1)
   → EntitlementStore.purchase(id)
   → StoreKitSubscriptionService.purchase
   → Product.purchase()
       ├─ .success(verified)   → recompute entitlement → persist → transaction.finish()
       │                         → entitlementUpdates → EntitlementStore → FeatureGate
       │                         → router replays the pendingDestination that triggered the paywall
       ├─ .success(unverified) → SubscriptionError.unverifiedTransaction. No entitlement.
       ├─ .pending             → PurchaseOutcome.pending  (Ask to Buy). NOT an error.
       │                         Paywall shows "Waiting for approval"; Transaction.updates will
       │                         deliver the grant later, possibly days later, possibly after relaunch.
       └─ .userCancelled       → .userCancelled. No error surface, no telemetry noise.

RESTORE  (screenshot 20: "Restore purchase")
   → AppStore.sync()                          ← may prompt for the App Store password
   → recompute from Transaction.currentEntitlements
   → .restored(entitlement) | .nothingToRestore
   `.nothingToRestore` is a NEUTRAL outcome shown as an informational message, never an error alert.
```

**Post-purchase navigation:** the paywall stores the `pendingDestination` that caused it. On success
the router dismisses the paywall and replays that destination, so the user lands on the receipt
scanner they originally tapped — not back at Home.

---

## 6. AI quota (A-08)

```swift
struct AIUsageSnapshot: Sendable, Hashable {
    let used: Int
    let limit: Int?                 // nil = unlimited
    let resetsAt: Date
    let isAuthoritative: Bool       // true only when it came from the server
}
```

- The client keeps an optimistic local counter for responsive UI ("2 of 5 left today").
- **The backend is authoritative.** Every AI response carries the true remaining quota; a `429`
  produces `AIError.quotaExceeded(resetAt:)`, which overwrites the local counter and routes to
  `.paywall(.aiQuota(resetAt:))`.
- The local counter is never trusted to *grant* a request, only to *warn* before one.

---

## 7. Testing the subscription layer

| What | How |
|---|---|
| Entitlement derivation | `Configuration.storekit` + `SKTestSession`: purchase, renew, expire, refund, revoke |
| Family Sharing | `SKTestSession` ownership type `.familyShared` |
| Grace / billing retry | Test session renewal-state manipulation |
| Feature gating matrix | Pure unit tests over `FeatureGating.evaluate` — every feature × every tier × quota state. No StoreKit involved. |
| Route guarding | `RouteGuard` tests with a fake `FeatureGate` |
| Offline degradation | Fake `SubscriptionProviding` returning stale `lastVerifiedAt` |
| Paywall context attribution | Assert the correct `PaywallContext` for each lock reason |

The gating matrix — the part most likely to have a product bug — is tested entirely without StoreKit,
because `FeatureGating` is a pure function. That separation is the reason it is a pure function.
