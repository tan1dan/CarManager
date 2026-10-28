import Testing
import Foundation
@testable import CarManager

@Suite("Fuel consumption")
struct FuelConsumptionTests {
    private let vehicle = VehicleID()
    private let clock = FixedClock()

    private func fill(_ km: Double, _ liters: Double, full: Bool = true, missed: Bool = false, day: Double = 0) -> FuelEntry {
        let date = clock.now.addingTimeInterval(day * 86_400)
        return FuelEntry(
            vehicleID: vehicle, date: date, odometer: Odometer(kilometers: km),
            volume: Volume(liters: liters), pricePerUnit: Money(Decimal(1.8), .eur),
            totalCost: Money(Decimal(liters * 1.8), .eur), fuelType: .diesel,
            isFullTank: full, missedPreviousFillUp: missed, createdAt: date, updatedAt: date
        )
    }

    @Test("Consumption runs from one full fill to the next")
    func basicSegment() {
        let segments = FuelConsumptionCalculator.segments([fill(1_000, 40), fill(1_600, 36)])
        #expect(segments.count == 1)
        #expect(segments[0].distance.kilometers == 600)
        #expect(abs(segments[0].litersPer100km - 6.0) < 0.0001)
    }

    @Test("Partial fills in between count towards the closing segment")
    func partialFills() {
        let segments = FuelConsumptionCalculator.segments([
            fill(1_000, 40), fill(1_300, 15, full: false), fill(1_600, 21)
        ])
        #expect(segments.count == 1)
        #expect(segments[0].volume.liters == 36)
    }

    @Test("Nothing before the first full fill can be measured")
    func leadingPartialIgnored() {
        let segments = FuelConsumptionCalculator.segments([fill(500, 20, full: false), fill(1_000, 40), fill(1_500, 30)])
        #expect(segments.map(\.distance.kilometers) == [500])
    }

    @Test("A missed fill-up voids its segment instead of reporting a wrong number")
    func missedFillUp() {
        let segments = FuelConsumptionCalculator.segments([
            fill(1_000, 40), fill(1_600, 20, missed: true), fill(2_200, 36)
        ])
        // Only the clean second stretch survives.
        #expect(segments.map(\.distance.kilometers) == [600])
    }

    @Test("Zero or negative distances are discarded")
    func nonPositiveDistance() {
        #expect(FuelConsumptionCalculator.segments([fill(1_000, 40), fill(1_000, 10)]).isEmpty)
    }

    @Test("The average is weighted by distance, not a mean of segments")
    func weightedAverage() {
        let segments = FuelConsumptionCalculator.segments([fill(0, 50), fill(100, 10), fill(1_100, 60)])
        // 10 L / 100 km and 60 L / 1000 km → 70 L / 1100 km, not (10 + 6) / 2.
        let average = try? #require(FuelConsumptionCalculator.average(segments))
        #expect(abs((average ?? 0) - 70.0 / 1_100 * 100) < 0.0001)
        #expect(FuelConsumptionCalculator.average([]) == nil)
    }
}

@Suite("Cost ledger")
struct CostLedgerTests {
    private let vehicle = VehicleID()
    private let clock = FixedClock()      // 2025-10-09 UTC

    private func expense(_ amount: Decimal, monthsAgo: Int, category: ExpenseCategory = .parking, currency: CurrencyCode = .eur) -> Expense {
        let date = clock.calendar.date(byAdding: .month, value: -monthsAgo, to: clock.now)!
        return Expense(vehicleID: vehicle, title: "x", category: category, cost: Money(amount, currency),
                       date: date, createdAt: date, updatedAt: date)
    }

    @Test("Monthly totals are zero-filled, oldest first, ending with the current month")
    func monthly() {
        let ledger = CostLedger.entries(fuel: [], services: [], expenses: [
            expense(100, monthsAgo: 0), expense(50, monthsAgo: 0), expense(30, monthsAgo: 2)
        ])
        let months = CostLedger.monthly(ledger, currency: .eur, months: 4, endingAt: clock.now, calendar: clock.calendar)
        #expect(months.map(\.value) == [0, 30, 0, 150])
    }

    @Test("Other currencies are left out, never converted at a made-up rate")
    func currencyIsolation() {
        let ledger = CostLedger.entries(fuel: [], services: [], expenses: [
            expense(100, monthsAgo: 0), expense(999, monthsAgo: 0, currency: .usd)
        ])
        #expect(CostLedger.total(ledger, currency: .eur) == 100)
    }

    @Test("Categories are sorted by amount and empty ones are dropped")
    func categories() {
        let ledger = CostLedger.entries(fuel: [], services: [], expenses: [
            expense(10, monthsAgo: 0, category: .parking), expense(80, monthsAgo: 0, category: .insurance),
            expense(0, monthsAgo: 0, category: .carWash)
        ])
        #expect(CostLedger.byCategory(ledger, currency: .eur).map(\.category) == [.insurance, .parking])
    }

    @Test("A change needs a baseline")
    func change() {
        #expect(CostLedger.change(from: 0, to: 50) == nil)
        #expect(CostLedger.change(from: 100, to: 150) == 0.5)
        #expect(CostLedger.change(from: 100, to: 80) == -0.2)
    }

    @Test("Repairs and maintenance are told apart by the service record's items")
    func serviceCategories() {
        let date = clock.now
        let repair = ServiceRecord(vehicleID: vehicle, date: date,
                                   items: [ServiceItem(type: .brakes, name: "Pads", nature: .repair)],
                                   totalCost: Money(200, .eur), createdAt: date, updatedAt: date)
        let routine = ServiceRecord(vehicleID: vehicle, date: date,
                                    items: [ServiceItem(type: .oilChange, name: "Oil")],
                                    totalCost: Money(90, .eur), createdAt: date, updatedAt: date)
        let ledger = CostLedger.entries(fuel: [], services: [repair, routine], expenses: [])
        #expect(Set(ledger.map(\.category)) == [.repairs, .maintenance])
    }
}

@Suite("Vehicle analytics")
@MainActor
struct VehicleAnalyticsTests {
    private let clock = FixedClock()

    @Test("A new vehicle has no figures rather than zeros")
    func emptyVehicle() async throws {
        let dependencies = makeDependencies(clock: clock)
        let created = try await CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )(VehicleDraft(brand: "Audi", model: "A4"), vehicleLimit: nil)

        let analytics = try await LoadVehicleAnalytics(
            vehicles: dependencies.vehicles, fuel: dependencies.fuel, services: dependencies.services,
            expenses: dependencies.expenses, odometer: dependencies.odometer, clock: clock
        )(vehicleID: created.vehicle.id)

        #expect(analytics.averageConsumption == nil)
        #expect(analytics.thisMonthChange == nil)
        #expect(analytics.costPerKilometer == nil)
        #expect(!analytics.hasAnyCost)
        #expect(analytics.monthlySpend.count == 12)
    }
}

@Suite("Yearly costs and period analytics")
@MainActor
struct YearlyCostsTests {
    private let clock = FixedClock()      // 2025-10-09 UTC

    private func vehicle(_ d: AppDependencies) async throws -> VehicleID {
        try await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock)(
            VehicleDraft(brand: "Audi", model: "A4"), vehicleLimit: nil
        ).vehicle.id
    }

    private func spend(_ d: AppDependencies, _ id: VehicleID, _ amount: Decimal, monthsAgo: Int) async throws {
        let date = clock.calendar.date(byAdding: .month, value: -monthsAgo, to: clock.now)!
        _ = try await AddExpense(expenses: d.expenses, odometer: d.odometer, clock: clock)(
            vehicleID: id, title: "Parking", category: .parking, cost: Money(amount, .eur), date: date
        )
    }

    @Test("Months that have not started yet are nil, not zero")
    func futureMonths() async throws {
        let d = makeDependencies(clock: clock)
        let id = try await vehicle(d)
        try await spend(d, id, 50, monthsAgo: 0)
        let costs = try await LoadYearlyCosts(vehicles: d.vehicles, fuel: d.fuel, services: d.services, expenses: d.expenses, clock: clock)(vehicleID: id)
        #expect(costs.months.count == 12)
        #expect(costs.months[9]?.value == 50)        // October
        #expect(costs.months[10] == nil && costs.months[11] == nil)
        #expect(costs.currentMonthIndex == 9)
    }

    @Test("The year-on-year change compares the same span of both years")
    func yearOnYear() async throws {
        let d = makeDependencies(clock: clock)
        let id = try await vehicle(d)
        try await spend(d, id, 100, monthsAgo: 1)    // Sep 2025
        try await spend(d, id, 200, monthsAgo: 13)   // Sep 2024 — inside the same span
        try await spend(d, id, 999, monthsAgo: 11)   // Nov 2024 — after the span, ignored
        let costs = try await LoadYearlyCosts(vehicles: d.vehicles, fuel: d.fuel, services: d.services, expenses: d.expenses, clock: clock)(vehicleID: id)
        #expect(costs.previousYearChange == -0.5)
        #expect(costs.availableYears == [2025, 2024])
    }

    @Test("A past year shows all twelve months and no current month")
    func pastYear() async throws {
        let d = makeDependencies(clock: clock)
        let id = try await vehicle(d)
        try await spend(d, id, 30, monthsAgo: 13)
        let costs = try await LoadYearlyCosts(vehicles: d.vehicles, fuel: d.fuel, services: d.services, expenses: d.expenses, clock: clock)(vehicleID: id, year: 2024)
        #expect(costs.months.allSatisfy { $0 != nil })
        #expect(costs.currentMonthIndex == nil)
        #expect(costs.total == 30)
    }

    @Test("Without odometer distance there is no cost per kilometre")
    func noDistance() async throws {
        let d = makeDependencies(clock: clock)
        let id = try await vehicle(d)
        try await spend(d, id, 80, monthsAgo: 0)
        let analytics = try await LoadPeriodAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services,
                                                      expenses: d.expenses, odometer: d.odometer, clock: clock)(vehicleID: id, months: 6)
        #expect(analytics.monthlySpend.count == 6)
        #expect(analytics.total == 80)
        #expect(analytics.costPerKilometer == nil)
        #expect(analytics.costPerKilometerChange == nil)
    }

    @Test("Deleting an expense removes its odometer reading too")
    func deleteExpense() async throws {
        let d = makeDependencies(clock: clock)
        let id = try await vehicle(d)
        let expense = try await AddExpense(expenses: d.expenses, odometer: d.odometer, clock: clock)(
            vehicleID: id, title: "Wash", category: .carWash, cost: Money(10, .eur), date: clock.now,
            odometerValue: Odometer(kilometers: 1_000)
        )
        try await DeleteExpense(expenses: d.expenses, odometer: d.odometer)(id: expense.id)
        #expect(try await d.expenses.expenses(vehicleID: id).isEmpty)
        #expect(try await d.odometer.readings(vehicleID: id).allSatisfy { $0.source != .expense(expense.id) })
    }
}

@Suite("Vehicle store refresh")
@MainActor
struct VehicleStoreRefreshTests {
    private let clock = FixedClock()

    @Test("A car that arrives after launch (an iCloud import) reaches Home after a refresh")
    func importedVehicleAppearsAfterRefresh() async throws {
        let dependencies = makeDependencies(clock: clock)
        let app = AppModel(dependencies: dependencies)
        await app.vehicles.bootstrap()
        #expect(app.vehicles.selected == nil)
        let before = app.vehicles.revision

        // Written straight to the repository, as the CloudKit importer does.
        let imported = Vehicle(brand: "Audi", model: "A4", fuelType: .diesel, primaryCurrency: .eur,
                               isDefault: true, createdAt: clock.now, updatedAt: clock.now)
        try await dependencies.vehicles.insert(imported)
        #expect(app.vehicles.selected == nil)   // stale until told

        await app.vehicles.refresh()
        #expect(app.vehicles.selected?.id == imported.id)
        #expect(app.vehicles.summaries.count == 1)
        #expect(app.vehicles.revision > before)
    }

    @Test("A stored default that no longer exists falls back to an existing car")
    func staleDefaultFallsBack() async throws {
        let dependencies = makeDependencies(clock: clock)
        dependencies.preferences.defaultVehicleID = VehicleID()   // from a previous install
        let car = Vehicle(brand: "VW", model: "Golf", fuelType: .petrol, primaryCurrency: .eur,
                          isDefault: false, createdAt: clock.now, updatedAt: clock.now)
        try await dependencies.vehicles.insert(car)
        let app = AppModel(dependencies: dependencies)
        await app.vehicles.bootstrap()
        #expect(app.vehicles.selected?.id == car.id)
    }
}
