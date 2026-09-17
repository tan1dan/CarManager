import SwiftUI

/// The receipt flow, with its states kept explicitly separate:
///
///   Capture → Processing → Result → Review → Confirmation → Save
///
/// The state machine itself lives in the Domain (`ReceiptScanState`), not in this ViewModel.
struct ReceiptScanFlowView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: ReceiptScanViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    ReceiptScanContentView(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Scan Receipt")
            .toolbar {
                Button("Close") {
                    viewModel?.discard()
                    model?.router.dismissFullScreen()
                }
                .accessibilityIdentifier("receiptClose")
            }
        }
        .task {
            guard viewModel == nil, let model, let vehicleID = model.selectedVehicleID else { return }
            viewModel = ReceiptScanViewModel(
                vehicleID: vehicleID,
                scanReceipt: ScanReceipt(
                    vision: model.dependencies.vision,
                    textRecognizer: model.dependencies.textRecognizer,
                    preprocessor: model.dependencies.imagePreprocessor,
                    files: model.dependencies.files,
                    scans: model.dependencies.scans,
                    clock: model.dependencies.clock
                ),
                confirmReceiptScan: ConfirmReceiptScan(
                    addFuel: AddFuelEntry(
                        fuel: model.dependencies.fuel,
                        odometer: model.dependencies.odometer,
                        clock: model.dependencies.clock
                    ),
                    addService: AddServiceRecord(
                        services: model.dependencies.services,
                        odometer: model.dependencies.odometer,
                        reminders: model.dependencies.reminders,
                        clock: model.dependencies.clock
                    ),
                    addExpense: AddExpense(
                        expenses: model.dependencies.expenses,
                        odometer: model.dependencies.odometer,
                        clock: model.dependencies.clock
                    ),
                    scans: model.dependencies.scans
                ),
                clock: model.dependencies.clock
            )
        }
    }
}

/// Takes a NON-OPTIONAL @Bindable view model. Binding through an optional inside
/// `Binding(get:set:)` breaks Observation tracking, because the read happens outside the
/// observed `body` scope.
private struct ReceiptScanContentView: View {
    @Bindable var viewModel: ReceiptScanViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        switch viewModel.scanState {
        case .capturing:
            VStack(spacing: 12) {
                Text("Receipt Capture")
                Button("Capture") { viewModel.capture() }
                    .accessibilityIdentifier("receiptCapture")
            }
        case .recognizing, .analyzing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Receipt Processing")
            }
            .accessibilityIdentifier("receiptProcessing")

        case .awaitingReview(let scan), .editing(let scan), .confirming(let scan):
            reviewForm(scan)

        case .saved:
            VStack(spacing: 12) {
                Text("Receipt Saved")
                Button("Done") { model?.router.dismissFullScreen() }
                    .accessibilityIdentifier("receiptDone")
            }
        case .failed(let message, _):
            VStack(spacing: 12) {
                Text("Receipt scan failed")
                Text(message)
                Button("Retry") { viewModel.reset() }
                Button("Enter manually") {
                    model?.router.dismissFullScreen()
                    if let id = model?.selectedVehicleID {
                        model?.router.present(.expenseEditor(.create(id)))
                    }
                }
            }
        case .discarded:
            Text("Discarded")
        }
    }

    /// Result + Review + Confirmation in one form. NOTHING is persisted here: "Confirm and save"
    /// requires a `ConfirmedReceipt`, which cannot be built from an unreviewed draft.
    private func reviewForm(_ scan: ReceiptScan) -> some View {
        Form {
            Section("Receipt Result") {
                Text("Vendor: \(scan.draft.vendor.value ?? "—")")
                Text("Kind: \(scan.draft.suggestedRecordKind.rawValue)")
            }

            Section("Review") {
                Text("Receipt Review")
                Toggle("Accept total", isOn: $viewModel.acceptedTotal)
                    .accessibilityIdentifier("receiptAcceptTotal")
                Toggle("Accept date", isOn: $viewModel.acceptedDate)
                    .accessibilityIdentifier("receiptAcceptDate")
            }

            Section("Confirmation") {
                Text("Receipt Confirmation")
                Button("Confirm and save") { Task { await viewModel.confirm() } }
                    .disabled(!viewModel.canConfirm)
                    .accessibilityIdentifier("receiptConfirm")
                Button("Discard") { viewModel.discard() }
                    .accessibilityIdentifier("receiptDiscard")
            }
        }
    }
}

/// Reached from `ModalRoute.receiptReview` — the same review step, presented as a sheet
/// when the scan was started elsewhere.
struct ReceiptReviewView: View {
    let scanID: ReceiptScanID
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Receipt Review")
            Button("Close") { model?.router.dismissModal() }
        }
        .navigationTitle("Review receipt")
    }
}
