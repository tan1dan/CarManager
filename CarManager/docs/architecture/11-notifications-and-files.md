# 11 · Notification Architecture & Document/File Storage

---

# Part A — Notifications

## 1. The separation the spec demands

> *"Reminder scheduling must be separated from reminder business logic. The domain must not directly
> depend on `UNUserNotificationCenter`."*

```
DOMAIN (pure, no UserNotifications import)
  Reminder, ReminderTrigger, RecurrenceRule
  ReminderEvaluator     → what is due, right now, exactly
  RecurrenceCalculator  → what the next occurrence is
  MileageProjector      → when a mileage threshold will probably be hit
  NotificationPlanner   → [Reminder] + [Document] → [ScheduledNotification]   ← plain values
        │
        │  ScheduledNotification: a value type. No UNNotificationRequest, no UNMutableNotificationContent.
        ▼
INFRASTRUCTURE
  UNNotificationScheduler : NotificationScheduling
        → builds UNMutableNotificationContent, UNCalendarNotificationTrigger, UNNotificationRequest
        → registers categories and actions
        → the ONLY file in the app importing UserNotifications
```

`NotificationPlanner` is a pure function. Everything hard about notification scheduling — which
occurrences, at what dates, with what escalation, with what identifiers — is therefore unit-tested
with no permissions, no simulator, and no waiting.

## 2. Three notification concepts, deliberately distinct

| Concept | Type | Lifetime | Where |
|---|---|---|---|
| **A domain rule** | `Reminder`, `DocumentMetadata.expirationDate` | Persistent, user-owned | SwiftData |
| **An OS-scheduled alert** | `UNNotificationRequest` | Ephemeral, rebuilt on demand | UNUserNotificationCenter |
| **An in-app inbox item** (A-25, screenshot 05) | `AppNotification` | Persistent, user-clearable | SwiftData |

They are **not** the same thing and must not be modelled as one. The Alerts screen shows history
(including things that already fired, and AI insights that never had an OS notification). The OS
queue holds only future fires. The reminder is the rule that generates both.

## 3. Scheduling strategy

### 3.1 Date triggers — exact

`UNCalendarNotificationTrigger` on the computed due date, minus `leadTime.days`, at a fixed local
hour (09:00). Escalation for documents: **30 / 14 / 7 / 1 days before expiry**, each its own request.

### 3.2 Mileage triggers — projected (A-10)

iOS cannot wake the app when the odometer changes; there is no odometer. So:

```
MileageProjector.projectedDate(
    currentOdometer, dueOdometer, averageDailyDistance, now
) -> Date?

averageDailyDistance = distance covered / days elapsed, over a trailing 90-day window
                       of OdometerReading rows, requiring ≥ 2 readings and ≥ 14 days span.
                       Otherwise nil → no notification is scheduled at all.
```

- The notification is scheduled for `projectedDate − leadTime` and is therefore an **estimate**.
- Copy must reflect that: *"Oil change due in ~520 km"*, never *"due on 14 November"* for a mileage
  reminder. False precision here is worse than no notification.
- **Every write that produces an `OdometerReading` triggers `RescheduleRemindersForVehicle`**, so the
  projection converges as the user logs fuel. A user who logs weekly gets a projection accurate to
  within days by the time it matters.
- A `BGAppRefreshTask` re-projects daily even without user activity, so a long gap does not leave a
  stale schedule.

### 3.3 `.whicheverFirst` — the spec's third mode

Schedule **both** requests. Whichever fires first is correct by construction. When one fires, the
other is cancelled by `RescheduleRemindersForVehicle` on next launch. Cheap, robust, and it does not
depend on the projection being right — if the mileage projection is late, the date notification still
fires on time, and vice versa.

*In-app*, `EvaluateReminderTriggers` computes the true status exactly (`04 §5`), so the Home
*Upcoming* list and the Reminders screen are never wrong even when the notification estimate is.
**The notification is a best-effort nudge; the in-app evaluation is the truth.** Stating that
explicitly is what keeps the two implementations from being expected to agree.

### 3.4 Recurrence

Only the **next N = 3 occurrences** of a recurring reminder are scheduled at any time, computed by
`RecurrenceCalculator`. Rescheduling on completion, on odometer change and on app foreground keeps
the window topped up. iOS caps pending requests at **64 per app** — a garage of 5 vehicles × 8
reminders × unbounded occurrences would silently blow that cap and drop notifications. The window is
not an optimisation; it is a correctness requirement.

Identifiers are deterministic: `reminder.<uuid>.<occurrenceIndex>` and
`document.<uuid>.<daysBefore>`. That makes rescheduling **idempotent** — cancel-by-prefix then
re-add, with no risk of duplicates or orphans.

### 3.5 `.seasonal` recurrence (A-18)

"Tire swap · Apr / Nov" schedules on the 1st of each listed month. `RecurrenceCalculator.next()`
returns the nearest future month in the set, wrapping to next year.

## 4. Categories, actions and deep links

```swift
enum NotificationCategoryRegistry {
    static let reminderDue = "REMINDER_DUE"       // actions: "Mark done", "Snooze 7 days"
    static let documentExpiring = "DOCUMENT_EXPIRING"   // action: "View document"
    static let aiInsight = "AI_INSIGHT"
}
```

Every request's `userInfo` carries a `Codable` `AppDestination`. Tapping a notification therefore
takes **the exact same code path as a deep link** (`06 §1.4`): decode → `RouteGuard.evaluate` →
`AppRouter.navigate`. One routing implementation, not two.

Action handling (`UNUserNotificationCenterDelegate`) lives in an Infrastructure adapter that
translates an action identifier into a use-case call (`CompleteReminder`, `SnoozeReminder`) — the
delegate itself contains no logic.

## 5. Permission handling

- Permission is requested **contextually**, when the user creates their first reminder or enables
  notifications in Settings — never at launch. Launch-time prompts get denied.
- **Denial never fails a domain operation.** `CreateReminder` succeeds and returns a
  `PermissionError` as a *warning*; the reminder still works in-app.
- `NotificationAuthorization` is re-checked on every foreground, since the user can change it in
  Settings at any time.

## 6. The in-app inbox (screenshot 05)

`AppNotification` rows are created by:

| Source | When |
|---|---|
| `EvaluateReminderTriggers` | On launch/foreground, for newly-overdue reminders (de-duplicated by reminder + occurrence) |
| `EvaluateDocumentExpiries` | For newly-entering-expiry-window documents |
| `GenerateAIInsights` | When a new insight of severity ≥ `.attention` is produced |
| `SyncStatusMonitor` | On a non-retryable sync failure |
| `EntitlementStore` | On subscription lapse |

Stored as **localisation keys + arguments** (`03 §2.8`), so switching language re-renders the whole
inbox correctly. "Clear" calls `NotificationInboxRepository.clearAll()`; the unread count feeds the
Home bell badge.

---

# Part B — Document & File Storage

## 7. The rule

> **No binary data in SwiftData. Ever.**

`DocumentMetadata`, `Vehicle.photoRef`, `FuelEntry.receiptRef`, `ServiceRecord.attachmentRefs`,
`AIMessage.attachments` all hold a `FileRef` — an ID, a **relative** path, and a SHA-256 checksum
(`03 §2.7`).

Why not `@Attribute(.externalStorage)`, which SwiftData offers? Because with CloudKit mirroring
enabled, external-storage blobs become `CKAsset`s inside the mirrored record graph, and every
12 MB manual (screenshot 06) is then coupled to the record-sync lifecycle: it re-uploads on unrelated
record edits, it cannot be downloaded on demand, its progress cannot be surfaced, and the local store
grows without a purge strategy. Owning the file layer costs one actor and buys explicit control over
all four.

## 8. Layout

```
<Application Support>/Files/          ← local-only. NOT backed up? No: IS backed up, IS in iCloud
    vehicles/<vehicleID>/photo.jpg
    receipts/<uuid>.jpg
    documents/<uuid>.pdf
    thumbnails/<uuid>.jpg              ← regenerable; excluded from backup
    scans/<uuid>.jpg                   ← ephemeral; purged after 30 days
<Caches>/                              ← nothing durable. ever.
<tmp>/exports/                         ← PDF exports, share-sheet handoff, purged on launch
```

`FileLocationResolver` turns `FileRef.relativePath` into a live `URL` at access time. Absolute URLs
are never persisted — container paths change between launches, installs and devices, and storing them
is the classic bug that makes every attachment vanish after an app update.

`thumbnails/` is marked `isExcludedFromBackup` (regenerable). `scans/` too.

## 9. `FileStorageActor`

```swift
actor FileStorageActor: FileStorage {
    func store(_ data: Data, preferredName: String, kind: FileKind) async throws(DocumentError) -> FileRef
    func read(_ ref: FileRef) async throws(DocumentError) -> Data
    func url(for ref: FileRef) async throws(DocumentError) -> URL
    func availability(_ ref: FileRef) async -> FileAvailability
    func ensureLocal(_ ref: FileRef) async throws(DocumentError)
    func delete(_ ref: FileRef) async throws(DocumentError)
    func enqueueForGarbageCollection(_ refs: [FileRef]) async
    func totalSize() async -> Int64
}
```

An actor because file I/O must not run on the main thread and concurrent writes to the same path must
be serialised. `Data` in and out is `Sendable`; large reads are streamed to `URL` rather than loaded
into memory for the viewer path.

## 10. File sync — the part CloudKit mirroring does *not* do

`Application Support` is included in iCloud Backup but is **not** synced live between devices.
Documents added on the iPhone must appear on the iPad, so:

```
FileSyncCoordinator (actor)
  · ubiquity container: NSFileManager.url(forUbiquityContainerIdentifier:)
  · on store():   write locally, then copy into the ubiquity container (setUbiquitous)
  · on read():    if not present locally → startDownloadingUbiquitousItem
                  → report FileAvailability.downloading(progress) via NSMetadataQuery
  · checksum verification on download completion (FileRef.checksum)
  · retry with exponential backoff; failures are non-fatal and surfaced per-file
```

**`FileAvailability` is a first-class UI state.** A document row shows: available / downloading with
progress / tap-to-download. It never shows a broken viewer, and it never blocks the Documents list
from rendering — the metadata is local and instant regardless (`07 §3.2`).

**Alternative considered and rejected:** CKAsset in a custom CloudKit zone. More control, but a
second CloudKit integration living alongside the mirrored store, with its own change tokens and
conflict handling. The ubiquity container gives ~90% of the value for ~10% of the work. → ADR-011

## 11. Garbage collection

Files are **not** reference-counted, because a `FileRef` may legitimately be shared (a receipt image
attached to both a service record and a document).

```
DeleteX use case → returns the [FileRef] it orphaned
                 → FileStorage.enqueueForGarbageCollection(refs)
                 → a pending-deletion list persisted in preferences

FileGarbageCollector (runs on launch, ≤ once/day, off the main actor):
  1. read the pending list
  2. for each ref, ask every repository whether it is still referenced
  3. unreferenced AND older than a 7-day grace window → delete from disk + ubiquity container
  4. ALSO sweep the reverse direction: files on disk with no metadata row anywhere
     (produced by a crash between file write and row write) → delete if older than 7 days
```

The 7-day grace window is what makes the UI-level undo (`03 §3.1`) safe, and what protects against a
CloudKit merge re-introducing a record whose file we deleted a second earlier.

## 12. Limits and validation

| Rule | Value |
|---|---|
| Max single document | 50 MB |
| Allowed UTIs | `.pdf`, `.jpeg`, `.png`, `.heic` |
| Photos | Downscaled to max 2048 px on the long edge before storage |
| Images sent to AI | Downscaled to max 1536 px, JPEG q0.8, **EXIF/GPS stripped** (`12 §Security`) |
| Thumbnails | 400 px, generated via `QuickLookThumbnailing`, failure is non-fatal |
| Total storage | Reported in Settings; a soft warning above 500 MB |

## 13. Export

`DocumentExporting` renders PDF via `ImageRenderer` off the main actor into `tmp/exports/`, returned
as a `URL` for the system share sheet. `tmp/exports/` is purged at launch. `ExportDataArchive`
produces a versioned zip of JSON + files, which `ImportDataArchive` merges additively by ID —
never destructively.
