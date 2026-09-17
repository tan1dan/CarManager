import Foundation

public enum RecordKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case fuel, service, expense
    public var id: String { rawValue }
}

/// Every AI-extracted field carries its confidence and whether a human has accepted it.
/// Nothing is silently trusted.
public struct FieldSuggestion<T: Hashable & Sendable>: Hashable, Sendable {
    public var value: T?
    public var confidence: Double
    public var wasEditedByUser: Bool
    public var isAccepted: Bool

    public init(value: T? = nil, confidence: Double = 0, wasEditedByUser: Bool = false, isAccepted: Bool = false) {
        self.value = value; self.confidence = confidence
        self.wasEditedByUser = wasEditedByUser; self.isAccepted = isAccepted
    }

    public mutating func accept() { isAccepted = true }
    public mutating func edit(to newValue: T) {
        value = newValue; wasEditedByUser = true; isAccepted = true
    }
}

public struct ReceiptDraft: Hashable, Sendable {
    public var suggestedRecordKind: RecordKind
    public var vendor: FieldSuggestion<String>
    public var date: FieldSuggestion<Date>
    public var total: FieldSuggestion<Money>
    public var odometer: FieldSuggestion<Odometer>
    public var expenseCategory: FieldSuggestion<ExpenseCategory>
    public var fuelVolume: FieldSuggestion<Volume>
    public var serviceItems: [ServiceItem]

    public init(
        suggestedRecordKind: RecordKind = .expense,
        vendor: FieldSuggestion<String> = .init(),
        date: FieldSuggestion<Date> = .init(),
        total: FieldSuggestion<Money> = .init(),
        odometer: FieldSuggestion<Odometer> = .init(),
        expenseCategory: FieldSuggestion<ExpenseCategory> = .init(),
        fuelVolume: FieldSuggestion<Volume> = .init(),
        serviceItems: [ServiceItem] = []
    ) {
        self.suggestedRecordKind = suggestedRecordKind
        self.vendor = vendor; self.date = date; self.total = total; self.odometer = odometer
        self.expenseCategory = expenseCategory; self.fuelVolume = fuelVolume
        self.serviceItems = serviceItems
    }

    /// The minimum a user must have reviewed before a record may be created.
    public var hasRequiredAcceptedFields: Bool {
        total.isAccepted && total.value != nil && date.isAccepted && date.value != nil
    }
}

public enum ScanStatus: Hashable, Sendable {
    case analyzing
    case awaitingReview
    case confirmed(RecordRef)
    case discarded
}

public enum RecordRef: Hashable, Sendable {
    case fuel(FuelEntryID)
    case service(ServiceRecordID)
    case expense(ExpenseID)
}

public struct ReceiptScan: Identifiable, Hashable, Sendable {
    public let id: ReceiptScanID
    public let vehicleID: VehicleID
    public let imageRef: FileRef
    public let recognizedText: String?
    public var draft: ReceiptDraft
    public var status: ScanStatus
    public let createdAt: Date

    public init(
        id: ReceiptScanID = ReceiptScanID(), vehicleID: VehicleID, imageRef: FileRef,
        recognizedText: String? = nil, draft: ReceiptDraft,
        status: ScanStatus = .awaitingReview, createdAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.imageRef = imageRef
        self.recognizedText = recognizedText; self.draft = draft
        self.status = status; self.createdAt = createdAt
    }
}

/// The explicit product-mandated flow. Persistence is NOT reachable from the scanning states.
public enum ReceiptScanState: Hashable, Sendable {
    case capturing
    case recognizing(imageRef: FileRef)
    case analyzing(imageRef: FileRef)
    /// Persistence is impossible from here.
    case awaitingReview(ReceiptScan)
    case editing(ReceiptScan)
    case confirming(ReceiptScan)
    case saved(RecordRef)
    case failed(message: String, retryable: Bool)
    case discarded
}

/// Constructible ONLY from a reviewed draft. `ConfirmReceiptScan` requires this type, so
/// "save without confirmation" is unrepresentable rather than merely discouraged.
public struct ConfirmedReceipt: Sendable {
    public let scanID: ReceiptScanID
    public let vehicleID: VehicleID
    public let kind: RecordKind
    public let total: Money
    public let date: Date
    public let odometer: Odometer?
    public let vendor: String?
    public let expenseCategory: ExpenseCategory
    public let fuelVolume: Volume?
    public let serviceItems: [ServiceItem]
    public let confirmedAt: Date

    /// Failable by design: returns nil unless every required field has been accepted by a human.
    public init?(reviewing scan: ReceiptScan, at date: Date) {
        guard scan.draft.hasRequiredAcceptedFields,
              let total = scan.draft.total.value,
              let receiptDate = scan.draft.date.value
        else { return nil }

        self.scanID = scan.id
        self.vehicleID = scan.vehicleID
        self.kind = scan.draft.suggestedRecordKind
        self.total = total
        self.date = receiptDate
        self.odometer = scan.draft.odometer.isAccepted ? scan.draft.odometer.value : nil
        self.vendor = scan.draft.vendor.value
        self.expenseCategory = scan.draft.expenseCategory.value ?? .other
        self.fuelVolume = scan.draft.fuelVolume.isAccepted ? scan.draft.fuelVolume.value : nil
        self.serviceItems = scan.draft.serviceItems
        self.confirmedAt = date
    }
}
