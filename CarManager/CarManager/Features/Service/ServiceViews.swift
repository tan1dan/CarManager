import SwiftUI

struct ServiceHistoryView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: ServiceHistoryViewModel?

    var body: some View {
        List {
            Text("Service History")
            switch viewModel?.state {
            case .loading: ProgressView()
            case .loaded(let records):
                ForEach(records) { record in
                    Button("\(record.primaryType.rawValue) · \(record.items.count) item(s)") {
                        model?.router.push(.serviceDetail(record.id))
                    }
                }
            case .empty: Text("No service records")
            case .failed(let error): Text(error.messageKey)
            default: Text("Idle")
            }
        }
        .navigationTitle("Service")
        .toolbar {
            Button("Add") { model?.router.present(.serviceEditor(.create(vehicleID))) }
                .accessibilityIdentifier("serviceAdd")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = ServiceHistoryViewModel(
                    query: QueryServiceHistory(services: model.dependencies.services)
                )
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }
}

struct ServiceDetailsView: View {
    let recordID: ServiceRecordID
    var body: some View { Text("Service Details").navigationTitle("Service record") }
}

struct AddServiceView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddServiceViewModel?

    var body: some View {
        Group {
            if let viewModel { AddServiceContentView(viewModel: viewModel) } else { ProgressView() }
        }
        .navigationTitle("Add service")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = AddServiceViewModel(
                vehicleID: mode.vehicleID,
                addServiceRecord: AddServiceRecord(
                    services: model.dependencies.services,
                    odometer: model.dependencies.odometer,
                    reminders: model.dependencies.reminders,
                    clock: model.dependencies.clock
                ),
                router: model.router,
                currency: model.dependencies.preferences.defaultCurrency,
                now: model.dependencies.clock.now
            )
        }
    }
}

private struct AddServiceContentView: View {
    @Bindable var viewModel: AddServiceViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Add Service")
            Section("Record") {
                TextField("Workshop", text: $viewModel.workshop)
                TextField("Total cost", text: $viewModel.costText)
                    .accessibilityIdentifier("serviceCostField")
            }

            // A service record has MANY items, which is what lets one visit satisfy several
            // reminders at once.
            Section("Include") {
                ForEach(ServiceType.allCases) { type in
                    Button {
                        viewModel.toggle(type)
                    } label: {
                        Text("\(viewModel.selectedTypes.contains(type) ? "✓ " : "")\(type.rawValue)")
                    }
                    .accessibilityIdentifier("serviceType_\(type.rawValue)")
                }
            }

            Section {
                Button("Save") { Task { await viewModel.save() } }
                    .accessibilityIdentifier("serviceSave")
                Button("Cancel") { model?.router.dismissModal() }
            }
            if let error = viewModel.state.error { Section { Text(error.messageKey) } }
        }
    }
}
