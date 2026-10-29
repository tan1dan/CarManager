import Foundation

// The analytics engine. PURE: values in, values out — no repositories, no clock, no UI.
// Everything a chart or a stat tile shows is computed here, so every number on screen is
// derived from records the user actually entered and can be tested in isolation.

// MARK: - Fuel consumption

/// One full-tank-to-full-tank stretch. Consumption is only defined between two full fills:
/// the second one tells us exactly how much fuel the distance in between used.
public struct ConsumptionSegment: Hashable, Sendable {
    public let endDate: Date
    public let distance: Distance
    public let volume: Volume

    public init(endDate: Date, distance: Distance, volume: Volume) {
        self.endDate = endDate; self.distance = distance; self.volume = volume
    }

    /// L/100 km (kWh/100 km for electric).
    public var litersPer100km: Double { volume.liters / distance.kilometers * 100 }
}

public enum FuelConsumptionCalculator {
    /// Full-tank segmentation.
    ///
    /// - Entries are ordered by (odometer, date) — the repository's `entriesForConsumption`.
    /// - A segment runs from one full fill to the next; the fuel of every fill after the first
    ///   one up to and including the closing one is what the distance consumed.
    /// - A segment containing a fill flagged `missedPreviousFillUp` is discarded: some fuel
    ///   went in that we never saw, so any number would be wrong — and showing nothing is
    ///   better than showing a wrong number.
    /// - Non-positive distances (duplicate or corrected odometer readings) are discarded.
    public static func segments(_ entries: [FuelEntry]) -> [ConsumptionSegment] {
        var result: [ConsumptionSegment] = []
        var anchor: FuelEntry?
        var pendingVolume = 0.0
        var tainted = false

        for entry in entries {
            guard let start = anchor else {
                if entry.isFullTank { anchor = entry }
                continue
            }
            pendingVolume += entry.volume.liters
            if entry.missedPreviousFillUp { tainted = true }
            guard entry.isFullTank else { continue }

            let distance = entry.odometer.kilometers - start.odometer.kilometers
            if !tainted, distance > 0, pendingVolume > 0 {
                result.append(ConsumptionSegment(
                    endDate: entry.date,
                    distance: Distance(kilometers: distance),
                    volume: Volume(liters: pendingVolume)
                ))
            }
            anchor = entry
            pendingVolume = 0
            tainted = false
        }
        return result
    }

    /// Distance-weighted: total fuel over total distance. A plain mean of segment values
    /// would let one short hop distort the figure.
    public static func average(_ segments: [ConsumptionSegment]) -> Double? {
        let distance = segments.reduce(0) { $0 + $1.distance.kilometers }
        guard distance > 0 else { return nil }
        let volume = segments.reduce(0) { $0 + $1.volume.liters }
        return volume / distance * 100
    }

    /// Average per calendar month, oldest first, for the `months` months ending with the
    /// month containing `now`. A month without a closing full fill has no value (`nil`).
    public static func monthly(
        _ segments: [ConsumptionSegment], months: Int, endingAt now: Date, calendar: Calendar
    ) -> [MonthValue<Double?>] {
        CostLedger.monthStarts(count: months, endingAt: now, calendar: calendar).map { start in
            let inMonth = segments.filter { calendar.isDate($0.endDate, equalTo: start, toGranularity: .month) }
            return MonthValue(monthStart: start, value: average(inMonth))
        }
    }
}

// MARK: - Costs

public struct MonthValue<Value: Hashable & Sendable>: Hashable, Sendable {
    public let monthStart: Date
    public let value: Value
    public init(monthStart: Date, value: Value) { self.monthStart = monthStart; self.value = value }
}

public struct CategoryTotal: Hashable, Sendable {
    public let category: ExpenseCategory
    public let amount: Decimal
    public init(category: ExpenseCategory, amount: Decimal) { self.category = category; self.amount = amount }
}

public enum CostLedger {
    /// Fuel, service and expenses as one stream. Each stays in its own table; this
    /// projection is built on read and never stored, so a cost can never be counted twice.
    public static func entries(
        fuel: [FuelEntry], services: [ServiceRecord], expenses: [Expense]
    ) -> [CostEntry] {
        let fuelEntries = fuel.map {
            CostEntry(id: "fuel-\($0.id)", vehicleID: $0.vehicleID, date: $0.date, amount: $0.totalCost,
                      category: .fuel, odometer: $0.odometer, origin: .fuel($0.id), title: $0.station ?? String(localized: "Fill-up"))
        }
        let serviceEntries = services.map { record in
            CostEntry(id: "service-\(record.id)", vehicleID: record.vehicleID, date: record.date,
                      amount: record.totalCost, category: record.isRepair ? .repairs : .maintenance,
                      odometer: record.odometer, origin: .service(record.id),
                      title: record.items.first?.name ?? String(localized: "Service"))
        }
        let expenseEntries = expenses.map {
            CostEntry(id: "expense-\($0.id)", vehicleID: $0.vehicleID, date: $0.date, amount: $0.cost,
                      category: $0.category, odometer: $0.odometer, origin: .expense($0.id), title: $0.title)
        }
        return (fuelEntries + serviceEntries + expenseEntries).sorted { $0.date > $1.date }
    }

    /// Sum in one currency. Entries in another currency are left out rather than converted:
    /// a silent conversion at an unknown rate would be a fabricated number.
    public static func total(_ entries: [CostEntry], currency: CurrencyCode, in range: DateRange? = nil) -> Decimal {
        entries
            .filter { $0.amount.currency == currency && (range?.contains($0.date) ?? true) }
            .reduce(Decimal(0)) { $0 + $1.amount.amount }
    }

    /// One total per calendar month, oldest first, zero-filled.
    public static func monthly(
        _ entries: [CostEntry], currency: CurrencyCode, months: Int, endingAt now: Date, calendar: Calendar
    ) -> [MonthValue<Decimal>] {
        monthStarts(count: months, endingAt: now, calendar: calendar).map { start in
            let range = monthRange(start, calendar: calendar)
            return MonthValue(monthStart: start, value: total(entries, currency: currency, in: range))
        }
    }

    /// Largest first; categories with nothing spent are omitted.
    public static func byCategory(_ entries: [CostEntry], currency: CurrencyCode, in range: DateRange? = nil) -> [CategoryTotal] {
        var sums: [ExpenseCategory: Decimal] = [:]
        for entry in entries where entry.amount.currency == currency && (range?.contains(entry.date) ?? true) {
            sums[entry.category, default: 0] += entry.amount.amount
        }
        return sums.map { CategoryTotal(category: $0.key, amount: $0.value) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    /// Percentage change from `previous` to `current`. `nil` when there is no baseline —
    /// "+∞%" helps nobody.
    public static func change(from previous: Decimal, to current: Decimal) -> Double? {
        guard previous > 0 else { return nil }
        return NSDecimalNumber(decimal: (current - previous) / previous).doubleValue
    }

    public static func monthStarts(count: Int, endingAt now: Date, calendar: Calendar) -> [Date] {
        guard count > 0, let current = calendar.dateInterval(of: .month, for: now)?.start else { return [] }
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: current) }
    }

    public static func monthRange(_ monthStart: Date, calendar: Calendar) -> DateRange {
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: monthStart) ?? monthStart
        return DateRange(start: monthStart, end: end)
    }

    public static func yearRange(containing date: Date, calendar: Calendar) -> DateRange {
        let interval = calendar.dateInterval(of: .year, for: date)
        let start = interval?.start ?? date
        let end = (interval?.end).map { $0.addingTimeInterval(-1) } ?? date
        return DateRange(start: start, end: end)
    }
}
