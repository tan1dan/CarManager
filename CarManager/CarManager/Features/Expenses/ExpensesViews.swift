import SwiftUI

/// Expenses overview, built from Figma 13.
struct ExpensesView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: ExpensesViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "Expenses", onBack: { model?.router.pop() }) {
                    HStack(spacing: 8) {
                        if let p = viewModel?.state.value, p.years.count > 1 { yearMenu(p) }
                        CircleIconButton(symbol: "plus", accessibilityLabel: "Add expense") { add() }
                            .accessibilityIdentifier("expenseAdd")
                    }
                }
                content.padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .task { await load() }
        .onChange(of: model?.router.activeModal) { _, modal in if modal == nil { Task { await load() } } }
    }

    private func yearMenu(_ p: ExpensesPresentation) -> some View {
        Menu {
            ForEach(p.years, id: \.self) { year in
                Button(String(year)) { Task { await viewModel?.select(year: year, vehicleID: vehicleID) } }
            }
        } label: {
            HStack(spacing: 4) {
                Text(String(p.year)).font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .dsGlass(radius: 16)
        }
        .accessibilityLabel("Year \(p.year)")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let p):
            totalCard(p)
            if !p.tiles.isEmpty {
                HStack(spacing: 10) {
                    ForEach(p.tiles) { categoryTile($0) }
                }
            }
            if p.rows.isEmpty {
                InfoBanner(symbol: "calendar", text: "Nothing was spent in \(String(p.year)).", tone: .neutral)
            } else {
                VStack(spacing: 8) {
                    Eyebrow(text: "Recent")
                    RowGroup(items: p.rows) { row in
                        RecordRow(symbol: row.symbol, iconStyle: row.isFuel ? .accent : .neutral,
                                  title: row.title, subtitle: row.subtitle, value: row.amount, showsChevron: false)
                            .contextMenu {
                                if let id = row.expenseID {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        Task { await viewModel?.delete(id, vehicleID: vehicleID) }
                                    }
                                }
                            }
                    }
                }
            }
        case .empty:
            EmptyStateView(symbol: "creditcard", title: "No expenses yet",
                           message: "Insurance, parking, tolls, car washes — log them and see where the money goes.",
                           actionTitle: "Add expense", action: add)
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load expenses",
                           message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }

    private func totalCard(_ p: ExpensesPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.totalCaption)
                        .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                    Text(p.total)
                        .font(.system(size: 32, weight: .bold)).tracking(-0.8)
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                Spacer()
                if let change = p.change { Chip(text: change, tone: p.changeTone) }
            }
            .padding(.bottom, 20)
            BarSeriesChart(values: p.bars, labels: p.barLabels, highlight: p.highlight, spacing: 7, cornerRadius: 5)
                .frame(height: 104)
        }
        .padding(20)
        .dsSurface()
    }

    private func categoryTile(_ tile: ExpensesPresentation.CategoryTile) -> some View {
        let color = DS.Colors.series[tile.colorIndex % DS.Colors.series.count]
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Circle().fill(color).frame(width: 7, height: 7)
                Spacer()
                Text(tile.share).font(DS.Text.chip).foregroundStyle(color)
            }
            .padding(.bottom, 14)
            Text(tile.name).font(.system(size: 11)).foregroundStyle(DS.Colors.textSecondary).lineLimit(1)
            Text(tile.amount)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 10)
            ProgressBar(fraction: tile.fraction, color: color, height: 3)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .dsSurface(radius: 20)
        .accessibilityElement(children: .combine)
    }

    private func add() { model?.router.present(.expenseEditor(.create(vehicleID))) }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            let d = model.dependencies
            viewModel = ExpensesViewModel(
                loadYear: LoadYearlyCosts(vehicles: d.vehicles, fuel: d.fuel, services: d.services, expenses: d.expenses, clock: d.clock),
                deleteExpense: DeleteExpense(expenses: d.expenses, odometer: d.odometer),
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                clock: d.clock
            )
        }
        await viewModel?.load(vehicleID: vehicleID)
    }
}

struct ExpenseDetailsView: View {
    let expenseID: ExpenseID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: "Expense", onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}

/// Add Expense, built from Figma 29.
struct AddExpenseView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddExpenseViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel { AddExpenseContentView(viewModel: viewModel) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            let created = AddExpenseViewModel(
                vehicleID: mode.vehicleID,
                addExpense: AddExpense(expenses: d.expenses, odometer: d.odometer, clock: d.clock),
                vehicles: d.vehicles, odometer: d.odometer, router: model.router,
                currency: d.preferences.defaultCurrency,
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                now: d.clock.now
            )
            viewModel = created
            await created.prepare()
        }
    }
}

private struct AddExpenseContentView: View {
    @Bindable var viewModel: AddExpenseViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorTopBar(title: "Add Expense", trailingEnabled: viewModel.canSave,
                             onLeading: viewModel.cancel, onTrailing: save)
                VStack(spacing: 16) {
                    HeroAmountField(caption: "Amount", currencySymbol: viewModel.format.currencySymbol(viewModel.currency),
                                    amount: $viewModel.amountText, meta: viewModel.meta)
                        .accessibilityIdentifier("expenseCostField")
                    FormSurface {
                        FormMenuRow(label: "Category", options: viewModel.categories.map { ($0, $0.displayName) },
                                    selection: $viewModel.category, isFirst: true)
                            .accessibilityIdentifier("expenseCategoryMenu")
                        FormDateRow(label: "Date", date: $viewModel.date, range: Date.distantPast...viewModel.now)
                        if !viewModel.vehicleName.isEmpty {
                            FormValueRow(label: "Vehicle", value: viewModel.vehicleName)
                        }
                        FormTextRow(label: "Odometer", text: $viewModel.odometerText, placeholder: viewModel.odometerHint ?? "Optional",
                                    unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                        FormTextRow(label: "Note", text: $viewModel.note, placeholder: "Optional")
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).font(DS.Text.subheadline).foregroundStyle(DS.Colors.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SaveButton(title: "Save expense", isBusy: viewModel.isSaving, isEnabled: viewModel.canSave, action: save)
                        .accessibilityIdentifier("expenseSave")
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() { Task { await viewModel.save() } }
}
