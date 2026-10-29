import Foundation
import Observation

/// Display values for the Expenses overview (Figma 13).
struct ExpensesPresentation: Equatable, Sendable {
    struct CategoryTile: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var share: String
        var amount: String
        var fraction: Double
        var colorIndex: Int
    }
    struct Row: Equatable, Sendable, Identifiable {
        var id: String
        var symbol: String
        var isFuel: Bool
        var title: String
        var subtitle: String
        var amount: String
        /// Only stand-alone expenses are deleted here; fuel and service have their own screens.
        var expenseID: ExpenseID?
    }
    var year: Int
    var years: [Int]
    var totalCaption: String
    var total: String
    var change: String?
    var changeTone: Tone
    var bars: [Double?]
    var barLabels: [String]
    var highlight: Int?
    var tiles: [CategoryTile]
    var rows: [Row]
}

@MainActor
@Observable
final class ExpensesViewModel {
    private(set) var state: ViewState<ExpensesPresentation> = .idle
    private(set) var year: Int?

    private let loadYear: LoadYearlyCosts
    private let deleteExpense: DeleteExpense
    private let format: DisplayFormat
    private let clock: any ClockProviding

    init(loadYear: LoadYearlyCosts, deleteExpense: DeleteExpense, format: DisplayFormat, clock: any ClockProviding) {
        self.loadYear = loadYear
        self.deleteExpense = deleteExpense
        self.format = format
        self.clock = clock
    }

    func load(vehicleID: VehicleID) async {
        if case .loaded = state {} else { state = .loading }
        do {
            let costs = try await loadYear(vehicleID: vehicleID, year: year)
            if costs.entries.isEmpty && costs.availableYears.count <= 1 { state = .empty; return }
            state = .loaded(present(costs))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func select(year: Int, vehicleID: VehicleID) async {
        self.year = year
        await load(vehicleID: vehicleID)
    }

    func delete(_ id: ExpenseID, vehicleID: VehicleID) async {
        try? await deleteExpense(id: id)
        await load(vehicleID: vehicleID)
    }

    func present(_ costs: YearlyCosts) -> ExpensesPresentation {
        let total = costs.total.doubleValue
        var tiles: [ExpensesPresentation.CategoryTile] = []
        if total > 0 {
            // Two largest categories by name, everything else folded into "Other" — three tiles fit.
            let named = costs.categories.count > 3 ? Array(costs.categories.prefix(2)) : costs.categories
            let rest = costs.categories.dropFirst(named.count).reduce(Decimal(0)) { $0 + $1.amount }
            var parts = named.map { ($0.category.displayName, $0.amount) }
            if rest > 0 { parts.append((String(localized: "Other"), rest)) }
            tiles = parts.enumerated().map { index, part in
                let fraction = part.1.doubleValue / total
                return .init(name: part.0, share: "\(Int((fraction * 100).rounded()))%",
                             amount: format.money(part.1, costs.currency, fractionDigits: 0),
                             fraction: fraction, colorIndex: index)
            }
        }
        let rows = costs.entries.prefix(30).map { entry in
            ExpensesPresentation.Row(
                id: entry.id,
                symbol: entry.category.symbolName,
                isFuel: entry.category == .fuel,
                title: entry.title,
                subtitle: format.shortDate(entry.date, relativeTo: clock.now) + " · " + entry.category.displayName,
                amount: format.money(entry.amount),
                expenseID: { if case .expense(let id) = entry.origin { return id }; return nil }()
            )
        }
        let change = costs.previousYearChange
        return ExpensesPresentation(
            year: costs.year,
            years: costs.availableYears,
            totalCaption: costs.currentMonthIndex != nil ? String(localized: "Total this year") : String(localized: "Total in \(String(costs.year))"),
            total: format.money(costs.total, costs.currency, fractionDigits: 0),
            change: change.map { String(localized: "\(format.percentChange($0)) vs \(String(costs.year - 1))") },
            changeTone: (change ?? 0) > 0.005 ? .warning : (change ?? 0) < -0.005 ? .success : .neutral,
            bars: costs.months.map { $0?.value.doubleValue },
            barLabels: (1...12).compactMap { month in
                format.calendar.date(from: DateComponents(year: costs.year, month: month, day: 1)).map { format.month($0, narrow: true) }
            },
            highlight: costs.currentMonthIndex,
            tiles: tiles,
            rows: Array(rows)
        )
    }
}

@MainActor
@Observable
final class AddExpenseViewModel {
    var amountText = ""
    var category: ExpenseCategory = .other
    var date: Date
    var odometerText = ""
    var note = ""
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var vehicleName = ""
    private(set) var odometerHint: String?
    private(set) var currency: CurrencyCode

    /// Fuel has its own editor with litres and the full-tank flag, so it is not offered here.
    let categories = ExpenseCategory.allCases.filter { $0 != .fuel }

    private let vehicleID: VehicleID
    private let addExpense: AddExpense
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let router: AppRouter
    let format: DisplayFormat
    let now: Date

    init(
        vehicleID: VehicleID, addExpense: AddExpense, vehicles: any VehicleRepository,
        odometer: any OdometerRepository, router: AppRouter, currency: CurrencyCode, format: DisplayFormat, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addExpense = addExpense
        self.vehicles = vehicles
        self.odometer = odometer
        self.router = router
        self.currency = currency
        self.format = format
        self.now = now
        self.date = now
    }

    func prepare() async {
        if let vehicle = try? await vehicles.vehicle(id: vehicleID) {
            currency = vehicle.primaryCurrency
            vehicleName = vehicle.displayName
        }
        if let current = try? await odometer.current(vehicleID: vehicleID) {
            odometerHint = format.integer(current.value.kilometers)
        }
    }

    /// "Insurance · Audi A4" under the amount.
    var meta: String { [category.displayName, vehicleName].filter { !$0.isEmpty }.joined(separator: " · ") }

    var canSave: Bool { (NumberInput.decimal(amountText) ?? 0) > 0 && !isSaving }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await addExpense(
                vehicleID: vehicleID, title: category.displayName, category: category,
                cost: Money(NumberInput.decimal(amountText) ?? 0, currency), date: date,
                odometerValue: NumberInput.double(odometerText).flatMap { $0 > 0 ? Odometer(kilometers: $0) : nil },
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
            router.dismissModal()
        } catch {
            errorMessage = UserMessage.text(for: error)
        }
    }

    func cancel() { router.dismissModal() }
}
