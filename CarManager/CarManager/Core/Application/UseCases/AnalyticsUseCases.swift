import Foundation

/// Everything the charts need for one vehicle, computed once per screen load.
///
/// Every value is optional or empty when the underlying records do not exist — a vehicle
/// with two fill-ups has no consumption trend yet, and the UI says so instead of drawing zeros.
public struct VehicleAnalytics: Sendable, Equatable {
    public let currency: CurrencyCode
    /// Oldest first, 12 calendar months ending with the current one, zero-filled.
    public let monthlySpend: [MonthValue<Decimal>]
    public let thisMonthSpend: Decimal
    /// Change versus last month; `nil` without a baseline.
    public let thisMonthChange: Double?
    public let yearSpend: Decimal
    public let previousYearChange: Double?
    public let categoriesThisYear: [CategoryTotal]
    public let categoriesLastSixMonths: [CategoryTotal]
    public let averageConsumption: Double?
    /// Oldest first, 12 months; `nil` where no segment closed that month.
    public let monthlyConsumption: [MonthValue<Double?>]
    /// Latest month with a value versus the one before it.
    public let consumptionChange: Double?
    /// Spend per kilometre over the last 12 months; `nil` without distance data.
    public let costPerKilometer: Decimal?
    public let recentCosts: [CostEntry]
    public let fuelEntries: [FuelEntry]

    public var hasAnyCost: Bool { !recentCosts.isEmpty }
}

public struct LoadVehicleAnalytics: Sendable {
    let vehicles: any VehicleRepository
    let fuel: any FuelRepository
    let services: any ServiceRepository
    let expenses: any ExpenseRepository
    let odometer: any OdometerRepository
    let clock: any ClockProviding

    public init(
        vehicles: any VehicleRepository, fuel: any FuelRepository, services: any ServiceRepository,
        expenses: any ExpenseRepository, odometer: any OdometerRepository, clock: any ClockProviding
    ) {
        self.vehicles = vehicles; self.fuel = fuel; self.services = services
        self.expenses = expenses; self.odometer = odometer; self.clock = clock
    }

    public func callAsFunction(vehicleID: VehicleID) async throws -> VehicleAnalytics {
        guard let vehicle = try await vehicles.vehicle(id: vehicleID) else {
            throw DomainError.validation(.vehicleNotFound)
        }
        async let fuelHistory = fuel.entries(vehicleID: vehicleID)
        async let fuelOrdered = fuel.entriesForConsumption(vehicleID: vehicleID)
        async let serviceHistory = services.query(ServiceQuery(vehicleID: vehicleID))
        async let expenseHistory = expenses.expenses(vehicleID: vehicleID)
        async let readings = odometer.readings(vehicleID: vehicleID)

        let now = clock.now, calendar = clock.calendar
        let currency = vehicle.primaryCurrency
        let ledger = CostLedger.entries(
            fuel: try await fuelHistory, services: try await serviceHistory, expenses: try await expenseHistory
        )

        let monthly = CostLedger.monthly(ledger, currency: currency, months: 12, endingAt: now, calendar: calendar)
        let thisMonth = monthly.last?.value ?? 0
        let lastMonth = monthly.dropLast().last?.value ?? 0

        let thisYear = CostLedger.yearRange(containing: now, calendar: calendar)
        let lastYearDate = calendar.date(byAdding: .year, value: -1, to: now) ?? now
        let lastYear = CostLedger.yearRange(containing: lastYearDate, calendar: calendar)
        // Compare like with like: this year so far against the same span last year.
        let lastYearToDate = DateRange(start: lastYear.start, end: lastYearDate)
        let yearSpend = CostLedger.total(ledger, currency: currency, in: thisYear)
        let lastYearSpend = CostLedger.total(ledger, currency: currency, in: lastYearToDate)

        let sixMonthsStart = CostLedger.monthStarts(count: 6, endingAt: now, calendar: calendar).first ?? now
        let lastSixMonths = DateRange(start: sixMonthsStart, end: now)

        let segments = FuelConsumptionCalculator.segments(try await fuelOrdered)
        let monthlyConsumption = FuelConsumptionCalculator.monthly(segments, months: 12, endingAt: now, calendar: calendar)
        let withValues = monthlyConsumption.compactMap(\.value)
        let consumptionChange: Double? = withValues.count >= 2
            ? (withValues[withValues.count - 1] - withValues[withValues.count - 2]) / withValues[withValues.count - 2]
            : nil

        // Cost per km over the last 12 months, using the odometer span in that window.
        let yearStart = monthly.first?.monthStart ?? now
        let window = DateRange(start: yearStart, end: now)
        let windowReadings = try await readings.filter { window.contains($0.recordedAt) }
        let span = (windowReadings.map(\.value.kilometers).max() ?? 0) - (windowReadings.map(\.value.kilometers).min() ?? 0)
        let windowSpend = CostLedger.total(ledger, currency: currency, in: window)
        let costPerKm: Decimal? = span > 0 && windowSpend > 0 ? windowSpend / Decimal(span) : nil

        return VehicleAnalytics(
            currency: currency,
            monthlySpend: monthly,
            thisMonthSpend: thisMonth,
            thisMonthChange: CostLedger.change(from: lastMonth, to: thisMonth),
            yearSpend: yearSpend,
            previousYearChange: CostLedger.change(from: lastYearSpend, to: yearSpend),
            categoriesThisYear: CostLedger.byCategory(ledger, currency: currency, in: thisYear),
            categoriesLastSixMonths: CostLedger.byCategory(ledger, currency: currency, in: lastSixMonths),
            averageConsumption: FuelConsumptionCalculator.average(segments),
            monthlyConsumption: monthlyConsumption,
            consumptionChange: consumptionChange,
            costPerKilometer: costPerKm,
            recentCosts: Array(ledger.prefix(20)),
            fuelEntries: try await fuelHistory
        )
    }
}

/// One calendar year of spending for the Expenses overview (Figma 13).
public struct YearlyCosts: Sendable, Equatable {
    public let year: Int
    public let currency: CurrencyCode
    /// January…December. `nil` for months that have not started yet — they are not "€0".
    public let months: [MonthValue<Decimal>?]
    /// Index into `months` of the current month when `year` is the current year.
    public let currentMonthIndex: Int?
    public let total: Decimal
    /// Against the same span of the previous year; `nil` without a baseline.
    public let previousYearChange: Double?
    public let categories: [CategoryTotal]
    /// Newest first, all origins (fuel, service, expenses) in this year.
    public let entries: [CostEntry]
    /// Years that have at least one cost, newest first; always includes the current year.
    public let availableYears: [Int]
}

public struct LoadYearlyCosts: Sendable {
    let vehicles: any VehicleRepository
    let fuel: any FuelRepository
    let services: any ServiceRepository
    let expenses: any ExpenseRepository
    let clock: any ClockProviding

    public init(
        vehicles: any VehicleRepository, fuel: any FuelRepository, services: any ServiceRepository,
        expenses: any ExpenseRepository, clock: any ClockProviding
    ) {
        self.vehicles = vehicles; self.fuel = fuel; self.services = services
        self.expenses = expenses; self.clock = clock
    }

    public func callAsFunction(vehicleID: VehicleID, year requested: Int? = nil) async throws -> YearlyCosts {
        guard let vehicle = try await vehicles.vehicle(id: vehicleID) else {
            throw DomainError.validation(.vehicleNotFound)
        }
        async let fuelHistory = fuel.entries(vehicleID: vehicleID)
        async let serviceHistory = services.query(ServiceQuery(vehicleID: vehicleID))
        async let expenseHistory = expenses.expenses(vehicleID: vehicleID)
        let ledger = CostLedger.entries(
            fuel: try await fuelHistory, services: try await serviceHistory, expenses: try await expenseHistory
        )

        let now = clock.now, calendar = clock.calendar
        let currency = vehicle.primaryCurrency
        let currentYear = calendar.component(.year, from: now)
        let year = requested ?? currentYear

        let isCurrentYear = year == currentYear
        let currentMonth = calendar.component(.month, from: now)
        let months: [MonthValue<Decimal>?] = (1...12).map { month in
            if isCurrentYear && month > currentMonth { return nil }
            guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
            let range = CostLedger.monthRange(start, calendar: calendar)
            return MonthValue(monthStart: start, value: CostLedger.total(ledger, currency: currency, in: range))
        }

        let anchor = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        let yearRange = CostLedger.yearRange(containing: anchor, calendar: calendar)
        // A year in progress is compared with the same span last year, not the whole of it.
        let spanEnd = isCurrentYear ? now : yearRange.end
        let thisSpan = DateRange(start: yearRange.start, end: spanEnd)
        let lastStart = calendar.date(byAdding: .year, value: -1, to: yearRange.start) ?? yearRange.start
        let lastEnd = calendar.date(byAdding: .year, value: -1, to: spanEnd) ?? spanEnd
        let total = CostLedger.total(ledger, currency: currency, in: thisSpan)
        let previous = CostLedger.total(ledger, currency: currency, in: DateRange(start: lastStart, end: lastEnd))

        let years = Set(ledger.map { calendar.component(.year, from: $0.date) } + [currentYear])

        return YearlyCosts(
            year: year,
            currency: currency,
            months: months,
            currentMonthIndex: isCurrentYear ? currentMonth - 1 : nil,
            total: total,
            previousYearChange: CostLedger.change(from: previous, to: total),
            categories: CostLedger.byCategory(ledger, currency: currency, in: thisSpan),
            entries: ledger.filter { thisSpan.contains($0.date) },
            availableYears: years.sorted(by: >)
        )
    }
}

/// The Analytics screen's figures for one period (Figma 38). Every value is `nil` or empty
/// when the records to compute it do not exist.
public struct PeriodAnalytics: Sendable, Equatable {
    public let vehicleID: VehicleID
    public let currency: CurrencyCode
    /// Oldest first, one per calendar month of the period, zero-filled.
    public let monthlySpend: [MonthValue<Decimal>]
    public let total: Decimal
    /// This month against last month; `nil` without a baseline.
    public let lastMonthChange: Double?
    public let monthlyConsumption: [MonthValue<Double?>]
    public let averageConsumption: Double?
    public let bestConsumption: MonthValue<Double>?
    public let categories: [CategoryTotal]
    public let costPerKilometer: Decimal?
    /// Against the same-length period before it; `nil` without a baseline.
    public let costPerKilometerChange: Double?
}

public struct LoadPeriodAnalytics: Sendable {
    let vehicles: any VehicleRepository
    let fuel: any FuelRepository
    let services: any ServiceRepository
    let expenses: any ExpenseRepository
    let odometer: any OdometerRepository
    let clock: any ClockProviding

    public init(
        vehicles: any VehicleRepository, fuel: any FuelRepository, services: any ServiceRepository,
        expenses: any ExpenseRepository, odometer: any OdometerRepository, clock: any ClockProviding
    ) {
        self.vehicles = vehicles; self.fuel = fuel; self.services = services
        self.expenses = expenses; self.odometer = odometer; self.clock = clock
    }

    /// `months == nil` means all time, starting with the month of the first record.
    public func callAsFunction(vehicleID: VehicleID?, months requested: Int?) async throws -> PeriodAnalytics {
        let resolved: Vehicle?
        if let vehicleID { resolved = try await vehicles.vehicle(id: vehicleID) } else { resolved = try await vehicles.defaultVehicle() }
        guard let vehicle = resolved else { throw DomainError.validation(.vehicleNotFound) }
        let id = vehicle.id

        async let fuelHistory = fuel.entries(vehicleID: id)
        async let fuelOrdered = fuel.entriesForConsumption(vehicleID: id)
        async let serviceHistory = services.query(ServiceQuery(vehicleID: id))
        async let expenseHistory = expenses.expenses(vehicleID: id)
        async let readings = odometer.readings(vehicleID: id)

        let now = clock.now, calendar = clock.calendar
        let currency = vehicle.primaryCurrency
        let ledger = CostLedger.entries(
            fuel: try await fuelHistory, services: try await serviceHistory, expenses: try await expenseHistory
        )

        let months: Int
        if let requested { months = requested } else if let first = ledger.last?.date {
            let span = calendar.dateComponents([.month], from: first, to: now).month ?? 0
            months = min(max(span + 1, 6), 120)
        } else { months = 6 }

        let monthly = CostLedger.monthly(ledger, currency: currency, months: months, endingAt: now, calendar: calendar)
        let start = monthly.first?.monthStart ?? now
        let period = DateRange(start: start, end: now)

        let segments = FuelConsumptionCalculator.segments(try await fuelOrdered)
        let inPeriod = segments.filter { period.contains($0.endDate) }
        let consumption = FuelConsumptionCalculator.monthly(segments, months: months, endingAt: now, calendar: calendar)
        let best = consumption.compactMap { m in m.value.map { MonthValue(monthStart: m.monthStart, value: $0) } }
            .min { $0.value < $1.value }

        // Cost per km: spend in a window over the odometer distance covered in it.
        let allReadings = try await readings
        // Spend is counted only between the first and last reading in the window, so a
        // window the history only partly covers is not divided by too short a distance.
        func costPerKm(_ range: DateRange) -> Decimal? {
            let inRange = allReadings.filter { range.contains($0.recordedAt) }
            guard let first = inRange.min(by: { $0.recordedAt < $1.recordedAt }),
                  let last = inRange.max(by: { $0.recordedAt < $1.recordedAt }) else { return nil }
            let distance = last.value.kilometers - first.value.kilometers
            let spend = CostLedger.total(ledger, currency: currency, in: DateRange(start: first.recordedAt, end: last.recordedAt))
            return distance > 0 && spend > 0 ? spend / Decimal(distance) : nil
        }
        let current = costPerKm(period)
        let previousStart = calendar.date(byAdding: .month, value: -months, to: start) ?? start
        // Only compare with a previous window the history fully covers.
        let historyStart = allReadings.map(\.recordedAt).min() ?? now
        let previous = historyStart <= previousStart
            ? costPerKm(DateRange(start: previousStart, end: start.addingTimeInterval(-1))) : nil
        let perKmChange = current.flatMap { c in previous.flatMap { CostLedger.change(from: $0, to: c) } }

        return PeriodAnalytics(
            vehicleID: id,
            currency: currency,
            monthlySpend: monthly,
            total: CostLedger.total(ledger, currency: currency, in: period),
            lastMonthChange: monthly.count >= 2 ? CostLedger.change(from: monthly[monthly.count - 2].value, to: monthly[monthly.count - 1].value) : nil,
            monthlyConsumption: consumption,
            averageConsumption: FuelConsumptionCalculator.average(inPeriod),
            bestConsumption: best,
            categories: CostLedger.byCategory(ledger, currency: currency, in: period),
            costPerKilometer: current,
            costPerKilometerChange: perKmChange
        )
    }
}
