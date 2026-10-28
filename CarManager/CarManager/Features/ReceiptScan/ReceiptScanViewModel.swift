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
        // Amounts are kept in the car's currency; the receipt's own is shown alongside.
        currency = draft.conversion?.to ?? draft.total.value?.currency ?? currency
        if let total = draft.total.value {
            totalText = format.decimal(total.amount.doubleValue, digits: 2)
        }
        if let km = draft.odometer.value { odometerText = format.integer(km.kilometers) }
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

    /// How the total relates to what is printed: converted, or needing a manual amount.
    var conversionNote: (text: String, tone: Tone)? {
        guard let draft = original, let conversion = draft.conversion else { return nil }
        let printed = draft.originalTotal.map { format.money($0, fractionDigits: 2) }
        switch conversion.status {
        case .sameCurrency:
            return nil
        case .converted:
            guard let printed, let rate = conversion.rate, let from = conversion.from else { return nil }
            let rateText = format.decimal(rate.doubleValue, digits: 4)
            let when = conversion.rateDate.map { " on \($0)" } ?? ""
            let source = conversion.source.map { $0.hasPrefix("ECB") ? "ECB" : "market" } ?? "published"
            return ("Receipt total \(printed). Converted to \(conversion.to.iso4217) at the \(source) rate 1 \(from.iso4217) = \(rateText) \(conversion.to.iso4217)\(when).", .accent)
        case .rateUnavailable:
            return ("Receipt total \(printed ?? "in another currency"). No exchange rate is available — enter the amount in \(conversion.to.iso4217).", .warning)
        case .unknownCurrency:
            return ("The receipt's currency couldn't be read. Enter the amount in \(conversion.to.iso4217).", .warning)
        }
    }

    /// Jobs and parts read from a workshop invoice, with their price in the car's currency.
    var serviceLines: [(name: String, price: String?)] {
        (original?.serviceItems ?? []).map { item in
            (item.name, item.partCost.map { format.money($0, fractionDigits: 2) })
        }
    }

    /// Plain words for what the reader noticed.
    var warningNotes: [String] {
        guard let warnings = original?.warnings else { return [] }
        return ReceiptWarning.allCases.filter(warnings.contains).compactMap { warning in
            switch warning {
            case .blurry, .faded: "The photo is hard to read — check every value."
            case .cutOff: "Part of the receipt is cut off."
            case .handwritten: "Handwritten receipt — check the amounts."
            case .multipleReceipts: "More than one receipt in the photo; only one was read."
            case .refund: "This looks like a refund."
            case .mathMismatch: "Litres × price doesn't match the amount on the receipt."
            case .tipIncluded: "The total includes a tip."
            case .notCarRelated: "This doesn't look car-related."
            case .partialPayment: "Only part of the bill seems to be paid here."
            case .unreadable: "Most of the receipt couldn't be read."
            case .readOnDevice: "No connection — read on this iPhone only, so fewer details were found."
            case .foreignCurrency: nil
            }
        }
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
