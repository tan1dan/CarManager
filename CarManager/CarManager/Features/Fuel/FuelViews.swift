import SwiftUI

struct FuelHistoryView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: FuelHistoryViewModel?

    var body: some View {
        List {
            Text("Fuel")
            switch viewModel?.state {
            case .loading: ProgressView()
            case .loaded(let entries):
                ForEach(entries) { entry in
                    Button("\(entry.station ?? "Fill-up") · \(Int(entry.volume.liters)) L") {
                        model?.router.push(.fuelDetail(entry.id))
                    }
                }
            case .empty: Text("No fill-ups yet")
            case .failed(let error): Text(error.messageKey)
            default: Text("Idle")
            }
        }
        .navigationTitle("Fuel")
        .toolbar {
            Button("Add") { model?.router.present(.fuelEditor(.create(vehicleID))) }
                .accessibilityIdentifier("fuelAdd")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = FuelHistoryViewModel(
                    loadHistory: LoadFuelHistory(fuel: model.dependencies.fuel)
                )
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }
}

struct FuelDetailsView: View {
    let entryID: FuelEntryID
    var body: some View { Text("Fuel Details").navigationTitle("Fill-up") }
}

struct AddFuelView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddFuelViewModel?

    var body: some View {
        Group {
            if let viewModel { AddFuelContentView(viewModel: viewModel) } else { ProgressView() }
        }
        .navigationTitle("Add fuel")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = AddFuelViewModel(
                vehicleID: mode.vehicleID,
                addFuelEntry: AddFuelEntry(
                    fuel: model.dependencies.fuel,
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

private struct AddFuelContentView: View {
    @Bindable var viewModel: AddFuelViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Add Fuel")
            Section("Entry") {
                TextField("Litres", text: $viewModel.volumeText)
                    .accessibilityIdentifier("fuelVolumeField")
                TextField("Total cost", text: $viewModel.totalCostText)
                    .accessibilityIdentifier("fuelCostField")
                TextField("Odometer", text: $viewModel.odometerText)
                    .accessibilityIdentifier("fuelOdometerField")
                // The full-tank flag is load-bearing: the whole consumption algorithm hinges on it.
                Toggle("Full tank", isOn: $viewModel.isFullTank)
                    .accessibilityIdentifier("fuelFullTankToggle")
            }
            Section {
                Button("Save entry") { Task { await viewModel.save() } }
                    .accessibilityIdentifier("fuelSave")
                Button("Cancel") { model?.router.dismissModal() }
            }
            if let error = viewModel.state.error { Section { Text(error.messageKey) } }
        }
    }
}
