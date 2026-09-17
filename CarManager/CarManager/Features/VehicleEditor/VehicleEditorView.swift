import SwiftUI

/// Add and Edit share one editor — the mode distinguishes them.
struct VehicleEditorView: View {
    let mode: VehicleEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: VehicleEditorViewModel?

    var body: some View {
        Group {
            if let viewModel {
                VehicleEditorContentView(viewModel: viewModel, mode: mode)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(isCreating ? "Add vehicle" : "Edit vehicle")
        .task {
            guard viewModel == nil, let model else { return }
            let created = VehicleEditorViewModel(
                mode: mode,
                createVehicle: CreateVehicle(
                    vehicles: model.dependencies.vehicles,
                    odometer: model.dependencies.odometer,
                    reminders: model.dependencies.reminders,
                    clock: model.dependencies.clock
                ),
                updateVehicle: UpdateVehicle(
                    vehicles: model.dependencies.vehicles, clock: model.dependencies.clock
                ),
                vehicles: model.dependencies.vehicles,
                vehicleStore: model.vehicles,
                featureGate: model.featureGate,
                router: model.router
            )
            viewModel = created
            await created.prepare()
        }
    }

    private var isCreating: Bool { if case .create = mode { return true }; return false }
}

private struct VehicleEditorContentView: View {
    @Bindable var viewModel: VehicleEditorViewModel
    let mode: VehicleEditorMode
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text(isCreating ? "Add Vehicle" : "Edit Vehicle")

            Section("Details") {
                TextField("Brand", text: $viewModel.draft.brand)
                    .accessibilityIdentifier("vehicleBrandField")
                TextField("Model", text: $viewModel.draft.model)
                    .accessibilityIdentifier("vehicleModelField")
                // Still a placeholder editor — these two exist because the domain records
                // them and the Garage card displays them.
                TextField("Year", value: $viewModel.draft.year, format: .number.grouping(.never))
                    .accessibilityIdentifier("vehicleYearField")
                // Raw text goes into the draft; CreateVehicle/UpdateVehicle normalise it, so
                // typing is never fought mid-keystroke.
                TextField("VIN (optional)", text: Binding(
                    get: { viewModel.draft.vin ?? "" },
                    set: { viewModel.draft.vin = $0 }
                ))
                .accessibilityIdentifier("vehicleVINField")
                Picker("Fuel type", selection: $viewModel.draft.fuelType) {
                    ForEach(FuelType.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            Section {
                Button("Scan license plate") {
                    model?.router.presentFullScreen(.camera(.plate))
                }
                .accessibilityIdentifier("vehicleScanPlate")
            }

            Section {
                Button(isCreating ? "Add to garage" : "Save") {
                    Task { await viewModel.save() }
                }
                .accessibilityIdentifier("vehicleSave")
                Button("Cancel") { model?.router.dismissModal() }
            }

            if let error = viewModel.state.error {
                Section { Text(error.messageKey).accessibilityIdentifier("vehicleEditorError") }
            }
        }
    }

    private var isCreating: Bool { if case .create = mode { return true }; return false }
}
