import SwiftUI

/// The receipt flow, with its states kept explicitly separate:
///
///   Capture → Processing → Review → Confirmation → Save
///
/// The state machine itself lives in the Domain (`ReceiptScanState`), not in this ViewModel.
struct ReceiptScanFlowView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: ReceiptScanViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel {
                ReceiptScanContentView(viewModel: viewModel) { close() }
            } else if model?.selectedVehicleID == nil {
                ScanMessageView(symbol: "car", title: "Add a vehicle first",
                                message: "A receipt is saved to a vehicle.", primaryTitle: "Close", primary: close)
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model, let vehicleID = model.selectedVehicleID else { return }
            let d = model.dependencies
            viewModel = ReceiptScanViewModel(
                vehicleID: vehicleID,
                scanReceipt: ScanReceipt(vision: d.vision, textRecognizer: d.textRecognizer, preprocessor: d.imagePreprocessor,
                                         files: d.files, scans: d.scans, clock: d.clock),
                confirmReceiptScan: ConfirmReceiptScan(
                    addFuel: AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: d.clock),
                    addService: AddServiceRecord(services: d.services, odometer: d.odometer, reminders: d.reminders, clock: d.clock),
                    addExpense: AddExpense(expenses: d.expenses, odometer: d.odometer, clock: d.clock),
                    scans: d.scans, vehicles: d.vehicles
                ),
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                clock: d.clock
            )
        }
    }

    private func close() {
        viewModel?.discard()
        model?.router.dismissFullScreen()
    }
}

/// Takes a NON-OPTIONAL @Bindable view model. Binding through an optional inside
/// `Binding(get:set:)` breaks Observation tracking, because the read happens outside the
/// observed `body` scope.
private struct ReceiptScanContentView: View {
    @Bindable var viewModel: ReceiptScanViewModel
    let close: () -> Void
    @Environment(\.appModel) private var model

    var body: some View {
        switch viewModel.scanState {
        case .capturing:
            CaptureScreen(title: "Scan receipt", symbol: "dollarsign.square",
                          hint: "Fit the whole receipt in the frame. Good light helps.",
                          onClose: close, onImage: viewModel.analyze)

        case .recognizing, .analyzing:
            ScanProcessingView(imageData: viewModel.imageData, title: "Reading the receipt…",
                               subtitle: "Text is recognised on this iPhone.")
                .accessibilityIdentifier("receiptProcessing")

        case .awaitingReview, .editing, .confirming:
            ReceiptReviewForm(viewModel: viewModel, close: close)

        case .saved:
            ScanMessageView(symbol: "checkmark", title: "Saved",
                            message: "The record is in your vehicle's history.", primaryTitle: "Done", primary: close)
                .accessibilityIdentifier("receiptDone")

        case .failed(let message, _):
            ScanMessageView(symbol: "exclamationmark.triangle", title: "Couldn't read it", message: message,
                            primaryTitle: "Try again", primary: viewModel.reset,
                            secondaryTitle: "Enter manually") {
                close()
                if let id = model?.selectedVehicleID { model?.router.present(.expenseEditor(.create(id))) }
            }

        case .discarded:
            Color.clear
        }
    }
}

/// Review receipt, built from Figma 33. Nothing is saved until "Save" here.
private struct ReceiptReviewForm: View {
    @Bindable var viewModel: ReceiptScanViewModel
    let close: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorTopBar(title: "Review receipt", leading: "Discard", trailingEnabled: viewModel.canSave,
                             onLeading: close, onTrailing: save)
                VStack(spacing: 16) {
                    InfoBanner(symbol: "exclamationmark.shield",
                               text: "Check before saving. These values were read from the photo and may be wrong.",
                               tone: .warning)
                    if let data = viewModel.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(height: 140).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DS.Colors.hairline))
                            .accessibilityLabel("Receipt photo")
                    }
                    VStack(spacing: 8) {
                        Eyebrow(text: "Extracted")
                        FormSurface {
                            FormMenuRow(label: "Save as", options: [(.expense, "Expense"), (.fuel, "Fuel"), (.service, "Service")],
                                        selection: $viewModel.kind, isFirst: true)
                            FormTextRow(label: "Merchant", text: $viewModel.vendor, placeholder: "Optional")
                            FormDateRow(label: "Date", date: $viewModel.date, range: Date.distantPast...Date.now)
                            FormTextRow(label: "Total", text: $viewModel.totalText, placeholder: "0",
                                        unit: viewModel.format.currencySymbol(viewModel.currency), keyboard: .decimalPad)
                                .accessibilityIdentifier("receiptTotalField")
                            switch viewModel.kind {
                            case .expense:
                                FormMenuRow(label: "Category",
                                            options: ExpenseCategory.allCases.filter { $0 != .fuel }.map { ($0, $0.displayName) },
                                            selection: $viewModel.category)
                            case .fuel:
                                FormTextRow(label: "Litres", text: $viewModel.litresText, placeholder: "Required", unit: "L", keyboard: .decimalPad)
                                FormTextRow(label: "Odometer", text: $viewModel.odometerText, placeholder: "Required",
                                            unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            case .service:
                                FormTextRow(label: "Odometer", text: $viewModel.odometerText, placeholder: "Optional",
                                            unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            }
                        }
                    }
                    if let field = viewModel.lowConfidenceField {
                        Text("Low confidence on \(field) — check it before saving.")
                            .font(DS.Text.caption).foregroundStyle(DS.Colors.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = viewModel.errorMessage {
                        Text(error).font(DS.Text.subheadline).foregroundStyle(DS.Colors.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SaveButton(title: "Save as \(viewModel.kind.rawValue)", isBusy: viewModel.isSaving,
                               isEnabled: viewModel.canSave, action: save)
                        .accessibilityIdentifier("receiptConfirm")
                    Button(action: close) {
                        Label("Discard", systemImage: "xmark")
                            .font(DS.Text.rowTitle)
                            .foregroundStyle(DS.Colors.danger)
                            .frame(maxWidth: .infinity)
                            .frame(height: DS.Layout.buttonHeight)
                            .background(Capsule().fill(DS.Colors.danger.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("receiptDiscard")
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() { Task { await viewModel.confirm() } }
}

/// The photo, dimmed, with a spinner — shared by every scan.
struct ScanProcessingView: View {
    let imageData: Data?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(Color.white.opacity(0.03))
                if let imageData, let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius))
                        .opacity(0.35)
                }
                ProgressView().controlSize(.large).tint(.white)
            }
            .frame(height: 360)
            .clipped()
            VStack(spacing: 4) {
                Text(title).font(DS.Text.section).foregroundStyle(.white)
                if let subtitle { Text(subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary) }
            }
            Spacer()
        }
        .padding(DS.Layout.gutter)
        .padding(.top, 40)
    }
}

/// A centred outcome: saved, failed, nothing to do.
struct ScanMessageView: View {
    let symbol: String
    let title: String
    let message: String
    let primaryTitle: String
    let primary: () -> Void
    var secondaryTitle: String?
    var secondary: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            EmptyStateView(symbol: symbol, title: title, message: message, actionTitle: primaryTitle, action: primary)
            if let secondaryTitle, let secondary {
                Button(secondaryTitle, action: secondary)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Layout.gutter)
    }
}

/// Reached from `ModalRoute.receiptReview` when a scan was started elsewhere. Scans are kept
/// only in memory until confirmed, so an old link has nothing left to review.
struct ReceiptReviewView: View {
    let scanID: ReceiptScanID
    @Environment(\.appModel) private var model

    var body: some View {
        ScanMessageView(symbol: "doc.text.magnifyingglass", title: "Nothing to review",
                        message: "This scan was already saved or discarded.", primaryTitle: "Close") {
            model?.router.dismissModal()
        }
        .background(DS.Colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
