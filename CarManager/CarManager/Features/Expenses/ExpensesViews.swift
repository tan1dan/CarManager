import SwiftUI

struct ExpensesView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: ExpensesViewModel?

    var body: some View {
        List {
            Text("Expenses")
            switch viewModel?.state {
            case .loading: ProgressView()
            case .loaded(let expenses):
                ForEach(expenses) { expense in
                    Button("\(expense.title) · \(expense.category.rawValue)") {
                        model?.router.push(.expenseDetail(expense.id))
                    }
                }
            case .empty: Text("No expenses")
            case .failed(let error): Text(error.messageKey)
            default: Text("Idle")
            }
        }
        .navigationTitle("Expenses")
        .toolbar {
            Button("Add") { model?.router.present(.expenseEditor(.create(vehicleID))) }
                .accessibilityIdentifier("expenseAdd")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = ExpensesViewModel(load: LoadExpenses(expenses: model.dependencies.expenses))
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }
}

struct ExpenseDetailsView: View {
    let expenseID: ExpenseID
    var body: some View { Text("Expense Details").navigationTitle("Expense") }
}

struct AddExpenseView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddExpenseViewModel?

    var body: some View {
        Group {
            if let viewModel { AddExpenseContentView(viewModel: viewModel) } else { ProgressView() }
        }
        .navigationTitle("Add expense")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = AddExpenseViewModel(
                vehicleID: mode.vehicleID,
                addExpense: AddExpense(
                    expenses: model.dependencies.expenses,
                    odometer: model.dependencies.odometer,
                    clock: model.dependencies.clock
                ),
                router: model.router,
                currency: model.dependencies.preferences.defaultCurrency,
                now: model.dependencies.clock.now
            )
        }
    }
}

private struct AddExpenseContentView: View {
    @Bindable var viewModel: AddExpenseViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Add Expense")
            TextField("Title", text: $viewModel.title)
                .accessibilityIdentifier("expenseTitleField")
            TextField("Cost", text: $viewModel.costText)
                .accessibilityIdentifier("expenseCostField")
            Picker("Category", selection: $viewModel.category) {
                ForEach(ExpenseCategory.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Save") { Task { await viewModel.save() } }
                .accessibilityIdentifier("expenseSave")
            Button("Cancel") { model?.router.dismissModal() }
            if let error = viewModel.state.error { Text(error.messageKey) }
        }
    }
}
