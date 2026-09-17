import Foundation

public struct FuelEntry: Identifiable, Hashable, Sendable {
    public let id: FuelEntryID
    public let vehicleID: VehicleID
    public var date: Date
    public var odometer: Odometer
    public var volume: Volume
    public var pricePerUnit: Money
    public var totalCost: Money
    public var fuelType: FuelType
    public var station: String?
    /// The field the whole consumption algorithm hinges on.
    public var isFullTank: Bool
    public var missedPreviousFillUp: Bool
    public var note: String?
    public var receiptRef: FileRef?
    public let source: RecordSource
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: FuelEntryID = FuelEntryID(), vehicleID: VehicleID, date: Date, odometer: Odometer,
        volume: Volume, pricePerUnit: Money, totalCost: Money, fuelType: FuelType,
        station: String? = nil, isFullTank: Bool = true, missedPreviousFillUp: Bool = false,
        note: String? = nil, receiptRef: FileRef? = nil, source: RecordSource = .manual,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.date = date
        self.odometer = odometer
        self.volume = volume
        self.pricePerUnit = pricePerUnit
        self.totalCost = totalCost
        self.fuelType = fuelType
        self.station = station
        self.isFullTank = isFullTank
        self.missedPreviousFillUp = missedPreviousFillUp
        self.note = note
        self.receiptRef = receiptRef
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct FuelEntryDraft: Hashable, Sendable {
    public var vehicleID: VehicleID
    public var date: Date
    public var odometer: Odometer
    public var volume: Volume
    public var totalCost: Money
    public var pricePerUnit: Money?
    public var fuelType: FuelType
    public var station: String?
    public var isFullTank: Bool
    public var note: String?
    public var source: RecordSource

    public init(
        vehicleID: VehicleID, date: Date, odometer: Odometer, volume: Volume, totalCost: Money,
        pricePerUnit: Money? = nil, fuelType: FuelType, station: String? = nil,
        isFullTank: Bool = true, note: String? = nil, source: RecordSource = .manual
    ) {
        self.vehicleID = vehicleID
        self.date = date
        self.odometer = odometer
        self.volume = volume
        self.totalCost = totalCost
        self.pricePerUnit = pricePerUnit
        self.fuelType = fuelType
        self.station = station
        self.isFullTank = isFullTank
        self.note = note
        self.source = source
    }
}
