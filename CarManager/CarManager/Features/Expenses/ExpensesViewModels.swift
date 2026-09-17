import Foundation
import Observation

@MainActor
@Observable
final class ExpensesViewModel {
    private(set) var state: ViewState<[Expense]> = .idle
    /// The period selector is feature-local state, not global.
    var period: AnalyticsPeriod = .year

    private let load: LoadExpenses
    init(load: LoadExpenses) { self.load = load }

    func load(vehicleID: VehicleID) async {
        state = .loading
        do {
            let expenses = try await load(vehicleID: vehicleID)
            state = expenses.isEmpty ? .empty : .loaded(expenses)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}

@MainActor
@Observable
final class AddExpenseViewModel {
    var title = ""
    var costText = ""
    var category: ExpenseCategory = .other
    private(set) var state: ViewState<Expense> = .idle

    private let vehicleID: VehicleID
    private let addExpense: AddExpense
    private let router: AppRouter
    private let currency: CurrencyCode
    private let now: Date

    init(
        vehicleID: VehicleID, addExpense: AddExpense, router: AppRouter,
        currency: CurrencyCode, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addExpense = addExpense
        self.router = router
        self.currency = currency
        self.now = now
    }

    func save() async {
        state = .loading
        do {
            let expense = try await addExpense(
                vehicleID: vehicleID, title: title, category: category,
                cost: Money(Decimal(Double(costText) ?? 0), currency), date: now
            )
            state = .loaded(expense)
            router.dismissModal()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
