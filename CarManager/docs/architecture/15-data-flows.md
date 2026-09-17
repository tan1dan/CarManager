# 15 · Data Flow Diagrams

Format for every flow: **Input → Use Case → Repository/Service → Persistence/External → Output →
State change.**

---

## 1. Application launch

```
Input      cold start
UseCase    —  (AppLifecycleCoordinator orchestrates; it is not a use case)
Steps      CarManagerApp.init
             └─ AppDependencies.live()
                  └─ PersistenceStack: ModelContainer(SchemaV1, CloudKit .private)
             RootView.task {
               ├─ SelectedVehicleStore.bootstrap()      ← BLOCKING for first paint
               ├─ Task: RestoreSession()                ← non-blocking (flow 2)
               ├─ Task: EntitlementStore.bootstrap()    ← cached first, StoreKit after
               ├─ Task: subscriptions.start()           ← Transaction.updates listener, app-lifetime
               ├─ Task: SyncStatusMonitor.start()
               ├─ Task: NetworkMonitor.start()
               ├─ Task(.background): EvaluateReminderTriggers(nil) → inbox rows
               ├─ Task(.background): EvaluateDocumentExpiries() → inbox rows
               ├─ Task(.background): RescheduleAllReminders()     ← re-projects mileage triggers
               ├─ Task(.background): FileGarbageCollector.run()   ← ≤ once/day
               └─ Task(.background): AIInsightRepository.purgeExpired()
             }
External   SQLite (local); CloudKit begins its own import in the background
Output     Root destination decided by (onboardingCompleted, AuthState, vehicleCount)
State      SelectedVehicleStore .loaded · AuthState .restoring→… · EntitlementStore cached→verified
Rule       Nothing in this list except SelectedVehicleStore.bootstrap() may delay first paint.
```

## 2. Session restoration

```
Input      launch, AuthState = .restoring
UseCase    RestoreSession
Service    AuthProviding → KeychainStore
External   backend /refresh (only if the access token is expired)
Output     AuthSession? → UserProfile?
State      .authenticated(profile) | .anonymous          ← NEVER an error screen (A-04)
Note       Failure is silent and lands on .anonymous. The garage is already on screen.
```

## 3. Sign in

```
Input      email+password | Apple identityToken | Google idToken (PKCE via ASWebAuthenticationSession)
UseCase    SignIn / SignInWithApple / SignInWithGoogle
Service    AuthProviding (actor) → backend /auth/*  →  KeychainStore.store(tokens)
External   backend; Apple/Google identity providers
Output     AuthSession
State      AuthState .authenticated(profile)
           → AppRouter replays pendingDestination (the screen that demanded sign-in)
           → EntitlementStore.refresh()  (subscription may be tied to the account)
Note       LOCAL DATA IS UNTOUCHED. Signing in does not import, merge or replace the garage (A-03).
```

## 4. Create first vehicle

```
Input      VehicleDraft (brand, model, year, fuelType, VIN?, plate?, initialOdometer, photo?)
UseCase    CreateVehicle
  1  FeatureGate.evaluate(.multipleVehicles)   → free tier + 0 vehicles ⇒ .allowed
  2  VehicleValidator.validate(draft)          → pure
  3  FileStorage.store(photo)                  → FileRef
  4  ── one PersistenceActor transaction ──
       VehicleRepository.insert(vehicle, isDefault: TRUE)   ← FIRST VEHICLE RULE
       OdometerRepository.append(OdometerReading(.manual, initialOdometer))
       ReminderRepository.insert(ReminderTemplate.defaults(for: fuelType))  ← isActive: false
Persist    SQLite → (async, invisible) CloudKit export
Output     Vehicle
State      SelectedVehicleStore.select(vehicle) · GarageViewModel refresh via change feed
           · HomeViewModel reloads · router dismisses the editor
```

## 5. Switch vehicle

```
Input      user picks a vehicle (Garage row, or the vehicle picker sheet)
UseCase    SetDefaultVehicle
Repository VehicleRepository.setDefault(id)     ← transactional: clears isDefault on all others
Service    PreferencesProviding.defaultVehicleID = id
Output     Vehicle
State      SelectedVehicleStore.selected = vehicle
           → Home, Vehicle Detail, Analytics, AI context all recompute (they observe the store)
Note       No screen holds its own copy of "the current vehicle". One store, many observers.
```

## 6. Add fuel

```
Input      FuelEntryDraft (date, odometer, volume, price/total, station, isFullTank, tag?, receipt?)
UseCase    AddFuelEntry
  1  validate; derive the missing one of {volume, pricePerUnit, totalCost}
  2  deviation > 2% ⇒ WARNING (not an error)
  3  FileStorage.store(receipt) → FileRef
  4  ── one transaction ──
       FuelRepository.insert(entry)
       OdometerRepository.append(OdometerReading(.fuelEntry(id), odometer))
  5  RescheduleRemindersForVehicle(vehicleID)   ← the new odometer changes every projection (A-10)
Persist    SQLite → CloudKit (async)
Output     FuelEntry + [DomainWarning]
State      sheet dismisses IMMEDIATELY (no network wait)
           change feed → FuelHistoryViewModel, HomeViewModel, AnalyticsViewModel re-fetch
           analytics cache invalidated by the bumped dataVersion
Note       NO Expense row is created (03 §4).
```

## 7. Calculate fuel consumption

```
Input      vehicleID, AnalyticsPeriod
UseCase    CalculateFuelStatistics
Repository FuelRepository.entriesForConsumption(vehicleID:) → ascending (odometer, date)
Domain     FuelConsumptionCalculator.calculate(entries)      ← PURE, no I/O
             sort → segment (full→full, partials accumulate, B chains as next A)
             → validate segments → distance-weighted aggregate  (09 §1)
Output     FuelStatistics { consumption: Metric, costPer100km, averagePrice, segments,
                            trend, dataQualityIssues }
State      FuelHistoryViewModel.state = .loaded · Home consumption tile updates
Note       Zero maths in the view. <2 full tanks ⇒ .insufficientData, not 0.0.
```

## 8. Add service

```
Input      ServiceRecordDraft (date, odometer?, items[≥1], workshop, totalCost, attachments)
UseCase    AddServiceRecord
  1  validate (≥1 item; cost ≥ 0)
  2  FileStorage.store(attachments) → [FileRef]
  3  ── one transaction ──
       ServiceRepository.insert(record)
       OdometerRepository.append(OdometerReading(.serviceRecord(id)))
  4  matching = active reminders whose kind.satisfyingServiceTypes ∩ record item types ≠ ∅
     for each: CompleteReminder(id, at: date, odometer: odometer)
       → RecurrenceCalculator rolls the trigger forward
       → .everyDistance REBASES baselineOdometer to the completion odometer
  5  RescheduleRemindersForVehicle
Output     ServiceRecord + [ReminderID] auto-completed
State      Service history, Home upcoming, Reminders progress bars, analytics all refresh
Note       A record with oilChange + filters items completes BOTH reminders (A-26).
```

## 9. Add expense

```
Input      ExpenseDraft (title, category, cost, date, odometer?, receipt?)
UseCase    AddExpense
Repository ExpenseRepository.insert · OdometerRepository.append (only if odometer supplied)
Service    FileStorage
Output     Expense
State      Expenses overview + Home month tile refresh via change feed
Note       Creates NO fuel and NO service record. A .fuel-category expense is counted in
           AnalyticsReport but NOT in FuelStatistics — different questions (03 §4.3).
```

## 10. Create reminder

```
Input      ReminderDraft (title, kind, trigger, recurrence, leadTime)
UseCase    CreateReminder
  1  validate (baseline present for mileage; ≥1 month for seasonal; trigger/recurrence coherent)
  2  ReminderRepository.insert
  3  NotificationPlanner.plan(reminder, currentOdometer, avgDailyDistance, now)  ← PURE
       .date      → exact UNCalendar trigger
       .mileage   → MileageProjector → projected date (an ESTIMATE)
       .whicheverFirst → BOTH requests scheduled; first to fire wins
       recurrence → next 3 occurrences only (64-request iOS cap, 11 §3.4)
  4  NotificationScheduling.schedule([ScheduledNotification])   ← plain values, no UN types
Output     Reminder (+ PermissionError as a WARNING if notifications are denied)
State      Reminders list + Home upcoming refresh
Note       The domain never imports UserNotifications. NotificationPlanner is a pure function.
```

## 11. Reminder triggers

```
── IN-APP (exact) ──
Input      launch / foreground / any odometer write
UseCase    EvaluateReminderTriggers(vehicleID: nil, now:)
Domain     ReminderEvaluator.evaluate(reminder, context)   ← PURE
             .date       → compare dates
             .mileage    → compare odometer; no reading ⇒ .indeterminate (never .overdue)
             .whicheverFirst → overdue if EITHER is; reason = the nearer in normalised terms
Output     [ReminderEvaluation]
State      Home upcoming, Reminders NEXT UP + progress, vehicle health score
           newly-overdue → NotificationInboxRepository.insert(AppNotification)

── OS NOTIFICATION (estimate) ──
Input      UNCalendarNotificationTrigger fires
Service    UNUserNotificationCenterDelegate (Infrastructure adapter)
Output     userInfo → AppDestination → RouteGuard → AppRouter.navigate   ← same path as a deep link
State      app opens on the reminder; action buttons call CompleteReminder / SnoozeReminder
Rule       The in-app evaluation is TRUTH; the notification is a best-effort nudge (11 §3.3).
```

## 12. Add document

```
Input      DocumentDraft (name, type, dates, file, createExpiryReminder)
UseCase    AddDocument
  1  validate UTI + size (≤ 50 MB)
  2  FileStorage.store(bytes) → FileRef        ← FILE FIRST. A failed write leaves no row.
  3  DocumentRepository.insert(metadata)
  4  Task(.background): ThumbnailGenerating → update metadata.thumbnailRef (failure is non-fatal)
  5  if expirationDate != nil && createExpiryReminder:
       CreateReminder(kind: .custom, trigger: .date(expiry), leadTime: 30d)
       → DocumentMetadata.reminderID linked
  6  FileSyncCoordinator copies into the ubiquity container (async)
Output     DocumentMetadata
State      Documents grid refresh; Home upcoming gains the expiry event
```

## 13. Document expiration notification

```
Input      launch/foreground, or the scheduled UN trigger fires
UseCase    EvaluateDocumentExpiries
Repository DocumentRepository.expiring(before: now + 30d)
Domain     DocumentExpiryEvaluator  ← PURE
             nil expiry → .noExpiry (NEVER .expired)
Output     [DocumentExpiry]
Scheduling NotificationPlanner emits 4 requests per document: 30 / 14 / 7 / 1 days before
           identifiers "document.<uuid>.<daysBefore>" ⇒ rescheduling is idempotent
State      Documents badge, Home upcoming ("Insurance renewal · Expires in 14 days"),
           Alerts inbox row, vehicle health deduction
```

## 14. Scan receipt  ← the flow the spec constrains hardest

```
Input      captured image, vehicleID
UseCase    ScanReceipt                                    ── HAS NO FINANCIAL REPOSITORY ──
  1  FeatureGate.requirePremium(.receiptScan)             → .locked ⇒ paywall, zero network
  2  ImagePreprocessing.prepareForUpload                  → downscale + STRIP EXIF/GPS
  3  FileStorage.store(image) → FileRef
  4  TextRecognizer.recognizeText (ON-DEVICE Vision)      → fewer tokens, offline fallback, audit
  5  VisionAnalysisProvider.analyze(.receipt(image, ocrText, vehicleFacts))
  6  StructuredOutputDecoder validates against the schema → ReceiptDraft
       every field is a FieldSuggestion{ value, confidence, wasEditedByUser, isAccepted }
  7  ScanRepository.upsert(ReceiptScan(status: .awaitingReview))   ← AUDIT ROW ONLY
Persist    the IMAGE and the SCAN. No fuel entry. No service record. No expense.
Output     ReceiptScan in state .awaitingReview
State      router presents .modal(.receiptReview(scanID))
STOP       The flow terminates here. Persistence of a financial record is IMPOSSIBLE
           from this use case — it holds no repository that could do it (03 §5).
```

## 15. Confirm receipt

```
Input      the user reviews and edits the draft; every required field must be ACCEPTED
Domain     ConfirmedReceipt.init?(reviewing: scan, at: now)
             → returns nil unless every required field is accepted ⇒ the type CANNOT be
               constructed from an unreviewed draft
UseCase    ConfirmReceiptScan(confirmed)
             switch confirmed.kind {
               case .fuel:    AddFuelEntry(source: .receiptScan(scanID))
               case .service: AddServiceRecord(source: .receiptScan(scanID))
               case .expense: AddExpense(source: .receiptScan(scanID))
             }                                            ← EXACTLY ONE. Never two.
             ScanRepository: status = .confirmed(recordRef)   ⇒ idempotent on re-confirm
Persist    one row + the receipt image attached to it
Output     RecordRef
State      review sheet dismisses; the record appears in its history and in the cost ledger
Note       The whole state machine (03 §5) lives in the DOMAIN, not in the ViewModel.
```

## 16. Scan dashboard

```
Input      captured image, vehicleID?
UseCase    ScanDashboard
  1  FeatureGate.requirePremium(.dashboardScan)
  2  require DisclaimerAcknowledgement(version) — else .requiresDisclaimerAcknowledgement
       → router presents .modal(.disclaimerAcknowledgement(.notProfessionalDiagnostics))
  3  ImagePreprocessing (EXIF/GPS stripped) → FileStorage
  4  VisionAnalysisProvider.analyze(.dashboard(image, vehicleFacts))
  5  StructuredOutputDecoder → [DashboardFinding]; drivingSafety DEFAULTS TO .unknown
  6  ScanRepository.insert(DashboardScan(findings, disclaimer: <non-optional>))
Output     DashboardScan  — an INFORMATIONAL ESTIMATE by construction (03 §6)
State      result screen; NO vehicle record is created; no "save as service" shortcut is offered
```

## 17. Ask AI

```
Input      user text, conversationID?, vehicleID
UseCase    AskAI  →  AsyncThrowingStream<AIStreamEvent>
  1  FeatureGate.evaluate(.aiChat) → .locked ⇒ paywall, ZERO network
  2  AIConversationRepository.appendMessage(user)     ← PERSISTED BEFORE THE REQUEST
  3  BuildAIContext(vehicleID, scope: .chat)
       StatisticsEngine + FuelConsumptionCalculator + ReminderEvaluator + DocumentExpiryEvaluator
       → AIVehicleContext { facts, fuel, costs, recentServices≤10, upcoming≤5, docs≤5,
                            health, coverage }
       NO raw rows. NO VIN. NO plate. NO notes. NO other vehicles. (08 §4.3)
  4  AIProvider.stream(request)   → BackendAIProvider → SSE
       (the backend holds the model key and enforces quota — 07 §5, A-08)
  5  .delta events accumulate in the ViewModel's in-memory buffer  ← NOT persisted per token
  6  terminal:
       .completed → appendMessage(assistant, isPartial: false)
       cancelled  → appendMessage(assistant, isPartial: true)     ← partial is KEPT
       error      → appendMessage(assistant, failure: …)          ← rendered inline + Retry
Output     streamed AIMessage
State      transcript grows; quota banner updates from the server's authoritative count
           .quotaExceeded ⇒ .modal(.paywall(.aiQuota(resetAt:)))
```

## 18. Generate AI insight

```
Input      vehicleID, AnalyticsPeriod
UseCase    GenerateAIInsights
  1  FeatureGate.requirePremium(.aiInsights)
  2  BuildAnalyticsReport + CalculateFuelStatistics    ← DETERMINISTIC, computed by US
  3  allowlist = report.metricValues                   ← only metrics that ACTUALLY exist
  4  AIProvider.complete(insights request { report summary, allowlist, schema })
  5  ── POST-VALIDATION ──
       discard any insight with no supportingMetrics
       discard any insight citing a MetricID not in the allowlist
       discard any insight whose cited value ≠ the computed value (within tolerance)
       count rejections → TelemetryProviding
  6  AIInsightRepository.replaceAll(accepted, vehicleID:)  with validUntil
Output     [AIInsight]
State      Home AI card, Analytics insights, Alerts inbox (severity ≥ .attention)
Rule       AI NEVER aggregates raw rows and can never surface a statistic we did not compute
           (08 §5). Home reads only the cache and renders fine with zero insights.
```

## 19. Purchase Premium

```
Input      ProductID (from the paywall, which carries the PaywallContext that triggered it)
UseCase    PurchasePremium
Service    EntitlementStore → StoreKitSubscriptionService (actor) → Product.purchase()
External   App Store
  .success(.verified)   → recompute from Transaction.currentEntitlements
                        → persist entitlement → transaction.finish()   ← finish AFTER persisting
  .success(.unverified) → SubscriptionError.unverifiedTransaction, NO entitlement granted
  .pending              → PurchaseOutcome.pending (Ask to Buy) — NOT an error;
                          Transaction.updates delivers the grant later, maybe after relaunch
  .userCancelled        → neutral, no alert, no telemetry noise
Output     PurchaseOutcome
State      EntitlementStore.entitlement = .premium → FeatureGate re-evaluates app-wide
           → paywall dismisses → router REPLAYS pendingDestination (the screen they wanted)
```

## 20. Restore purchases

```
Input      "Restore purchase" (paywall or Settings)
UseCase    RestorePurchases
Service    AppStore.sync() → recompute from Transaction.currentEntitlements
External   App Store (may prompt for the App Store password)
Output     .restored(Entitlement) | .nothingToRestore     ← the latter is NEUTRAL, not an error
State      EntitlementStore updates; gated features unlock across the app simultaneously
Note       Family-shared entitlements arrive with source == .familyShared and are honoured (A-07).
```

## 21. Export PDF

```
Input      vehicleID, AnalyticsPeriod, selected sections
UseCase    ExportVehicleHistoryPDF
  1  FeatureGate.requirePremium(.pdfExport)
  2  gather: Vehicle, [FuelEntry], [ServiceRecord], [Expense], [DocumentMetadata], AnalyticsReport
  3  DocumentExporting.exportPDF(ExportableDocument)   ← ImageRenderer, OFF the main actor
Persist    tmp/exports/<uuid>.pdf   (purged at launch)
Output     URL
State      .modal(.shareExport(url)) → system share sheet
Note       Cancellable via the owning Task; progress reported for large garages.
```

## 22. Sync local data with iCloud

```
Input      any local write, OR a remote change pushed by CloudKit
Service    NSPersistentCloudKitContainer  — we schedule NOTHING and await NOTHING
External   CloudKit private database

  EXPORT   local save → container exports on its own schedule → CloudKit
  IMPORT   CloudKit → container merges → NSPersistentStoreRemoteChange notification
             → ChangeFeed → Repository.changes → ViewModels re-fetch (debounced 250 ms)
             → SelectedVehicleStore re-resolves selection if the selected vehicle vanished

  FILES    FileSyncCoordinator (separate, ours):
             store → copy into the ubiquity container
             read  → not local ⇒ startDownloadingUbiquitousItem
                   → FileAvailability.downloading(progress) surfaced in the UI
                   → checksum verified against FileRef.checksum on completion

  STATUS   NSPersistentCloudKitContainer.Event → SyncStatusMonitor → SyncState
             → Settings "Last synced …" and, for non-retryable failures only, a dismissible toast

Conflicts  CloudKit last-writer-wins. Safe here because the model has almost no contested
           mutable scalars: OdometerReading is append-only, records have distinct UUIDs,
           and Vehicle.isDefault re-converges via SelectedVehicleStore (07 §4.2).
Rule       NO UI EVER WAITS FOR SYNC. Sync failure is a badge, never a blocker.
```

---

## Cross-cutting invariants visible across these flows

1. **Every write path ends at local persistence and updates UI immediately.** CloudKit is always
   downstream of the user being finished (flows 4, 6, 8, 9, 12).
2. **Every odometer-producing write reschedules reminders** (flows 6, 8, 9) — the compensation for
   iOS having no mileage trigger (A-10).
3. **Every AI path is gated before the network call** (flows 14, 16, 17, 18) — a free user never
   costs money, and the paywall is reached without a round trip.
4. **Every image leaving the device is EXIF/GPS-stripped** (flows 14, 16).
5. **Deep links and notification taps share one code path** (flows 11, and `06 §1.4`).
6. **Nothing the user typed or captured is ever silently discarded** — partial AI messages (17),
   captured scan images (14), unconfirmed drafts (15).
