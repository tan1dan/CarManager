import Foundation
import Observation

/// Receipt scan: Capture (Figma 32) → Processing → Review (33) → Save.
///
/// The review step is where a person checks every value. Saving goes through
/// `ConfirmedReceipt`, which cannot be built from an unreviewed draft.
@MainActor
@Observable
final class ReceiptScanViewModel {
    private(set) var scanState: ReceiptScanState = .capturing
    private(set) var imageData: Data?
    private(set) var errorMessage: String?
    private(set) var isSaving = false

    // Editable review fields, filled from the draft.
    var kind: RecordKind = .expense
    var vendor = ""
    var date: Date
    var totalText = ""
    var category: ExpenseCategory = .other
    var litresText = ""
    var odometerText = ""
    private(set) var currency: CurrencyCode = .eur
    private(set) var confidences: [Field: Double] = [:]
    private var original: ReceiptDraft?

    enum Field: Hashable { case vendor, date, total, category, litres }

    private let vehicleID: VehicleID
    private let scanReceipt: ScanReceipt
    private let confirmReceiptScan: ConfirmReceiptScan
    private let clock: any ClockProviding
    private var task: Task<Void, Never>?
    let format: DisplayFormat

    init(
        vehicleID: VehicleID, scanReceipt: ScanReceipt,
        confirmReceiptScan: ConfirmReceiptScan, format: DisplayFormat, clock: any ClockProviding
    ) {
        self.vehicleID = vehicleID
        self.scanReceipt = scanReceipt
        self.confirmReceiptScan = confirmReceiptScan
        self.format = format
        self.clock = clock
        self.date = clock.now
    }

    func analyze(_ data: Data) {
        imageData = data
        errorMessage = nil
        scanState = .analyzing(imageRef: FileRef(relativePath: "pending"))
        task = Task {
            do {
                // ScanReceipt STOPS at .awaitingReview. It holds no financial repository,
                // so it cannot write a record even if it wanted to.
                let scan = try await scanReceipt(imageData: data, vehicleID: vehicleID)
                fill(from: scan.draft)
                scanState = .awaitingReview(scan)
            } catch {
                scanState = .failed(message: UserMessage.text(for: error), retryable: true)
            }
        }
    }

    private func fill(from draft: ReceiptDraft) {
        original = draft
        kind = draft.suggestedRecordKind == .service ? .service : draft.suggestedRecordKind
        vendor = draft.vendor.value ?? ""
        date = draft.date.value ?? clock.now
        if let total = draft.total.value {
            currency = total.currency
            totalText = format.decimal(total.amount.doubleValue, digits: 2)
        }
        category = draft.expenseCategory.value ?? .other
        litresText = draft.fuelVolume.value.map { format.decimal($0.liters, digits: 2) } ?? ""
        confidences = [
            .vendor: draft.vendor.value == nil ? 0 : draft.vendor.confidence,
            .date: draft.date.value == nil ? 0 : draft.date.confidence,
            .total: draft.total.value == nil ? 0 : draft.total.confidence,
            .category: draft.expenseCategory.confidence,
            .litres: draft.fuelVolume.value == nil ? 0 : draft.fuelVolume.confidence
        ]
    }

    /// The least certain field the user should look at, if any.
    var lowConfidenceField: String? {
        let names: [(Field, String)] = [(.total, "Total"), (.date, "Date"), (.vendor, "Merchant"), (.category, "Category")]
        return names.first { (confidences[$0.0] ?? 0) < 0.6 }?.1
    }

    var canSave: Bool {
        guard (NumberInput.decimal(totalText) ?? 0) > 0, !isSaving else { return false }
        if kind == .fuel {
            return (NumberInput.double(litresText) ?? 0) > 0 && (NumberInput.double(odometerText) ?? 0) > 0
        }
        return true
    }

    func confirm() async {
        guard case .awaitingReview(var scan) = scanState, canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        // What the person saw and left alone is accepted; what they changed is an edit.
        // Either way, every value below passed through this review screen.
        var draft = scan.draft
        draft.suggestedRecordKind = kind
        draft.total.edit(to: Money(NumberInput.decimal(totalText) ?? 0, currency))
        draft.date.edit(to: date)
        let trimmedVendor = vendor.trimmingCharacters(in: .whitespaces)
        if !trimmedVendor.isEmpty { draft.vendor.edit(to: trimmedVendor) }
        draft.expenseCategory.edit(to: kind == .fuel ? .fuel : category)
        if kind == .fuel {
            draft.fuelVolume.edit(to: Volume(liters: NumberInput.double(litresText) ?? 0))
        }
        if let km = NumberInput.double(odometerText), km > 0 { draft.odometer.edit(to: Odometer(kilometers: km)) }
        scan.draft = draft
        scanState = .confirming(scan)

        guard let confirmed = ConfirmedReceipt(reviewing: scan, at: clock.now) else {
            scanState = .awaitingReview(scan)
            return
        }
        do {
            let ref = try await confirmReceiptScan(confirmed)
            scanState = .saved(ref)
        } catch {
            errorMessage = UserMessage.text(for: error)
            scanState = .awaitingReview(scan)
        }
    }

    func discard() {
        task?.cancel()
        scanState = .discarded
    }

    func reset() {
        imageData = nil
        errorMessage = nil
        scanState = .capturing
    }
}
