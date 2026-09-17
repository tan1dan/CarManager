import Foundation

public enum ExpenseCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case fuel, maintenance, repairs, insurance, parking, carWash, tires, taxes, accessories, other
    public var id: String { rawValue }
}

public struct Expense: Identifiable, Hashable, Sendable {
    public let id: ExpenseID
    public let vehicleID: VehicleID
    public var title: String
    public var category: ExpenseCategory
    public var cost: Money
    public var date: Date
    public var odometer: Odometer?
    public var note: String?
    public var receiptRef: FileRef?
    public let source: RecordSource
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ExpenseID = ExpenseID(), vehicleID: VehicleID, title: String,
        category: ExpenseCategory, cost: Money, date: Date, odometer: Odometer? = nil,
        note: String? = nil, receiptRef: FileRef? = nil, source: RecordSource = .manual,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.title = title; self.category = category
        self.cost = cost; self.date = date; self.odometer = odometer; self.note = note
        self.receiptRef = receiptRef; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

/// The unified analytics projection. NOT persisted — Fuel/Service/Expense stay separate tables,
/// so the same transaction can never be stored twice.
public struct CostEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let vehicleID: VehicleID
    public let date: Date
    public let amount: Money
    public let category: ExpenseCategory
    public let odometer: Odometer?
    public let origin: CostOrigin
    public let title: String

    public init(
        id: String, vehicleID: VehicleID, date: Date, amount: Money,
        category: ExpenseCategory, odometer: Odometer?, origin: CostOrigin, title: String
    ) {
        self.id = id; self.vehicleID = vehicleID; self.date = date; self.amount = amount
        self.category = category; self.odometer = odometer; self.origin = origin; self.title = title
    }
}

public enum CostOrigin: Hashable, Sendable {
    case fuel(FuelEntryID)
    case service(ServiceRecordID)
    case expense(ExpenseID)
    case vehiclePurchase(VehicleID)
}
