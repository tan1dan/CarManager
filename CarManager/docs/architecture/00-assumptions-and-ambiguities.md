# 00 · Ambiguities, Contradictions and Explicit Assumptions

> Read this first. Every decision in the rest of the blueprint depends on the assumptions
> resolved here. Each item has an ID (`A-xx`) referenced from the other documents.

---

## 1. Contradictions between the specification and the screenshots

### A-01 — The tab bar is not what the specification says

| Source | Primary sections |
|---|---|
| Specification | Home, Garage, AI, **Analytics**, **Settings** |
| Screenshots (02, 03, 04, 07, 08) | Home, Garage, **[+]**, AI, **Profile** |

**Resolution.** The screenshots win on *arrangement*, the specification wins on *scope*.

- `AppTab` = `.home`, `.garage`, `.ai`, `.profile`. The central `[+]` is **not a tab** — it is a
  modal presenter (`ModalRoute.quickLog`) rendered in the tab-bar slot.
- **Analytics is a full feature module**, not a tab. It is reachable from three entry points seen
  in the screenshots: Home stat cards (`This month €342`, `Avg L/100km 6.2`), Vehicle Detail →
  *Statistics*, and the Expenses overview (screen 13).
- **Settings is a route inside the Profile tab**, matching screens 08 and 21.
- `AppTab` is a single enum. Promoting Analytics to a fifth tab later is a one-line change plus a
  root-level tab-content switch. Nothing else in the architecture is coupled to the tab count.

### A-02 — "Profile" and "Settings" are two screens with overlapping content

Screen 08 (Profile) shows Language, Dark mode and Support. Screen 21 (Settings) shows Units,
Region, Time zone, Notifications, iCloud sync, Export, Version, Support.

**Resolution.** Profile is the *account + identity + subscription* surface. Settings is the
*preferences* surface pushed from Profile. Both read from the same `UserPreferencesStore`; neither
owns a mutable god-object. The Language/Dark-mode rows on Profile are shortcuts that write to the
same store (see `12-di-errors-security-concurrency.md`).

---

## 2. Product / technical contradictions requiring an architectural decision

### A-03 — Third-party auth vs. CloudKit data ownership  *(the most consequential one)*

The spec requires email/password and **Google Sign-In**. The spec also requires **iCloud sync**.
These two identities are not the same identity:

- CloudKit's private database is keyed to the **Apple ID signed into the device**. It cannot be
  keyed to a Google account or an app-managed email account.
- A user signing in with Google on a new device would find an empty garage, because CloudKit would
  hand them the private database of whatever Apple ID that device uses.

**Resolution — two identities, explicitly separated.**

| Identity | Owns | Backed by |
|---|---|---|
| **Data identity** | Vehicles, fuel, service, expenses, reminders, documents | Device iCloud account (CloudKit private DB) |
| **Account identity** | AI quota, subscription linkage, support, marketing email | Auth provider (Apple / Google / email) via the AI backend |

Consequences, which must be surfaced in the UI copy (not hidden):

1. Data follows the **iCloud account**, not the app account. Signing out of the app does not delete
   or move local data.
2. `AuthState` gates *AI and account features*; it does **not** gate the garage. A user can add a
   vehicle and log fuel before signing in (see A-04).
3. Account deletion deletes the **backend account** (AI history, quota, profile) and offers a
   separate, explicit "Delete all local & iCloud data" action. Two buttons, two confirmations.
4. If the product later requires "my garage follows my Google account", CloudKit must be replaced
   by a real backend. That is a **Phase 11+ rewrite of the Data layer only** — the Domain,
   Application and Presentation layers are unaffected because everything goes through repositories.

### A-04 — Onboarding order forces a local-first account model

Screen 01 offers "Get started" and "I already have an account", and the MVP list puts *Add Vehicle*
immediately after *Onboarding*. Requiring sign-in before the first vehicle would tank activation.

**Assumption.** The app supports a **`.anonymous` auth state** that is fully functional for all
local features. Sign-in is required only for: AI requests, subscription restore across devices, and
support. `AuthState = .restoring | .anonymous | .authenticated(UserProfile) | .signedOut`.

### A-05 — "iCloud Sync" is listed as a Premium feature. It should not be.

Gating `NSPersistentCloudKitContainer` behind a subscription requires two store configurations and a
destructive local↔cloud store migration whenever entitlement changes (purchase, lapse, refund,
Family Sharing revocation). That is one of the highest-risk pieces of code you can write, for a
feature users perceive as "my data isn't lost".

**Recommendation (opinionated).** Ship iCloud sync **free**. It is a data-safety feature, not a
value-add, and it costs you nothing per user. Replace it in the paywall with capabilities that are
genuinely marginal-cost or genuinely premium:

| Screenshot paywall claim | Keep? | Replacement / note |
|---|---|---|
| Unlimited vehicles | ✅ keep | Enforced by `FeatureGate` at `CreateVehicle` |
| Advanced AI scans & damage analysis | ✅ keep | Real marginal cost |
| iCloud sync & backup | ⚠️ **change** | Make free. Sell *"PDF & CSV export + full history"* instead |
| PDF export of history | ✅ keep | |
| Priority support | ✅ keep | |

If the business insists on gating sync, `PersistenceStack` already supports it — see
ADR-003 for the required (and unpleasant) migration design. The architecture does not prevent it;
this document recommends against it.

### A-06 — "Unlimited history" implies the free tier truncates history

Deleting or hiding a user's own records behind a paywall is hostile and creates a
data-loss support burden.

**Assumption.** Free tier **retains and displays all raw records** forever. The gate is applied to
*derived* surfaces only: free tier analytics and AI context are limited to a **rolling 12-month
window**. Implemented as `AnalyticsPeriod` clamping inside `FeatureGate`, not by deleting rows.

### A-07 — "Family Sharing"

Ambiguous between (a) StoreKit subscription Family Sharing and (b) sharing a vehicle's data with
family members via CloudKit sharing (`CKShare`).

**Assumption.** MVP means **(a)** — mark the subscription group as Family Shareable in App Store
Connect. `Entitlement.source` distinguishes `.direct` from `.familyShared` because restore and
revocation behave differently. **(b) is out of scope**; it would require moving records from the
private database to a shared zone and is a Phase 11+ project. The `Vehicle` model reserves an
`ownershipScope` field to make that migration additive.

### A-08 — Free-tier AI limits cannot be enforced on the client

`UsageCounter` in `UserDefaults` or SwiftData is trivially bypassed (reinstall, date change, jailbreak).

**Decision.** The **backend AI proxy is the authority** on AI quota. The client keeps a local
counter purely for optimistic UI ("3 of 5 requests left today") and always accepts the server's
`429 / quota_exceeded` as truth. `AIError.quotaExceeded(resetAt:)` is a first-class domain error
that routes to the paywall.

### A-09 — "Analytics" means two different things

The spec asks for an "Analytics" service protocol, an Analytics section, *and* screen 21 has a
`Analytics · On` toggle under DATA (product telemetry).

**Resolution — different names, no shared vocabulary:**

| Concept | Name in this architecture | Layer |
|---|---|---|
| Deterministic cost/consumption maths | `StatisticsEngine`, `AnalyticsReport` | Domain |
| Crash + product usage telemetry | `TelemetryService` | Infrastructure |

The word "Analytics" is never used for telemetry in code.

### A-10 — Mileage-based reminders cannot fire a local notification

`UNUserNotificationCenter` triggers on time, calendar, or location. There is no odometer trigger,
and the app cannot read the odometer in the background (no OBD in MVP).

**Decision.** Mileage triggers are **projected to a date** by `MileageProjector` using the vehicle's
observed average daily distance, and rescheduled on **every write that produces a new
`OdometerReading`**. In-app, `EvaluateReminderTriggers` runs on launch and foreground and is exact.
The notification is therefore an *estimate that converges*; copy must say "due in ~520 km", never a
false-precision date. See `11-notifications-and-files.md`.

### A-11 — "Fuel logged automatically" (screen 05, Alerts)

Implies an ingestion source the MVP does not have (bank/email/OBD integration).

**Assumption.** Out of MVP scope. The extension point is preserved:
`FuelEntry.source: RecordSource = .manual | .receiptScan | .imported | .automatic(providerID)`.
The alerts feed already renders any `AppNotification`, so adding the source later requires no
changes to Home, Alerts, or the notification model.

### A-12 — "Payment method · Visa ···4832" on Add Fuel and in Settings

Two different things, and one of them is a security trap.

- **Add Fuel → Payment**: a *user-defined label*. Modelled as `PaymentMethodTag { id, displayName,
  last4: String?, brand: PaymentBrand? }`, stored locally, **manually entered**, never a PAN, never
  validated against a card network, never sent to the AI. Purely for the user's own bookkeeping.
- **Settings → Payment method**: this is the **App Store** payment method. The row deep-links to
  `https://apps.apple.com/account/billing`. The app **never collects card data**. This is a hard
  rule in `12-di-errors-security-concurrency.md §Security`.

### A-13 — Multi-currency

`Money` carries a currency. Vehicles can be bought abroad; fuel can be bought abroad (the mock-ups
are Swedish with € pricing, which is itself a hint that currency is not fixed).

**Decision.** No FX conversion in MVP. `Money` is `(Decimal, CurrencyCode)`. `StatisticsEngine`
**refuses to sum across currencies**: it returns `AnalyticsReport.byCurrency: [CurrencyCode: Totals]`
plus a `mixedCurrencyWarning` flag. The UI shows the vehicle's primary currency and a disclosure
when other currencies exist. Silent summing of mixed currencies is the single most common
correctness bug in this app category; the type system prevents it here.

---

## 3. Additions found only in the screenshots (not in the written spec)

| # | Screenshot | Element | Architectural consequence |
|---|---|---|---|
| A-14 | 02 Home | `HEALTH 94%`, `Healthy` badge | New deterministic domain calculator `VehicleHealthScorer`. **Not AI.** Inputs: overdue reminders, expiring documents, service recency vs. schedule, consumption deviation vs. baseline. Output `VehicleHealth { score: Int, status: .healthy/.attention/.critical, contributingFactors: [HealthFactor] }`. Must be explainable — the factors drive the Home card and feed the AI context. |
| A-15 | 08 Add vehicle | `Scan license plate` | New use case `RecognizeLicensePlate` → `VehicleDraft` prefill. Uses on-device `Vision` text recognition + a plate-format validator per region. **No national registry lookup in MVP** (needs per-country paid APIs). Premium-gated. |
| A-16 | 07 Vehicle detail | `COLOR Nardo Grey`, `REGISTERED SE · 2021` | `Vehicle.color: String?`, `Vehicle.registrationCountry: RegionCode?`, `Vehicle.trim: String?` ("Quattro"). |
| A-17 | 15 Reminders | `NEXT UP` progress bar `82,120 → 82,540 km` | A mileage reminder needs a **baseline** odometer, not just a due odometer, to render progress. `Reminder.mileageTrigger = { baselineKm, intervalKm }`; `dueKm = baseline + interval`. Derived value object `ReminderProgress { fraction, remainingDistance, remainingDays }`. |
| A-18 | 15 Reminders | `Tire swap · Seasonal · Apr / Nov` | `RecurrenceRule` needs a `.seasonal(months: Set<Month>)` case. Cannot be expressed as `.everyMonths(n)`. |
| A-19 | 06 Documents | Search field; `PDF · 12 MB` | `DocumentQuery` with free-text search; `DocumentMetadata.fileSize`, `.mimeType`, `.pageCount`. |
| A-20 | 05 Fuel | Consumption sparkline with `+9%` | `ConsumptionTrend { points: [TrendPoint], deltaPercent: Double }` produced by `StatisticsEngine`, not by the view. |
| A-21 | 08 Profile | `1 Vehicle · 48 Fill-ups · 12 Services` | `UserStatistics` — cheap aggregate counts, separate from the heavy `AnalyticsReport`. |
| A-22 | 03 Sign up | "You get 7 days of Premium free" | StoreKit 2 **introductory offer**; requires `Product.SubscriptionInfo.isEligibleForIntroOffer` checks and eligibility caching in `EntitlementStore`. |
| A-23 | 20 Paywall | Monthly €4.99 / Yearly €39 | One subscription group, two products, yearly marked as the promoted plan. `ProductCatalog` is a static, typed enum — no string literals at call sites. |
| A-24 | 18 AI Chat | Header shows `Online` | Connectivity is surfaced. `NetworkMonitor` (NWPathMonitor) feeds a small global `ConnectivityState`; AI composer disables send and offers queueing when offline. |
| A-25 | 05 Alerts | `Clear` action, `TODAY` / `THIS WEEK` grouping | `AppNotification` is a **persisted domain entity** (an in-app inbox), distinct from the OS-scheduled `UNNotificationRequest`. Two different things with two different lifecycles. |
| A-26 | 11 Add Service | `INCLUDE` chips (Oil filter, Air filter…) | A service record has **multiple work items**, not one type. `ServiceRecord.items: [ServiceItem]` where `ServiceItem { type, name, partCost?, laborCost? }`. The single `type` in the spec becomes a derived `primaryType`. This matters: an oil change that also replaced the air filter must satisfy **both** the oil-change reminder and the filter reminder. |

---

## 4. Assumptions I am making without evidence

| ID | Assumption | Risk if wrong |
|---|---|---|
| A-27 | Deployment target **iOS 18.0+** | Below 18, SwiftData lacks `#Index`, history tracking, and several CloudKit fixes. If iOS 17 is required, ADR-002 changes materially. |
| A-28 | Single-user app; no collaboration in MVP | Contradicted only by a future reading of A-07(b) |
| A-29 | The AI backend is a thin proxy the developer will own (Cloudflare Worker / Vercel / small Swift service). It is **not** part of this deliverable. | If no backend is possible, AI must be dropped or moved to on-device Foundation Models with much weaker capability |
| A-30 | Odometer is entered in the vehicle's display unit, stored canonically in **kilometres**; volume canonically in **litres**; money as `Decimal` | Float storage would produce drifting totals |
| A-31 | The app is localised (screen 21 has Region/Language/Time zone). All domain errors carry localisation keys, never English strings | Retro-fitting localisation into error handling is expensive |

---

## 5. Things I am deliberately *not* building in MVP

Widgets, Live Activities, App Intents/Siri, watchOS, push notifications, OBD-II, CloudKit sharing,
receipt bank-import, national plate registries, FX conversion, in-app card collection.

Each has a named extension point documented in `18-risks-and-next-step.md §Extension Points`.
None of them add a single type to the MVP.
