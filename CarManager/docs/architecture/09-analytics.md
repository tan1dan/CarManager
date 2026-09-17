# 09 · Analytics Architecture (Deterministic Statistics)

```
Raw entities              Pure domain services            Value types            Presentation
──────────────            ────────────────────            ───────────            ────────────
[FuelEntry]        ─┐
[OdometerReading]  ─┴─► FuelConsumptionCalculator ─────► FuelStatistics ─┐
                                                                          ├─► PresentationModel ─► View
[FuelEntry]        ─┐                                                     │
[ServiceRecord]    ─┼─► CostLedger ─► [CostEntry] ─► StatisticsEngine ─► AnalyticsReport
[Expense]          ─┘                                        ▲            │
[OdometerReading]  ─────────────────────────────────────────┘            │
                                                                          ▼
                                                              GenerateAIInsights (§08 §5)
```

**Every box left of "Presentation" is a pure function of value types.** No I/O, no async, no
`Date()`, no `Calendar.current`, no formatting. That is what makes analytics deterministic — and
what makes it testable in microseconds with hand-written fixtures.

---

## 1. Fuel consumption — the precise algorithm

The spec demands precision about full-tank vs. partial-tank entries. This is the specification of
`FuelConsumptionCalculator`.

### 1.1 The physical principle

Consumption can only be measured across an interval where **the tank level is known at both ends**.
The only such points are full-tank fill-ups. Therefore:

> For two consecutive full-tank entries A and B (A earlier), the fuel consumed over the distance
> `B.odometer − A.odometer` equals **the sum of all fuel added *after* A, up to and including B**.

The critical detail: **A's own volume is excluded, B's own volume is included.** A's fill-up restored
the tank to full at A's odometer; that fuel was consumed *before* A. Everything added afterwards —
including any partial fills in between, and including B's fill which restores it to full again — is
what was burned over the segment.

Off-by-one here is the single most common bug in fuel-tracking apps and produces a consistent ~10%
error. It is worth the extra sentence.

### 1.2 The algorithm

```
INPUT:  entries: [FuelEntry] for one vehicle
OUTPUT: FuelStatistics

1. FILTER   drop entries with volume <= 0
2. SORT     ascending by (odometer, date). Odometer is primary: two fill-ups on the same day
            are ordered by distance driven, which is what physically happened.
3. SEGMENT  walk the sorted array, accumulating into an open segment:

            open = nil
            for e in sorted:
                if open == nil:
                    if e.isFullTank { open = Segment(start: e, volume: 0) }   // A found
                    continue                                                  // leading partials
                                                                              // are discarded:
                                                                              // no known baseline
                if e.missedPreviousFillUp || isAnomalous(open.start, e):
                    open = e.isFullTank ? Segment(start: e, volume: 0) : nil   // break & restart
                    continue

                open.volume += e.volume        // partials AND the closing full tank accumulate
                open.cost   += e.totalCost

                if e.isFullTank:
                    CLOSE segment (start: open.start, end: e,
                                   distance: e.odometer - open.start.odometer,
                                   volume: open.volume, cost: open.cost)
                    open = Segment(start: e, volume: 0)   // B becomes the next A. Chaining.

4. VALIDATE  discard a closed segment if:
             · distance <= 0                        (odometer regression / duplicate)
             · distance > maxPlausibleSegmentKm      (default 5,000 km — a missed fill-up)
             · impliedConsumption outside 1…60 L/100km   (data-entry error)
             Each discard is recorded as a DataQualityIssue, surfaced in the UI, never silent.

5. AGGREGATE
             averageConsumption = (Σ segment.volume / Σ segment.distance) × 100
             ── DISTANCE-WEIGHTED across all valid segments.
             ── NOT the arithmetic mean of per-segment averages. Averaging ratios is wrong:
                a 50 km segment must not carry the same weight as a 900 km segment.
```

### 1.3 Segment chaining

Note step 3's closing move: **B becomes the next segment's A**. Segments share endpoints, so a
history of `F P F P P F` (F = full, P = partial) produces exactly 2 segments covering the whole
distance with no gaps and no double-counted volume:

```
odo:    1000        1300        1600        1900        2200        2500
entry:  F(40L)      P(20L)      F(25L)      P(15L)      P(18L)      F(22L)
        └─────── segment 1 ──────┘
                distance 600 km, volume 20+25 = 45 L → 7.50 L/100km
                     └───────────── segment 2 ───────────────┘
                                distance 900 km, volume 15+18+22 = 55 L → 6.11 L/100km

average = (45 + 55) / (600 + 900) × 100 = 100/1500 × 100 = 6.67 L/100km
```

Note that the first entry's 40 L is **never counted**. It has no measurable distance attached to it.

### 1.4 Edge cases, exhaustively

| Case | Behaviour |
|---|---|
| Fewer than 2 full-tank entries | `FuelStatistics.consumption = .insufficientData(fullTankCount:)`. Not zero, not nil, not an error — a distinct case the UI renders as "Add another full fill-up". |
| Leading partial entries before the first full tank | Discarded from consumption. **Still counted** in total volume, total cost and average price. |
| Trailing entries after the last full tank | Same — the open segment is never closed, so its volume is not attributed to any distance. |
| `missedPreviousFillUp == true` | Breaks the segment. Volume still counts toward cost totals. |
| Odometer regression (B ≤ A) | Segment discarded, `DataQualityIssue.odometerRegression` raised. |
| Duplicate odometer, different dates | `distance == 0` → discarded. |
| Two vehicles' entries | Impossible — the calculator takes one vehicle's entries. Enforced by the repository method signature (`entriesForConsumption(vehicleID:)`). |
| EV (`fuelType == .electric`) | Same algorithm; `Volume` carries kWh. Output unit becomes kWh/100km. `FuelStatistics.unit` records which. |
| Mixed currency in a segment | Consumption is unaffected (volume/distance). **Cost per 100 km is computed per currency** (A-13) and the segment contributes only to its own currency bucket. |

### 1.5 The other fuel metrics

```
averageFuelPrice   = Σ totalCost / Σ volume         ← VOLUME-WEIGHTED
                     NOT mean(pricePerUnit). A 60 L fill at €1.60 and a 5 L top-up at €2.10
                     average to €1.64, not €1.85. Averaging the printed price is a real bug
                     that shows up as inflated "average price" in every naive implementation.

costPer100km       = (Σ segment.cost / Σ segment.distance) × 100      ← valid segments only
                     Distinct from AnalyticsReport.costPerKm, which includes ALL cost categories.

totalFuelVolume    = Σ volume over ALL entries in period (not just segments)
totalFuelCost      = Σ totalCost over ALL entries in period
```

### 1.6 Monthly consumption (A-20, screenshot 05's sparkline)

A segment can span a month boundary. The allocation policy must be stated, because "obviously
correct" answers differ:

> **A closed segment is attributed entirely to the calendar month of its *closing* entry (B).**

Chosen over pro-rating by distance because it is simple, deterministic, explainable to a user
("this month's figure comes from the fill-ups you completed this month"), and stable — pro-rating
makes a past month's value change when a later entry is added, which looks like a bug to users.
Months with no closed segment report `.noData`, rendered as a gap in the sparkline, **never as 0**.

`ConsumptionTrend.deltaPercent` (the "+9%") compares the current period's weighted average against
the immediately preceding period of equal length; `nil` if either has no data.

---

## 2. Cost per kilometre

Two different metrics with two different meanings. Both are needed; conflating them is a bug.

```
fuelCostPer100km     = fuel cost within valid segments / segment distance × 100
                       (a fuel-efficiency metric — §1.5)

costPerKm            = Σ CostEntry.amount in period / distanceDriven(in period)
                       (a cost-of-ownership metric — all categories)

distanceDriven(period) = maxOdometer(in period) − minOdometer(in period)
                       from OdometerReading, NOT from fuel entries alone —
                       a service visit or a manual update also establishes distance.
```

`costPerKm` returns `.insufficientData` when `distanceDriven <= 0` or when fewer than two odometer
readings exist in the period. It is never computed by dividing by an assumed distance.

**Cost of Ownership** additionally includes `Vehicle.purchasePrice` amortised over the ownership
period, reported separately as `CostOfOwnership { totalCost, costPerKm, costPerMonth,
depreciationExcluded: true }`. Depreciation is explicitly excluded — we have no valuation source and
inventing one would be exactly the kind of fabricated statistic the spec forbids.

---

## 3. `AnalyticsReport`

```swift
struct AnalyticsReport: Sendable, Hashable {
    let vehicleID: VehicleID?              // nil = all vehicles
    let period: AnalyticsPeriod
    let range: DateRange
    let generatedAt: Date

    let totals: [CurrencyCode: PeriodTotals]     // A-13: grouped, never summed across currencies
    let primaryCurrency: CurrencyCode
    let hasMixedCurrencies: Bool

    let byCategory: [CategoryBreakdown]           // screenshot 13's Fuel/Service/Other tiles
    let byMonth: [MonthlyBucket]                  // screenshot 13's bar chart
    let fuel: FuelStatistics
    let distanceDriven: Distance?
    let costPerKm: Metric<Money>
    let costOfOwnership: CostOfOwnership?

    let dataQuality: [DataQualityIssue]
    let wasClampedByEntitlement: Bool             // A-06 — free tier saw only 12 months
    let metricValues: [MetricID: Double]          // ◄── the AI allowlist (08 §5.2)
}

/// Every derived number is a Metric, not a bare value. "No data" is a first-class case,
/// so a view can never render a fabricated 0 for an unknown quantity.
enum Metric<T: Sendable & Hashable>: Sendable, Hashable {
    case value(T)
    case insufficientData(reason: InsufficientDataReason)
}
```

`Metric<T>` is a small type with a large payoff: the compiler forces every analytics surface to
decide what to show when data is missing. Screens 02 and 13 are full of numbers that would otherwise
silently read "€0" or "0.0 L/100km" for a brand-new vehicle — which users read as a bug, and which
would poison the AI insight allowlist.

---

## 4. `StatisticsEngine`

```swift
enum StatisticsEngine {
    static func report(
        costEntries: [CostEntry],
        odometerReadings: [OdometerReading],
        fuelStatistics: FuelStatistics,
        vehicle: Vehicle?,
        period: AnalyticsPeriod,
        range: DateRange,
        calendar: Calendar,
        now: Date
    ) -> AnalyticsReport

    static func categoryBreakdown(_ entries: [CostEntry], currency: CurrencyCode) -> [CategoryBreakdown]
    static func monthlyBuckets(_ entries: [CostEntry], range: DateRange, calendar: Calendar) -> [MonthlyBucket]
    static func distanceDriven(_ readings: [OdometerReading], in range: DateRange) -> Distance?
}
```

`static`, pure, no dependencies, `Calendar` and `now` injected. Determinism rules:

- Month bucketing uses the **injected `Calendar`** with an explicit `TimeZone` from `ClockProviding`.
  A user in CET (screenshot 21) must not see a purchase move months because the device is in UTC.
- Buckets are **dense**: every month in the range appears, with zero-value buckets explicitly marked
  `isEmpty` (distinct from "€0 spent"). This is what lets screenshot 13's bar chart render a correct
  12-month axis for a vehicle bought in August.
- Ordering is total and stable; ties broken by ID so output is byte-reproducible.
- No floating-point money. `Money.amount` is `Decimal` throughout; only ratios become `Double`.

---

## 5. Vehicle health score (A-14)

Screenshot 02 shows `HEALTH 94%` and a `Healthy` badge. This is **deterministic and explainable**,
never AI-generated — a number that changes because a language model felt differently today is
indefensible.

```swift
enum VehicleHealthScorer {
    static func score(
        reminders: [ReminderEvaluation],
        documents: [DocumentExpiry],
        lastService: ServiceRecord?,
        fuelStatistics: FuelStatistics,
        currentOdometer: Odometer?,
        now: Date
    ) -> VehicleHealth
}

struct VehicleHealth: Sendable, Hashable {
    let score: Int                    // 0…100
    let status: Status                // .healthy (≥85) | .attention (60…84) | .critical (<60)
    let factors: [HealthFactor]       // each with its own penalty and a localised explanation
    let isIndeterminate: Bool         // true when there is too little data to judge
}
```

Deductions (starting from 100, floored at 0):

| Factor | Penalty |
|---|---|
| Each overdue reminder | −12 (max −36) |
| Each expired document | −15 (max −30) |
| Each document expiring within 14 days | −5 |
| No service record in 18 months **and** >20,000 km since the last one | −10 |
| Consumption trend worse than baseline by >15% | −8 |
| Unresolved `DataQualityIssue`s | −0 (never penalised — a data problem is not a car problem) |

A vehicle with fewer than 2 reminders and no service history is `isIndeterminate` and the UI shows
"—" instead of a score. **Fabricating 100% for an empty garage is the same class of error as letting
the AI invent statistics**, and it is refused for the same reason.

`factors` is what feeds both the Home card's subtitle and `AIVehicleContext.HealthSummary`, so the
AI explains a score it did not compute.

---

## 6. Where analytics is computed, and caching

- **Always on a background executor**, via the use case, never on the main actor. A 5-year garage is
  a few thousand rows; the aggregation is milliseconds, but the fetch is not.
- **`AnalyticsReport` is cached in memory** keyed by `(vehicleID, period, dataVersion)`, where
  `dataVersion` is a monotonic counter bumped by the change feed. Home, Analytics and
  `BuildAIContext` all request the same report and hit the cache.
- **Nothing is precomputed into SwiftData.** No denormalised totals table. Derived data in the
  database is derived data that goes stale, and with CloudKit mirroring it is derived data that goes
  stale *on another device*. Recomputing from source is cheap and always correct.
- If profiling ever shows this is too slow (garages beyond ~50,000 rows), the escape hatch is a
  materialised monthly-rollup table rebuilt from the change feed — a Data-layer change only.
