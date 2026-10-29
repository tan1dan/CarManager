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
                ScanMessageView(symbol: "car", title: String(localized: "Add a vehicle first"),
                                message: String(localized: "A receipt is saved to a vehicle."), primaryTitle: String(localized: "Close"), primary: close)
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
            CaptureScreen(title: String(localized: "Scan receipt"), symbol: "dollarsign.square",
                          hint: String(localized: "Fit the whole receipt in the frame. Good light helps."),
                          onClose: close, onImage: viewModel.analyze)

        case .recognizing, .analyzing:
            ScanProcessingView(imageData: viewModel.imageData, title: String(localized: "Reading the receipt…"),
                               subtitle: String(localized: "Amounts in another currency are converted at the official rate."))
                .accessibilityIdentifier("receiptProcessing")

        case .awaitingReview, .editing, .confirming:
            ReceiptReviewForm(viewModel: viewModel, close: close)

        case .saved:
            ScanMessageView(symbol: "checkmark", title: String(localized: "Saved"),
                            message: String(localized: "The record is in your vehicle's history."), primaryTitle: String(localized: "Done"), primary: close)
                .accessibilityIdentifier("receiptDone")

        case .failed(let message, _):
            ScanMessageView(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't read it"), message: message,
                            primaryTitle: String(localized: "Try again"), primary: viewModel.reset,
                            secondaryTitle: String(localized: "Enter manually")) {
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
                EditorTopBar(title: String(localized: "Review receipt"), leading: String(localized: "Discard"), trailingEnabled: viewModel.canSave,
                             onLeading: close, onTrailing: save)
                VStack(spacing: 16) {
                    InfoBanner(symbol: "exclamationmark.shield",
                               text: String(localized: "Check before saving. These values were read from the photo and may be wrong."),
                               tone: .warning)
                    if let note = viewModel.conversionNote {
                        InfoBanner(symbol: note.tone == .warning ? "exclamationmark.triangle" : "arrow.left.arrow.right",
                                   text: note.text, tone: note.tone)
                            .accessibilityIdentifier("receiptConversion")
                    }
                    ForEach(viewModel.warningNotes, id: \.self) { note in
                        InfoBanner(symbol: "exclamationmark.circle", text: note, tone: .neutral)
                    }
                    if let data = viewModel.imageData, let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                    // A filled photo overflows its frame; clipping hides that but does not stop the
                    // overflow catching taps (it sat over the Back button).
                    .allowsHitTesting(false)
                            .frame(height: 140).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(DS.Colors.hairline))
                            .accessibilityLabel("Receipt photo")
                    }
                    VStack(spacing: 8) {
                        Eyebrow(text: String(localized: "Extracted"))
                        FormSurface {
                            FormMenuRow(label: String(localized: "Save as"), options: [(.expense, String(localized: "Expense")), (.fuel, String(localized: "Fuel")), (.service, String(localized: "Service"))],
                                        selection: $viewModel.kind, isFirst: true)
                            FormTextRow(label: String(localized: "Merchant"), text: $viewModel.vendor, placeholder: String(localized: "Optional"))
                            FormDateRow(label: String(localized: "Date"), date: $viewModel.date, range: Date.distantPast...Date.now)
                            FormTextRow(label: String(localized: "Total"), text: $viewModel.totalText, placeholder: "0",
                                        unit: viewModel.format.currencySymbol(viewModel.currency), keyboard: .decimalPad)
                                .accessibilityIdentifier("receiptTotalField")
                            switch viewModel.kind {
                            case .expense:
                                FormMenuRow(label: String(localized: "Category"),
                                            options: ExpenseCategory.allCases.filter { $0 != .fuel }.map { ($0, $0.displayName) },
                                            selection: $viewModel.category)
                            case .fuel:
                                FormTextRow(label: String(localized: "Litres"), text: $viewModel.litresText, placeholder: String(localized: "Required"), unit: String(localized: "L", comment: "Litres, unit symbol"), keyboard: .decimalPad)
                                FormTextRow(label: String(localized: "Odometer"), text: $viewModel.odometerText, placeholder: String(localized: "Required"),
                                            unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            case .service:
                                FormTextRow(label: String(localized: "Odometer"), text: $viewModel.odometerText, placeholder: String(localized: "Optional"),
                                            unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            }
                        }
                    }
                    if viewModel.kind == .service, !viewModel.serviceLines.isEmpty {
                        VStack(spacing: 8) {
                            Eyebrow(text: String(localized: "On the invoice"))
                            VStack(spacing: 0) {
                                ForEach(Array(viewModel.serviceLines.enumerated()), id: \.offset) { index, line in
                                    FormValueRow(label: line.name, value: line.price ?? "", isFirst: index == 0)
                                }
                            }
                            .dsSurface()
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
                    SaveButton(title: viewModel.saveTitle, isBusy: viewModel.isSaving,
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
                    // A filled photo overflows its frame; clipping hides that but does not stop the
                    // overflow catching taps (it sat over the Back button).
                    .allowsHitTesting(false)
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
        ScanMessageView(symbol: "doc.text.magnifyingglass", title: String(localized: "Nothing to review"),
                        message: String(localized: "This scan was already saved or discarded."), primaryTitle: String(localized: "Close")) {
            model?.router.dismissModal()
        }
        .background(DS.Colors.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
