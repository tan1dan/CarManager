# 14 · Screen → Architecture Mapping

Every screen visible in the supplied screenshots, mapped to its architectural components.
**No UI is specified here** — no layout, no colour, no typography, no components. Only which
feature, presentation model, ViewModel, use cases, repositories, services, domain models and
navigation destination each screen is built from.

Legend: `PM` = presentation model · `VM` = ViewModel · `UC` = use cases · `R` = repositories ·
`S` = services/ports · `D` = domain models · `→` = navigation destination.

---

## 01 · Onboarding

| | |
|---|---|
| **Feature** | `Features/Onboarding` |
| **PM** | `OnboardingPage` (icon key, title key, body key) — static content, no data |
| **VM** | `OnboardingViewModel` — page index, `completeOnboarding()` |
| **UC** | *(none)* — writes `preferences.onboardingCompletedVersion` |
| **R** | — |
| **S** | `PreferencesProviding` |
| **D** | `OnboardingState` |
| **→** | "Get started" → `.fullScreen(.authentication(.signUp))` · "I already have an account" → `.fullScreen(.authentication(.signIn))` · both may be skipped to `.anonymous` (A-04) |

## 02 · Sign in

| | |
|---|---|
| **Feature** | `Features/Authentication` |
| **PM** | `SignInFormState { email, password, fieldErrors: [FieldID: ErrorPresentation], isSubmitting, socialButtonsEnabled }` |
| **VM** | `SignInViewModel` — `submit()`, `signInWithApple()`, `signInWithGoogle()`, `forgotPassword()` |
| **UC** | `SignIn`, `SignInWithApple`, `SignInWithGoogle` |
| **R** | — |
| **S** | `AuthProviding`, `KeychainStore`, `TelemetryProviding` |
| **D** | `AuthCredentials`, `AuthSession`, `UserProfile`, `AuthenticationError` |
| **→** | success → dismiss + `AppRouter` replays `pendingDestination` (`06 §1.3`) · "Sign up" → `.authentication(.signUp)` · "Forgot password?" → `.modal(.forgotPassword)` |
| **Notes** | Apple/Google credential acquisition happens in the Infrastructure adapters; the VM only sees `AuthCredentials`. Sign in with Apple is mandatory alongside Google (`12 §10`). |

## 03 · Sign up

| | |
|---|---|
| **Feature** | `Features/Authentication` |
| **PM** | `SignUpFormState { name, email, password, acceptedTerms: Bool, introOfferBanner: IntroOfferBanner?, fieldErrors, isSubmitting }` |
| **VM** | `SignUpViewModel` |
| **UC** | `SignUp`, `LoadProducts` (for the "7 days of Premium free" banner — A-22) |
| **R** | — |
| **S** | `AuthProviding`, `SubscriptionProviding` (intro-offer eligibility only), `PreferencesProviding` |
| **D** | `AuthRegistration`, `UserProfile`, `IntroOffer`, `ValidationError` |
| **→** | success → root re-evaluates `AuthState` · Terms/Privacy links → `.modal(.legal(.termsOfUse / .privacyPolicy))` |
| **Notes** | The trial banner is **display-only**; no purchase happens here. `acceptedTerms == false` blocks submit via `ValidationError.termsNotAccepted`. |

## 02 · Home ("Your garage")

| | |
|---|---|
| **Feature** | `Features/Home` |
| **PM** | `HomeDashboardPM { greeting, vehicleCard: VehicleCardPM, aiRecommendation: InsightCardPM?, upcoming: [UpcomingEventPM], monthSpend: StatTilePM, consumption: StatTilePM, unreadAlertCount: Int }` — every string pre-formatted by `HomeFormatter` |
| **VM** | `HomeViewModel` — `load()`, `refresh()`, `switchVehicle()`, `openAlerts()`, observes `SelectedVehicleStore` + change feed |
| **UC** | **`LoadHomeDashboard`** (composite, `04 §7`) → internally `CalculateFuelStatistics`, `BuildAnalyticsReport`, `EvaluateReminderTriggers`, `EvaluateDocumentExpiries`, `LoadRecentActivity`, `LoadUserStatistics` |
| **R** | Vehicle, Fuel, Service, Expense, Odometer, Reminder, Document, AIInsight, NotificationInbox |
| **S** | `ClockProviding`, `PreferencesProviding` (units/currency) |
| **D** | `Vehicle`, `VehicleHealth`, `FuelStatistics`, `AnalyticsReport`, `UpcomingEvent`, `ActivityItem`, `AIInsight`, `Metric<T>` |
| **→** | vehicle card → `.vehicleDetail(id)` · bell → `.alerts` · AI card → `.aiInsightDetail(id)` · upcoming row → `.reminderDetail` / `.documentDetail` · `€342` tile → `.expenses(vid, .month)` · `6.2 L/100km` tile → `.fuelHistory(vid)` · `[+]` → `.modal(.quickLog)` |
| **Notes** | `HEALTH 94%` comes from `VehicleHealthScorer` (deterministic, A-14 / `09 §5`), **not** AI. `NEXT SVC 520 km` is `UpcomingEvent.remainingDistance`. Renders fully offline; AI insights are read from cache only. |

## 05 · Notifications ("Alerts")

| | |
|---|---|
| **Feature** | `Features/Alerts` |
| **PM** | `AlertsPM { sections: [AlertSectionPM] }` grouped `TODAY` / `THIS WEEK` / `EARLIER` by `ClockProviding.calendar` |
| **VM** | `AlertsViewModel` — `load()`, `markRead()`, `clearAll()`, `select(_:)` |
| **UC** | `LoadNotificationInbox`, `MarkNotificationRead`, `ClearNotifications` |
| **R** | `NotificationInboxRepository` |
| **S** | `ClockProviding` |
| **D** | `AppNotification`, `NotificationKind` (A-25) |
| **→** | each row navigates to its stored `AppDestination` — the same value a push notification carries (`11 §4`) |
| **Notes** | Rows are localisation keys + arguments, rendered at display time (`03 §2.8`). "Fuel logged automatically" is `NotificationKind.fuelLogged`, reserved for A-11. |

## 03 · Garage · List

| | |
|---|---|
| **Feature** | `Features/Garage` |
| **PM** | `GaragePM { vehicles: [VehicleRowPM] }` — each with mileage text, fuel type, VIN (truncated), `isPrimary` |
| **VM** | `GarageViewModel` — `load()`, `select(_:)`, `addVehicle()`, `delete(_:)` |
| **UC** | `LoadGarage`, `SetDefaultVehicle`, `DeleteVehicle` |
| **R** | `VehicleRepository`, `OdometerRepository` |
| **S** | `FeatureGate` (vehicle limit), `FileStorage` (photos) |
| **D** | `Vehicle`, `VehicleSummary` |
| **→** | row → `.vehicleDetail(id)` · `+` / "Add another vehicle" → `.modal(.vehicleEditor(.create))`, **guarded**: free tier with ≥1 vehicle → `.modal(.paywall(.vehicleLimit))` |
| **Notes** | `LoadGarage` uses count-only fetches for the badges; it never loads full record sets. |

## 07 · Vehicle · Detail

| | |
|---|---|
| **Feature** | `Features/VehicleDetail` |
| **PM** | `VehicleDetailPM { header: VehicleHeaderPM, stats: [StatTilePM], sections: [DetailSectionPM] }` where sections carry their counts ("12 records", "48 fill-ups", "6 active") |
| **VM** | `VehicleDetailViewModel` |
| **UC** | `LoadVehicleDetail` (composes `CalculateFuelStatistics` + count queries), `DeleteVehicle` |
| **R** | Vehicle, Fuel, Service, Expense, Document, Reminder, Odometer |
| **S** | `PreferencesProviding`, `FileStorage` |
| **D** | `Vehicle`, `FuelStatistics`, `VehicleSummary` |
| **→** | Edit → `.modal(.vehicleEditor(.edit(id)))` · Service → `.serviceHistory(id)` · Fuel → `.fuelHistory(id)` · Documents → `.documents(id)` · Statistics → `.analytics(id, .year)` |
| **Notes** | `REGISTERED SE · 2021` = `registrationCountry` + `year`; `COLOR Nardo Grey` = `Vehicle.color` (A-16). |

## 08 · Add vehicle

| | |
|---|---|
| **Feature** | `Features/VehicleEditor` (shared by create and edit) |
| **PM** | `VehicleEditorPM { mode, draft: VehicleDraft, fieldErrors, canSave, isPlateScanAvailable }` |
| **VM** | `VehicleEditorViewModel` — `save()`, `scanPlate()`, `pickPhoto()` |
| **UC** | `CreateVehicle`, `UpdateVehicle`, `RecognizeLicensePlate` (A-15, premium) |
| **R** | `VehicleRepository`, `OdometerRepository`, `ReminderRepository` |
| **S** | `FileStorage`, `TextRecognizer`, `FeatureGate`, `IDGenerating`, `ClockProviding` |
| **D** | `Vehicle`, `VehicleDraft`, `FuelType`, `VIN`, `LicensePlate`, `Odometer`, `ValidationError` |
| **→** | Save → dismiss; **if first vehicle** → `SelectedVehicleStore.select(new)` and Home reloads · "Scan license plate" → `.fullScreen(.camera(.plate))`, guarded by premium |
| **Notes** | The **first-vehicle-becomes-default** rule lives in `CreateVehicle` (`04 §1`), not here. The mileage field writes an `OdometerReading`, not a `Vehicle` column. |

## 04 · Add / Quick-log menu ("What's new?")

| | |
|---|---|
| **Feature** | `Features/QuickLog` |
| **PM** | `QuickLogPM { actions: [QuickActionPM] }` — each with `FeatureAccess` so locked rows render a badge |
| **VM** | `QuickLogViewModel` — `select(_:)` |
| **UC** | *(none)* — pure dispatch |
| **R** | — |
| **S** | `FeatureGate` |
| **D** | `PremiumFeature`, `FeatureAccess` |
| **→** | Add Fuel → `.modal(.fuelEditor(.create))` · Add Service → `.modal(.serviceEditor(.create))` · Add Expense → `.modal(.expenseEditor(.create))` · Add Reminder → `.modal(.reminderEditor(.create))` · Scan Receipt → `.fullScreen(.camera(.receipt))` **guarded** · Upload Document → `.modal(.documentPicker)` |
| **Notes** | This is `ModalRoute.quickLog`, presented from the tab-bar `[+]`. It is **not a tab** (A-01). Each row is guard-evaluated individually, so a free user sees the paywall on Scan Receipt but the editor on Add Fuel. |

## 10 · Add Fuel

| | |
|---|---|
| **Feature** | `Features/Fuel` |
| **PM** | `FuelEditorPM { totalCostDisplay, volumeDisplay, pricePerUnitDisplay, date, odometer, station, paymentTag, isFullTank, fieldErrors, warnings, canSave }` |
| **VM** | `FuelEditorViewModel` — computes the third of {volume, price, total} as the user types |
| **UC** | `AddFuelEntry`, `UpdateFuelEntry` |
| **R** | `FuelRepository`, `OdometerRepository` |
| **S** | `FileStorage` (receipt), `PreferencesProviding` (units/currency/payment tags), `NotificationScheduling` (via `RescheduleRemindersForVehicle`), `ClockProviding` |
| **D** | `FuelEntry`, `Volume`, `Money`, `Odometer`, `FuelType`, `PaymentMethodTag`, `RecordSource` |
| **→** | Save → dismiss; Home/Fuel refresh via the change feed |
| **Notes** | The **`Full tank` toggle is load-bearing** — it drives the whole consumption algorithm (`09 §1`). `Payment · Visa ···4832` is a user-typed `PaymentMethodTag` label, never card data (A-12 / `12 §9`). Adding a fuel entry **does not** create an `Expense` (`03 §4`). |

## 11 · Add Service

| | |
|---|---|
| **Feature** | `Features/Service` |
| **PM** | `ServiceEditorPM { type, date, odometer, cost, workshop, itemChips: [ServiceItemChipPM], attachments, autoCompleteReminders: Bool, fieldErrors }` |
| **VM** | `ServiceEditorViewModel` |
| **UC** | `AddServiceRecord`, `UpdateServiceRecord`, `CompleteReminder` (invoked internally) |
| **R** | `ServiceRepository`, `OdometerRepository`, `ReminderRepository` |
| **S** | `FileStorage`, `NotificationScheduling`, `ClockProviding` |
| **D** | `ServiceRecord`, `ServiceItem`, `ServiceType`, `ServiceNature`, `PartUsage`, `Money` |
| **→** | Save → dismiss; returns which reminders auto-completed, surfaced as a confirmation |
| **Notes** | The `INCLUDE` chips (Oil filter, Air filter, Brake pads, Tire rotation, Coolant) are `ServiceItem`s — the reason `ServiceRecord` is multi-item (A-26 / `03 §2.4`). A record containing both an oil-change and a filter item satisfies **both** reminders. "Attach receipt" writes a `FileRef`, not bytes in the row. |

## 05 · Fuel history

| | |
|---|---|
| **Feature** | `Features/Fuel` |
| **PM** | `FuelHistoryPM { consumptionHeader: ConsumptionHeaderPM (value, unit, trendPercent, sparkline: [TrendPointPM]), entries: [FuelRowPM], dataQualityNotice: String? }` |
| **VM** | `FuelHistoryViewModel` — paginated, observes the change feed |
| **UC** | `LoadFuelHistory`, `CalculateFuelStatistics`, `DeleteFuelEntry` |
| **R** | `FuelRepository`, `OdometerRepository` |
| **S** | `PreferencesProviding` (L/100km vs MPG — conversion happens **here**, `05 §3.1`) |
| **D** | `FuelEntry`, `FuelStatistics`, `ConsumptionTrend`, `FuelSegment`, `DataQualityIssue` |
| **→** | `+` → `.modal(.fuelEditor(.create))` · row → `.fuelEntryDetail(id)` |
| **Notes** | `6.2` and `+9%` come from `FuelStatistics`, never computed in the view (A-20). With <2 full tanks the header renders `Metric.insufficientData`, **not `0.0`** (`09 §3`). |

## 13 · Expenses · Overview

| | |
|---|---|
| **Feature** | `Features/Expenses` |
| **PM** | `ExpensesOverviewPM { yearSelector, total: StatTilePM, monthlyBars: [MonthBarPM], categoryTiles: [CategoryTilePM], recent: [CostRowPM] }` |
| **VM** | `ExpensesViewModel` — owns the year selector (feature-local state, `06 §2.3`) |
| **UC** | `BuildAnalyticsReport`, `LoadExpenses`, `AddExpense`, `DeleteExpense` |
| **R** | Fuel, Service, Expense, Odometer, Vehicle |
| **S** | `FeatureGate` (period clamping, A-06), `PreferencesProviding`, `ClockProviding` |
| **D** | `CostEntry`, `CostLedger`, `AnalyticsReport`, `CategoryBreakdown`, `MonthlyBucket`, `Money` |
| **→** | category tile → `.analyticsDetail(.categories)` · recent row → `.expenseDetail` / `.fuelEntryDetail` / `.serviceRecordDetail` depending on `CostOrigin` |
| **Notes** | This screen is the clearest justification for `CostLedger`: `Fuel €1,842 / Service €1,120 / Other €1,324` and the `RECENT` list mix fuel entries, service records and expenses in one feed — from three tables, with **no duplication** (`03 §4`). Empty months render as `isEmpty`, not `€0` (`09 §4`). |

## 06 · Documents

| | |
|---|---|
| **Feature** | `Features/Documents` |
| **PM** | `DocumentsPM { searchText, cards: [DocumentCardPM (name, subtitle, expiryBadge, availability)] }` |
| **VM** | `DocumentsViewModel` — search debounced, observes the change feed |
| **UC** | `QueryDocuments`, `EvaluateDocumentExpiries`, `AddDocument`, `DeleteDocument`, `OpenDocumentFile` |
| **R** | `DocumentRepository` |
| **S** | `FileStorage` (+ `FileAvailability`), `ThumbnailGenerating`, `NotificationScheduling`, `ClockProviding` |
| **D** | `DocumentMetadata`, `DocumentType`, `DocumentExpiry`, `FileRef` |
| **→** | `+` → `.modal(.documentPicker)` · card → `.documentDetail(id)` → `.fullScreen(.documentViewer(id))` |
| **Notes** | Expiry badges ("Expires 14 Nov 2025" vs "Until 2024") come from `DocumentExpiryEvaluator`. `PDF · 12 MB` is `fileSize` + `mimeType` (A-19). A file not yet downloaded from iCloud shows `FileAvailability.remote` with tap-to-download — the list still renders instantly because metadata is local (`11 §10`). |

## 15 · Reminders

| | |
|---|---|
| **Feature** | `Features/Reminders` |
| **PM** | `RemindersPM { nextUp: NextUpPM (title, dueText, progressFraction, baselineText, currentText), all: [ReminderRowPM (title, recurrenceText, statusBadge)] }` |
| **VM** | `RemindersViewModel` |
| **UC** | `EvaluateReminderTriggers`, `CreateReminder`, `UpdateReminder`, `DeleteReminder`, `CompleteReminder` |
| **R** | `ReminderRepository`, `OdometerRepository` |
| **S** | `NotificationScheduling`, `ClockProviding` |
| **D** | `Reminder`, `ReminderTrigger`, `MileageTrigger`, `RecurrenceRule`, `ReminderStatus`, `ReminderProgress`, `ReminderEvaluation` |
| **→** | `+` → `.modal(.reminderEditor(.create))` · row → `.reminderDetail(id)` |
| **Notes** | The `NEXT UP` progress bar `82,120 km → 82,540 km` is `ReminderProgress`, which is why `MileageTrigger` carries a **baseline** as well as an interval (A-17). `Every 15,000 km` / `Yearly` / `Every 2 years` / `Seasonal · Apr / Nov` are the four `RecurrenceRule` cases including `.seasonal` (A-18). "Due within 520 km · Nov 20" is a `.whicheverFirst` trigger — the date half is exact, the mileage half is a projection (`11 §3.2`). |

## 07 · AI Assistant hub

| | |
|---|---|
| **Feature** | `Features/AIHub` |
| **PM** | `AIHubPM { tiles: [AIToolTilePM (title, subtitle, access: FeatureAccess)], recentChats: [ConversationRowPM], quotaBanner: QuotaBannerPM? }` |
| **VM** | `AIHubViewModel` |
| **UC** | `ListConversations`, `DeleteConversation` |
| **R** | `AIConversationRepository` |
| **S** | `FeatureGate`, `ConnectivityProviding` |
| **D** | `ConversationSummary`, `PremiumFeature`, `FeatureAccess`, `AIUsageSnapshot` |
| **→** | Scan Dashboard → `.fullScreen(.camera(.dashboard))` **guarded + disclaimer** · Scan Receipt → `.fullScreen(.camera(.receipt))` **guarded** · Analyze Damage → `.fullScreen(.camera(.damage))` **guarded + disclaimer** · Ask AI → `.aiChat(nil)` · recent chat → `.aiChat(id)` |
| **Notes** | Tiles render their lock state from `FeatureAccess` but **never enforce it** — enforcement is `RouteGuard` + the use case (`10 §4.2`). |

## 17 · AI · Scan Dashboard

| | |
|---|---|
| **Feature** | `Features/DashboardScan` |
| **PM** | `DashboardScanPM { cameraState, isTorchOn, capturedImage?, analysisState: ViewState<DashboardResultPM>, disclaimer: DisclaimerPM }` |
| **VM** | `DashboardScanViewModel` — owns the capture → analyze → result flow and its cancellation Task |
| **UC** | `ScanDashboard` |
| **R** | `ScanRepository` |
| **S** | `ImagePreprocessing` (**EXIF/GPS stripped**), `VisionAnalysisProvider`, `FileStorage`, `FeatureGate` |
| **D** | `DashboardScan`, `DashboardFinding`, `FindingSeverity`, `DrivingSafetyAssessment`, **`AIDisclaimer`** |
| **→** | Capture → in-place result · result → `.dashboardScanResult(id)` · X → dismiss |
| **Notes** | The disclaimer is a **non-optional field** on the result type, and `ScanDashboard` refuses to run until `DisclaimerAcknowledgement` is recorded for the current version (`03 §6`). `drivingSafety` defaults to `.unknown` on unparseable output — the failure mode is never "safe to drive". Writes **no** vehicle records. |

## 18 · AI · Chat

| | |
|---|---|
| **Feature** | `Features/AIChat` |
| **PM** | `AIChatPM { messages: [MessagePM], streamingText: String?, composer: ComposerPM (isEnabled, placeholder, isOnline), quota: QuotaBannerPM?, contextVehicleName: String? }` |
| **VM** | `AIChatViewModel` — owns `streamTask`, the delta buffer, cancellation, retry |
| **UC** | `AskAI`, `LoadConversation`, `BuildAIContext` (internal to `AskAI`) |
| **R** | `AIConversationRepository`, + all read repositories via `BuildAIContext` |
| **S** | `AIProvider`, `FeatureGate`, `ConnectivityProviding`, `ClockProviding` |
| **D** | `AIConversation`, `AIMessage`, `AIVehicleContext`, `AIStreamEvent`, `AIError` |
| **→** | back → `.aiHub` · quota exceeded → `.modal(.paywall(.aiQuota(resetAt:)))` |
| **Notes** | The `Online` header chip is `ConnectivityStore` (A-24). Deltas render from an in-memory buffer; the assistant message is persisted **once**, at completion/cancel/failure (`08 §2.2`). Context is the bounded `AIVehicleContext`, never raw rows, and never VIN/plate/notes (`08 §4`). |

## 08 · Profile

| | |
|---|---|
| **Feature** | `Features/Profile` |
| **PM** | `ProfilePM { identity: IdentityPM (name, email, tierBadge), stats: [StatTilePM], premiumCard: PremiumCardPM, quickSettings: [SettingRowPM] }` |
| **VM** | `ProfileViewModel` |
| **UC** | `LoadUserStatistics`, `SignOut`, `RestorePurchases` |
| **R** | Vehicle, Fuel, Service (count queries only) |
| **S** | `AuthSessionStore`, `EntitlementStore`, `PreferencesProviding` |
| **D** | `UserProfile`, `Entitlement`, `UserStatistics` |
| **→** | Premium card → `.modal(.paywall(.settingsUpgrade))` · Language/Dark mode → write `PreferencesProviding` in place · Support → `.settingsSection(.about)` · (row) → `.settings` |
| **Notes** | `1 Vehicle · 48 Fill-ups · 12 Services` is `UserStatistics` (A-21) — cheap counts, not an `AnalyticsReport`. The `PREMIUM` badge reads `EntitlementStore`; the view never touches StoreKit (`10`). |

## 20 · Premium · Paywall

| | |
|---|---|
| **Feature** | `Features/Premium` |
| **PM** | `PaywallPM { context: PaywallContext, headline, benefits: [BenefitPM], plans: [PlanPM (price, period, savingsBadge, isPromoted)], ctaTitle, introOfferText?, legalLinks }` |
| **VM** | `PaywallViewModel` — `purchase(_:)`, `restore()`, `dismiss()` |
| **UC** | `LoadProducts`, `PurchasePremium`, `RestorePurchases` |
| **R** | — |
| **S** | `SubscriptionProviding` via `EntitlementStore` **only** |
| **D** | `SubscriptionProduct`, `ProductID`, `Entitlement`, `IntroOffer`, `PurchaseOutcome`, `PaywallContext` |
| **→** | success → dismiss + replay `pendingDestination` (`10 §5`) · X → dismiss · Terms/Privacy → `.modal(.legal(_))` |
| **Notes** | `€4.99` / `€39` come from StoreKit's localised `displayPrice` — never hard-coded. "BEST · 2 months free" is a computed `relativeSavingsPercent`. `Start 7-day free trial` appears only when `isEligibleForIntroOffer` (A-22). `PaywallContext` drives the headline so the copy matches why the user arrived. `.pending` (Ask to Buy) is a first-class state, not an error. |

## 21 · Settings

| | |
|---|---|
| **Feature** | `Features/Settings` |
| **PM** | `SettingsPM { sections: [SettingsSectionPM] }`; sub-screens have their own PMs (`UnitsSettingsPM`, `DataSettingsPM`, `AboutPM`) |
| **VM** | `SettingsViewModel` + one VM per sub-screen |
| **UC** | `ExportVehicleHistoryPDF`, `ExportDataArchive`, `ImportDataArchive`, `DeleteAllData`, `RestorePurchases`, `DeleteAccount` |
| **R** | all (for export / delete-all) |
| **S** | `PreferencesProviding`, `SyncStatusProviding`, `DocumentExporting`, `SubscriptionProviding`, `TelemetryProviding`, `NotificationScheduling` |
| **D** | `UnitSystem`, `CurrencyCode`, `AppearancePreference`, `SyncState`, `Entitlement`, `DataArchive` |
| **→** | Units → `.settingsSection(.units)` · Notifications → `.settingsSection(.notifications)` · **Payment method → opens the App Store billing URL** (`12 §9`) · Export as PDF → `.modal(.shareExport(url))` (premium-guarded) · Manage subscription → `showManageSubscriptions` · Privacy/Terms → `.modal(.legal(_))` |
| **Notes** | Settings is a **read/write view over `PreferencesProviding`**, not a god-object (`06 §2.3`). `iCloud sync` reflects `SyncState`; per A-05 it is **not** premium-gated. `Analytics · On` is `telemetryEnabled` — product telemetry, unrelated to the Analytics feature (A-09). `Region`/`Time zone` feed `ClockProviding.calendar`, which is what makes month bucketing correct (`09 §4`). |

---

## Screens implied by the spec but not shown in the screenshots

Same treatment, briefer, so the implementation phase has no gaps.

| Screen | Feature | Key use cases | → |
|---|---|---|---|
| **Service history (timeline)** | `Features/Service` | `QueryServiceHistory` (by date/mileage/type/nature) | `.serviceHistory(vid, filter)` |
| **Add / edit Expense** | `Features/Expenses` | `AddExpense`, `UpdateExpense` | `.modal(.expenseEditor(_))` |
| **Add / edit Reminder** | `Features/Reminders` | `CreateReminder`, `UpdateReminder` | `.modal(.reminderEditor(_))` |
| **Analytics dashboard** | `Features/Analytics` | `BuildAnalyticsReport` with period picker (Week/Month/6M/Year/All) | `.analytics(vid, period)` |
| **Cost of Ownership detail** | `Features/Analytics` | `BuildAnalyticsReport` → `CostOfOwnership` | `.analyticsDetail(.ownership)` |
| **Receipt review & confirm** | `Features/ReceiptScan` | `ScanReceipt` → **review** → `ConfirmReceiptScan` | `.modal(.receiptReview(scanID))` |
| **Damage analysis result** | `Features/DamageAnalysis` | `AnalyzeDamage` | `.damageAnalysisResult(id)` |
| **AI insight detail** | `Features/Home` / `Analytics` | `GenerateAIInsights` (cached read) | `.aiInsightDetail(id)` |
| **Document viewer** | `Features/Documents` | `OpenDocumentFile` (+ `FileAvailability`) | `.fullScreen(.documentViewer(id))` |
| **Disclaimer acknowledgement** | `Features/AIHub` | records `DisclaimerAcknowledgement` | `.modal(.disclaimerAcknowledgement(kind))` |
| **Forgot password** | `Features/Authentication` | `RequestPasswordReset` | `.modal(.forgotPassword)` |
| **Legal (Terms / Privacy)** | `Features/Settings` | — | `.modal(.legal(_))` |
| **Empty garage state** | `Features/Garage` | — | fallback when `SelectedVehicleStore.selected == nil` |
