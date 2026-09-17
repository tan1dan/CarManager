# 08 · AI Architecture & AI Context Architecture

---

## 1. Provider abstraction

The Domain declares two ports. Neither mentions a vendor, a model name, an endpoint or a token.

```swift
protocol AIProvider: Sendable {
    func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
    func complete<T: AIStructuredResult>(_ request: AIStructuredRequest<T>) async throws(AIError) -> T
}

protocol VisionAnalysisProvider: Sendable {
    func analyze(_ request: VisionAnalysisRequest) async throws(AIError) -> VisionAnalysisResult
}
```

### Implementations

| Implementation | Used by | Notes |
|---|---|---|
| `BackendAIProvider` | production | `URLSession` + SSE against our proxy (`07 §5`). Holds no key. |
| `MockAIProvider` | Previews, UI tests, offline dev | Scripted responses with configurable delay + failure injection |
| `RecordingAIProvider` | dev tooling | Wraps live, writes fixtures to disk for replay in tests |
| `OnDeviceAIProvider` | **future** | Foundation Models framework. Fits the same protocol. A genuine extension point: on-device is plausible for the "what does P0420 mean?" class of question and would eliminate its marginal cost. |

**Swapping providers touches exactly one line** in `AppDependencies+Live.swift`. No use case, no
ViewModel, no view changes. That is the whole point of the port.

### Model selection is a server concern

The client sends a `purpose` (`.chat`, `.insights`, `.receipt`, `.dashboard`, `.damage`) — never a
model identifier. The backend maps purpose → model, so model upgrades, A/B tests and cost tuning
ship without an App Store release. Hard-coding a model string in the client is a mistake that takes
two weeks and a review cycle to fix.

---

## 2. Streaming with Swift Concurrency

**`AsyncThrowingStream` is the right abstraction here** — justified, per the brief:

- Chat is a **single-consumer, finite, cancellable, failable** sequence. That is exactly
  `AsyncThrowingStream`'s shape.
- Combine would drag reference-type publishers and cancellables into the Application layer and does
  not compose with `async` use cases.
- A delegate/callback API would push the cancellation problem into the ViewModel.
- Structured concurrency gives us cancellation for free: cancelling the consuming `Task` cancels the
  `URLSession` byte stream via `onTermination`.

```swift
enum AIStreamEvent: Sendable {
    case delta(String)
    case completed(text: String, usage: AIUsage)
}
```

### 2.1 The full streaming path

```
AIChatViewModel (@MainActor)
   │  streamTask = Task { … }                        ← the ONE cancellation handle
   ▼
AskAI (use case)  →  AsyncThrowingStream<AIStreamEvent>
   │  1. FeatureGate.evaluate(.aiChat)     ── .locked → paywall, zero network
   │  2. persist the USER message NOW      ── survives crash / cancel
   │  3. BuildAIContext(vehicleID)         ── bounded snapshot, §4
   │  4. provider.stream(request)
   ▼
BackendAIProvider
   │  URLSession.bytes(for:) → SSEDecoder.lines → .delta
   │  onTermination { task.cancel() }
   ▼
UI: ViewModel appends deltas into a local `streamingText` buffer (main actor, cheap String append)
    and re-renders the last bubble.
```

### 2.2 Persistence policy during streaming (important)

**Deltas are never written to SwiftData.** A 400-token answer would otherwise produce ~400 writes
and, with CloudKit mirroring on, ~400 record mutations pushed to iCloud. The assistant message is
persisted **once**:

| Terminal condition | What is persisted |
|---|---|
| `.completed` | Full message, `isPartial = false` |
| User cancelled | Buffered text, `isPartial = true` — the user keeps what arrived |
| Error mid-stream | Buffered text + `failure`, rendered inline with a Retry action |
| App backgrounded | Stream continues briefly under a background task; on expiry, persisted as partial |

Nothing is ever silently discarded. That is a product rule enforced by the use case, not the view.

### 2.3 Cancellation

`AIChatViewModel` holds `private var streamTask: Task<Void, Never>?`. Starting a new turn, leaving
the screen (`.task` modifier teardown), or tapping Stop calls `streamTask?.cancel()`. `AskAI`'s
stream continuation has an `onTermination` handler that cancels the URLSession task and persists the
partial. There is exactly one cancellation path, and it is testable with a fake provider that yields
slowly.

---

## 3. The six AI capabilities

| # | Capability | Port | Use case | Result type | Gated | Grounded in app data |
|---|---|---|---|---|---|---|
| 1 | **AI Chat** | `AIProvider.stream` | `AskAI` | streamed `AIMessage` | Premium + quota | ✅ via `AIVehicleContext` |
| 2 | **Receipt Scan** | `VisionAnalysisProvider` | `ScanReceipt` → `ConfirmReceiptScan` | `ReceiptDraft` (never persisted directly) | Premium | vehicle facts only |
| 3 | **Dashboard Scan** | `VisionAnalysisProvider` | `ScanDashboard` | `[DashboardFinding]` + `AIDisclaimer` | Premium | vehicle facts only |
| 4 | **Damage Analysis** | `VisionAnalysisProvider` | `AnalyzeDamage` | `[DamageFinding]` + `CostEstimateRange` + `AIDisclaimer` | Premium | vehicle facts only |
| 5 | **AI Recommendations** | `AIProvider.complete` | part of `GenerateAIInsights` | short actionable strings inside an `AIInsight` | Premium | ✅ strictly |
| 6 | **AI Insights** | `AIProvider.complete` | `GenerateAIInsights` | `[AIInsight]` with `supportingMetrics` | Premium | ✅ **validated**, §5 |

Capabilities 2–4 use **structured output**: the request declares a JSON schema, and
`StructuredOutputDecoder` validates the response against it before constructing domain types. A
response that does not conform raises `AIError.structuredOutputInvalid` — it is never partially
parsed into a half-populated draft.

---

## 4. AI Context Architecture

> The rule: **never send the database. Send a bounded, deterministic, versioned summary.**

### 4.1 The context type

```swift
struct AIVehicleContext: Sendable, Codable, Hashable {
    let schemaVersion: Int                 // bumped when the shape changes; stored on conversations
    let generatedAt: Date
    let locale: String
    let units: UnitSystem                  // so the model answers in the user's units

    let vehicle: VehicleFacts
    let fuel: FuelSummary?
    let costs: CostSummary?
    let recentServices: [ServiceSummary]   // ≤ 10
    let upcoming: [UpcomingSummary]        // ≤ 5
    let documents: [DocumentSummary]       // ≤ 5, expiring only
    let health: HealthSummary?
    let coverage: DataCoverage             // ◄── the honesty section. §5.

    struct VehicleFacts: Sendable, Codable, Hashable {
        let brand: String
        let model: String
        let year: Int?
        let trim: String?
        let fuelType: String
        let engineDisplacementCC: Int?
        let currentOdometerKm: Double?
        let ageYears: Int?
        // NO VIN. NO license plate. NO color. NO purchase price. See §4.4.
    }

    struct DataCoverage: Sendable, Codable, Hashable {
        let fuelEntryCount: Int
        let serviceRecordCount: Int
        let expenseCount: Int
        let earliestRecord: Date?
        let latestRecord: Date?
        let fullTankEntryCount: Int        // tells the model whether consumption is even meaningful
        let hasSufficientDataForConsumption: Bool
    }
}
```

### 4.2 `BuildAIContext` — deterministic assembly

```swift
struct BuildAIContext: Sendable {
    let vehicleRepo: any VehicleRepository
    let calculateFuelStatistics: CalculateFuelStatistics
    let buildAnalyticsReport: BuildAnalyticsReport
    let evaluateReminders: EvaluateReminderTriggers
    let evaluateDocuments: EvaluateDocumentExpiries
    let healthScorer: VehicleHealthScorer
    let clock: any ClockProviding

    func callAsFunction(vehicleID: VehicleID, scope: ContextScope) async throws -> AIVehicleContext
}

enum ContextScope: Sendable {
    case chat          // full context
    case insights      // analytics-heavy, no free-text notes
    case vision        // vehicle facts only — receipts/dashboards need almost nothing
}
```

Key properties, each of which is a requirement from the brief:

- **Minimal** — three scopes; `.vision` sends ~8 fields, not a garage.
- **Relevant** — it consumes **computed statistics**, not raw rows. `fuel` is a `FuelStatistics`
  summary (average, trend, last fill-up), not 48 fuel entries.
- **Deterministic** — same inputs + same `now` produce a byte-identical context. It is
  `Codable + Hashable`, so tests assert against a golden fixture and the hash can key a server-side
  prompt cache.
- **Bounded** — hard caps (10 services, 5 reminders, 5 documents) plus a `ContextBudget` that
  estimates serialized size and drops the lowest-priority sections if it exceeds the budget. Priority
  order: vehicle facts → coverage → fuel → upcoming → costs → services → documents.
- **Versioned** — `schemaVersion` is stored on `AIConversation`, so an old thread's answers remain
  interpretable after the shape changes.

### 4.3 What is deliberately excluded

| Excluded | Reason |
|---|---|
| Raw fuel/service/expense rows | Token cost, and the model would re-derive statistics badly |
| **VIN, license plate** | Strong personal identifiers. Not needed to answer any supported question. |
| Vehicle color, purchase price | Not needed; purchase price is financially sensitive |
| Free-text `note` fields | May contain arbitrary personal information the user never intended to send. **Notes are never included in any context.** |
| Workshop names, station names | Location-revealing. Included **only** in `.chat` scope, and only aggregated ("most frequent station"), never as a visit log. |
| Document file contents | Only type + expiry date; never the PDF |
| Photos | Only in the vision flows, and only the specific image the user just captured |
| Other vehicles' data | Context is per-vehicle. Asking about the A4 never sends the Golf. |

### 4.4 Redaction is structural, not conditional

`AIVehicleContext.VehicleFacts` **has no VIN field**. There is no flag, no `if includeVIN`. A future
developer cannot accidentally leak the VIN because the type cannot carry it. This is the same
technique used for `ConfirmedReceipt` (`03 §5`) and `CostEstimateRange` (`03 §6`): make the wrong
thing unrepresentable rather than merely discouraged.

---

## 5. Grounding — how "AI must not invent statistics" is enforced

Three mechanisms, in increasing order of strength.

### 5.1 Coverage disclosure (input side)

`DataCoverage` tells the model exactly how much data exists. A vehicle with 2 fuel entries and
`hasSufficientDataForConsumption: false` gets a context that makes "your consumption rose 9%"
unsupportable, and a system prompt instructing the model to say so.

### 5.2 The metric allowlist (contract side)

`GenerateAIInsights` passes the **computed** `AnalyticsReport` plus a closed list of `MetricID`s that
were actually produced:

```swift
enum MetricID: String, Codable, Sendable, CaseIterable {
    case averageConsumptionL100km, consumptionDeltaPercent, costPerKm,
         totalSpendPeriod, fuelSpendPeriod, maintenanceSpendPeriod, repairSpendPeriod,
         averageFuelPrice, monthOverMonthSpendDelta, distanceDrivenPeriod,
         daysUntilNextService, distanceUntilNextService, expiringDocumentCount
}
```

The response schema **requires** each insight to cite `supportingMetrics: [{metricID, value, period}]`.

### 5.3 Post-validation (output side) — the mechanism that actually bites

```swift
// inside GenerateAIInsights, before ANY persistence
let allowed: [MetricID: Double] = report.metricValues      // only metrics that were computed

let accepted = candidates.filter { insight in
    !insight.supportingMetrics.isEmpty &&
    insight.supportingMetrics.allSatisfy { ref in
        guard let truth = allowed[ref.metricID] else { return false }   // unknown metric → reject
        return abs(ref.value - truth) <= tolerance(for: ref.metricID)   // wrong value  → reject
    }
}
```

An insight that cites a metric we did not compute, or restates a computed metric with a different
number, **is discarded before it is ever persisted or displayed**. Rejections are counted and
reported via `TelemetryProviding` so prompt regressions are visible.

This is the concrete answer to *"Do not allow AI to invent missing statistics."* It is not a prompt
instruction (which is advisory); it is a filter (which is not).

### 5.4 Insights are never load-bearing

`LoadHomeDashboard` reads only **cached** insights and renders Home fine with zero of them. AI is
additive everywhere in this app: no screen fails, blocks, or shows an error because AI is
unavailable, unpaid-for, or offline.

---

## 6. AI error taxonomy and its routing

```swift
enum AIError: Error, Sendable, Equatable {
    case offline
    case quotaExceeded(resetAt: Date, tier: SubscriptionTier)
    case requiresPremium(PremiumFeature)
    case providerUnavailable(retryAfter: Duration?)
    case rateLimited(retryAfter: Duration?)
    case structuredOutputInvalid(expected: String)
    case contentFiltered
    case imageTooLarge(maxBytes: Int)
    case noTextRecognized
    case cancelled
    case transport(underlying: String)
}
```

| Error | Presentation |
|---|---|
| `.quotaExceeded`, `.requiresPremium` | **Paywall** with the matching `PaywallContext` — not an alert |
| `.offline` | Inline composer state, message kept as a draft |
| `.providerUnavailable`, `.rateLimited` | Inline retry with backoff; the turn stays in the transcript |
| `.structuredOutputInvalid` | Scan flows: "Couldn't read this receipt — try again or enter manually", with a direct link to the manual editor. **Never a partially-filled draft.** |
| `.cancelled` | Not an error. Partial message kept, no alert. |
| `.contentFiltered` | Neutral inline notice |

---

## 7. Prompt & system-instruction ownership

System prompts live **on the backend**, versioned, keyed by `AIPurpose`. The client sends structured
data and a purpose; it never sends prose it composed itself. Consequences:

- Prompt fixes ship in minutes, not App Store review cycles.
- The client cannot be manipulated into leaking a system prompt it does not have.
- `AIVehicleContext` is serialised to a **stable JSON block**, not to English prose, so the model
  receives structured facts and the serialisation is diffable in tests.
- The only client-side text is the user's own message.
