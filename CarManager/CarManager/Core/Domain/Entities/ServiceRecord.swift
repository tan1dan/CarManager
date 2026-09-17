import Foundation

public enum ServiceType: String, CaseIterable, Codable, Sendable, Identifiable {
    case oilChange, filters, brakes, tires, battery, suspension, engine, electrical, other
    public var id: String { rawValue }
}

public enum ServiceNature: String, Codable, Sendable {
    case scheduledMaintenance, repair
}

public struct PartUsage: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var partNumber: String?
    public var quantity: Int
    public var unitCost: Money?

    public init(id: UUID = UUID(), name: String, partNumber: String? = nil, quantity: Int = 1, unitCost: Money? = nil) {
        self.id = id; self.name = name; self.partNumber = partNumber
        self.quantity = quantity; self.unitCost = unitCost
    }
}

/// A service record has MANY items — an oil change that also replaced the air filter must
/// satisfy both the oil-change reminder and the filter reminder.
public struct ServiceItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var type: ServiceType
    public var name: String
    public var nature: ServiceNature
    public var partCost: Money?
    public var laborCost: Money?
    public var parts: [PartUsage]

    public init(
        id: UUID = UUID(), type: ServiceType, name: String,
        nature: ServiceNature = .scheduledMaintenance,
        partCost: Money? = nil, laborCost: Money? = nil, parts: [PartUsage] = []
    ) {
        self.id = id; self.type = type; self.name = name; self.nature = nature
        self.partCost = partCost; self.laborCost = laborCost; self.parts = parts
    }
}

public struct ServiceRecord: Identifiable, Hashable, Sendable {
    public let id: ServiceRecordID
    public let vehicleID: VehicleID
    public var date: Date
    public var odometer: Odometer?
    public var items: [ServiceItem]
    public var workshop: String?
    public var totalCost: Money
    public var note: String?
    public var attachmentRefs: [FileRef]
    public let source: RecordSource
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ServiceRecordID = ServiceRecordID(), vehicleID: VehicleID, date: Date,
        odometer: Odometer? = nil, items: [ServiceItem], workshop: String? = nil,
        totalCost: Money, note: String? = nil, attachmentRefs: [FileRef] = [],
        source: RecordSource = .manual, createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.date = date; self.odometer = odometer
        self.items = items; self.workshop = workshop; self.totalCost = totalCost
        self.note = note; self.attachmentRefs = attachmentRefs; self.source = source
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    public var primaryType: ServiceType { items.first?.type ?? .other }
    public var isRepair: Bool { items.contains { $0.nature == .repair } }
}

/// Typed query — repositories never take predicate strings or closures.
public struct ServiceQuery: Hashable, Sendable {
    public var vehicleID: VehicleID
    public var dateRange: DateRange?
    public var types: Set<ServiceType>?
    public var nature: ServiceNature?
    public var searchText: String?

    public init(
        vehicleID: VehicleID, dateRange: DateRange? = nil,
        types: Set<ServiceType>? = nil, nature: ServiceNature? = nil, searchText: String? = nil
    ) {
        self.vehicleID = vehicleID; self.dateRange = dateRange
        self.types = types; self.nature = nature; self.searchText = searchText
    }
}
