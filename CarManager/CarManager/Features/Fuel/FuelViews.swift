import SwiftUI

/// Fuel History, built from Figma 12 (and 24 when empty).
struct FuelHistoryView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: FuelHistoryViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "Fuel", onBack: { model?.router.pop() }) {
                    CircleIconButton(symbol: "plus", accessibilityLabel: "Add fuel") { add() }
                        .accessibilityIdentifier("fuelAdd")
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

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let p):
            if let chart = p.chart { chartCard(chart) } else {
                InfoBanner(symbol: "chart.line.uptrend.xyaxis", text: "Log two full tanks and the app starts showing your consumption.", tone: .neutral)
            }
            VStack(spacing: 8) {
                Eyebrow(text: "Fill-ups")
                RowGroup(items: p.rows) { row in
                    RecordRow(symbol: "fuelpump", iconStyle: .accent, title: row.title, subtitle: row.subtitle, value: row.amount, showsChevron: false)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await viewModel?.delete(row.id, vehicleID: vehicleID) }
                            }
                        }
                }
            }
        case .empty:
            EmptyStateView(symbol: "drop", title: "No fill-ups yet",
                           message: "Log a fill-up and the app starts showing consumption and cost per 100 km.",
                           actionTitle: "Add fuel", action: add)
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load fuel", message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }

    private func chartCard(_ chart: FuelHistoryPresentation.Chart) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Avg. consumption")
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(chart.value).font(.system(size: 32, weight: .bold)).tracking(-0.8).foregroundStyle(.white)
                        Text(chart.unit).font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                Spacer()
                if let change = chart.change { Chip(text: change, tone: chart.changeTone) }
            }
            .padding(.bottom, 16)
            TrendLineChart(values: chart.points, labels: chart.labels)
                .frame(height: 104)
        }
        .padding(20)
        .dsSurface()
    }

    private func add() { model?.router.present(.fuelEditor(.create(vehicleID))) }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            let d = model.dependencies
            viewModel = FuelHistoryViewModel(
                loadAnalytics: LoadVehicleAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services, expenses: d.expenses, odometer: d.odometer, clock: d.clock),
                deleteEntry: DeleteFuelEntry(fuel: d.fuel, odometer: d.odometer),
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                clock: d.clock
            )
        }
        await viewModel?.load(vehicleID: vehicleID)
    }
}

struct FuelDetailsView: View {
    let entryID: FuelEntryID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: "Fill-up", onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}

/// Add Fuel, built from Figma 10.
struct AddFuelView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddFuelViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel { AddFuelContentView(viewModel: viewModel) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            let created = AddFuelViewModel(
                vehicleID: mode.vehicleID,
                addFuelEntry: AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: d.clock),
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

private struct AddFuelContentView: View {
    @Bindable var viewModel: AddFuelViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorTopBar(title: "Add Fuel", trailingEnabled: viewModel.canSave,
                             onLeading: viewModel.cancel, onTrailing: save)
                VStack(spacing: 16) {
                    HeroAmountField(caption: "Total cost", currencySymbol: viewModel.format.currencySymbol(viewModel.currency),
                                    amount: $viewModel.totalCostText, meta: viewModel.meta)
                        .accessibilityIdentifier("fuelCostField")
                    FormSurface {
                        FormTextRow(label: "Litres", text: $viewModel.volumeText, placeholder: "0", unit: "L", keyboard: .decimalPad, isFirst: true)
                            .accessibilityIdentifier("fuelVolumeField")
                        FormDateRow(label: "Date", date: $viewModel.date, range: Date.distantPast...viewModel.now)
                        FormTextRow(label: "Odometer", text: $viewModel.odometerText, placeholder: viewModel.odometerHint ?? "0", unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            .accessibilityIdentifier("fuelOdometerField")
                        FormTextRow(label: "Station", text: $viewModel.station, placeholder: "Optional")
                        // The full-tank flag is load-bearing: consumption is only measurable
                        // between two full fills.
                        FormToggleRow(label: "Full tank", isOn: $viewModel.isFullTank)
                            .accessibilityIdentifier("fuelFullTankToggle")
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).font(DS.Text.subheadline).foregroundStyle(DS.Colors.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SaveButton(title: "Save entry", isBusy: viewModel.isSaving, isEnabled: viewModel.canSave, action: save)
                        .accessibilityIdentifier("fuelSave")
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() { Task { await viewModel.save() } }
}
