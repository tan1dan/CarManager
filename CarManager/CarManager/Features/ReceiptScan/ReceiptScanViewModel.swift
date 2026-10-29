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
            let to = conversion.to.iso4217
            let isECB = conversion.source?.hasPrefix("ECB") ?? false
            var text = isECB
                ? String(localized: "Receipt total \(printed). Converted to \(to) at the ECB rate 1 \(from.iso4217) = \(rateText) \(to).")
                : String(localized: "Receipt total \(printed). Converted to \(to) at the market rate 1 \(from.iso4217) = \(rateText) \(to).")
            if let date = conversion.rateDate { text += " " + String(localized: "Rate of \(date).") }
            return (text, .accent)
        case .rateUnavailable:
            let text = printed.map { String(localized: "Receipt total \($0). No exchange rate is available — enter the amount in \(conversion.to.iso4217).") }
                ?? String(localized: "The receipt is in another currency. No exchange rate is available — enter the amount in \(conversion.to.iso4217).")
            return (text, .warning)
        case .unknownCurrency:
            return (String(localized: "The receipt's currency couldn't be read. Enter the amount in \(conversion.to.iso4217)."), .warning)
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
            case .blurry, .faded: String(localized: "The photo is hard to read — check every value.")
            case .cutOff: String(localized: "Part of the receipt is cut off.")
            case .handwritten: String(localized: "Handwritten receipt — check the amounts.")
            case .multipleReceipts: String(localized: "More than one receipt in the photo; only one was read.")
            case .refund: String(localized: "This looks like a refund.")
            case .mathMismatch: String(localized: "Litres × price doesn't match the amount on the receipt.")
            case .tipIncluded: String(localized: "The total includes a tip.")
            case .notCarRelated: String(localized: "This doesn't look car-related.")
            case .partialPayment: String(localized: "Only part of the bill seems to be paid here.")
            case .unreadable: String(localized: "Most of the receipt couldn't be read.")
            case .readOnDevice: String(localized: "No connection — read on this iPhone only, so fewer details were found.")
            case .foreignCurrency: nil
            }
        }
    }

    /// The least certain field the user should look at, if any.
    var lowConfidenceField: String? {
        let names: [(Field, String)] = [(.total, String(localized: "Total")), (.date, String(localized: "Date")), (.vendor, String(localized: "Merchant")), (.category, String(localized: "Category"))]
        return names.first { (confidences[$0.0] ?? 0) < 0.6 }?.1
    }

    var saveTitle: String {
        switch kind {
        case .fuel: String(localized: "Save as fuel")
        case .service: String(localized: "Save as service")
        case .expense: String(localized: "Save as expense")
        }
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
