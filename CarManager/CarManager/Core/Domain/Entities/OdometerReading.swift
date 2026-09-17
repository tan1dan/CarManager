import Foundation

/// Append-only. Vehicle mileage is DERIVED from these rows, never stored as a mutable column.
public enum OdometerSource: Hashable, Codable, Sendable {
    case manual
    case fuelEntry(FuelEntryID)
    case serviceRecord(ServiceRecordID)
    case expense(ExpenseID)
    case obd
}

public struct OdometerReading: Identifiable, Hashable, Sendable {
    public let id: OdometerReadingID
    public let vehicleID: VehicleID
    public let value: Odometer
    public let recordedAt: Date
    public let source: OdometerSource
    public let createdAt: Date

    public init(
        id: OdometerReadingID = OdometerReadingID(), vehicleID: VehicleID, value: Odometer,
        recordedAt: Date, source: OdometerSource, createdAt: Date
    ) {
        self.id = id
        self.vehicleID = vehicleID
        self.value = value
        self.recordedAt = recordedAt
        self.source = source
        self.createdAt = createdAt
    }
}
