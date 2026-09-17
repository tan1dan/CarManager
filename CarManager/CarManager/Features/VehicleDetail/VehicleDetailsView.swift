import SwiftUI

struct VehicleDetailsView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: VehicleDetailsViewModel?

    var body: some View {
        List {
            Section("Vehicle") {
                Text("Vehicle Details")
                switch viewModel?.state {
                case .loading: ProgressView()
                case .loaded(let detail):
                    Text(detail.vehicle.displayName)
                    Text("Mileage: \(Int(detail.currentOdometer?.kilometers ?? 0)) km")
                    Text("Fuel: \(detail.fuelEntryCount) · Service: \(detail.serviceRecordCount) · Docs: \(detail.documentCount)")
                case .failed(let error): Text(error.messageKey)
                default: Text("Idle")
                }
            }

            Section("Details") {
                Button("Service History") { push(.serviceHistory(vehicleID)) }
                    .accessibilityIdentifier("vehicleServiceHistory")
                Button("Fuel History") { push(.fuelHistory(vehicleID)) }
                    .accessibilityIdentifier("vehicleFuelHistory")
                Button("Expenses") { push(.expenses(vehicleID)) }
                    .accessibilityIdentifier("vehicleExpenses")
                Button("Documents") { push(.documents(vehicleID)) }
                    .accessibilityIdentifier("vehicleDocuments")
                Button("Reminders") { push(.reminders(vehicleID)) }
                    .accessibilityIdentifier("vehicleReminders")
                Button("Statistics") { push(.analytics(vehicleID, .year)) }
                    .accessibilityIdentifier("vehicleStatistics")
            }
        }
        .navigationTitle("Vehicle")
        .toolbar {
            Button("Edit") { model?.router.present(.vehicleEditor(.edit(vehicleID))) }
                .accessibilityIdentifier("vehicleEdit")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = VehicleDetailsViewModel(
                    loadDetail: LoadVehicleDetail(
                        vehicles: model.dependencies.vehicles,
                        odometer: model.dependencies.odometer,
                        fuel: model.dependencies.fuel,
                        services: model.dependencies.services,
                        documents: model.dependencies.documents
                    )
                )
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }

    private func push(_ route: AppRoute) { model?.router.push(route) }
}
