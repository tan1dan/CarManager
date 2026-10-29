import Foundation
import SwiftData

// The persistence schema. These classes NEVER leave `Core/Data` — repositories return domain
// value types, because `PersistentModel` is not `Sendable`.
//
// Three rules come from CloudKit mirroring and shape everything here:
//
//  1. No `@Attribute(.unique)`. Uniqueness of a domain id is enforced by fetching first.
//  2. Every property has a default value, so CloudKit can add columns to existing records.
//  3. No SwiftData relationships. Rows reference each other by `UUID` exactly as the domain
//     does, which keeps mapping trivial and avoids the inverse-relationship requirements
//     CloudKit imposes. Cascades are explicit in `VehicleRepository.delete`.
//
// Complex values (money, enums with payloads, nested arrays) are stored as JSON `Data` via
// `CodableBox`. It costs one encode per write and keeps the CloudKit schema to plain scalars.

@Model
final class SDVehicle {
    var id: UUID = UUID()
    var brand: String = ""
    var model: String = ""
    var year: Int?
    var trim: String?
    var color: String?
    var vin: String?
    var licensePlate: String?
    var registrationCountry: String?
    var fuelTypeRaw: String = FuelType.petrol.rawValue
    var engineDisplacementCC: Int?
    var purchaseDate: Date?
    var purchasePriceData: Data?
    var currencyCode: String = CurrencyCode.eur.iso4217
    var photoRefData: Data?
    var isDefault: Bool = false
    var ownershipScopeRaw: String = OwnershipScope.personal.rawValue
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDOdometerReading {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var kilometers: Double = 0
    var recordedAt: Date = Date.distantPast
    var sourceData: Data?
    var createdAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDFuelEntry {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var date: Date = Date.distantPast
    var kilometers: Double = 0
    var liters: Double = 0
    var pricePerUnitData: Data?
    var totalCostData: Data?
    var fuelTypeRaw: String = FuelType.petrol.rawValue
    var station: String?
    var isFullTank: Bool = true
    var missedPreviousFillUp: Bool = false
    var note: String?
    var receiptRefData: Data?
    var sourceData: Data?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDServiceRecord {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var date: Date = Date.distantPast
    /// `nil` when the user did not record mileage — not zero.
    var kilometers: Double?
    var itemsData: Data?
    var workshop: String?
    var totalCostData: Data?
    var note: String?
    var attachmentRefsData: Data?
    var sourceData: Data?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDExpense {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var title: String = ""
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var costData: Data?
    var date: Date = Date.distantPast
    var kilometers: Double?
    var note: String?
    var receiptRefData: Data?
    var sourceData: Data?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDReminder {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var title: String = ""
    var kindRaw: String = ReminderKind.custom.rawValue
    var triggerData: Data?
    var recurrenceData: Data?
    var note: String?
    var isActive: Bool = true
    var lastCompletedAt: Date?
    var lastCompletedKilometers: Double?
    var leadTimeData: Data?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDDocument {
    var id: UUID = UUID()
    /// Optional in the domain too: a driver's licence belongs to the person, not a car.
    var vehicleID: UUID?
    var name: String = ""
    var typeRaw: String = DocumentType.other.rawValue
    var startDate: Date?
    var expirationDate: Date?
    var note: String?
    var fileRefData: Data?
    var fileSize: Int = 0
    var mimeType: String = "application/pdf"
    var pageCount: Int?
    var thumbnailRefData: Data?
    var reminderID: UUID?
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDConversation {
    var id: UUID = UUID()
    var vehicleID: UUID?
    var title: String = ""
    var messagesData: Data?
    var contextVersion: Int = 1
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDInsight {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var headline: String = ""
    var body: String = ""
    var severityRaw: String = InsightSeverity.info.rawValue
    var metricsData: Data?
    var generatedAt: Date = Date.distantPast
    var validUntil: Date = Date.distantPast
    var dismissedAt: Date?

    init(id: UUID = UUID()) { self.id = id }
}

@Model
final class SDNotification {
    var id: UUID = UUID()
    var vehicleID: UUID?
    var kindRaw: String = NotificationKind.aiInsight.rawValue
    var titleKey: String = ""
    var bodyKey: String = ""
    var argumentsData: Data?
    var createdAt: Date = Date.distantPast
    var readAt: Date?

    init(id: UUID = UUID()) { self.id = id }
}

/// A dashboard warning-light scan. Findings are one JSON blob, like chat messages.
@Model
final class SDDashboardScan {
    var id: UUID = UUID()
    var vehicleID: UUID?
    var imageRefData: Data?
    var findingsData: Data?
    var summary: String?
    var disclaimerKindRaw: String = DisclaimerKind.notProfessionalDiagnostics.rawValue
    var disclaimerVersion: Int = 1
    var createdAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

/// A body-damage analysis. Belongs to a vehicle and goes with it when the vehicle is deleted.
@Model
final class SDDamageAnalysis {
    var id: UUID = UUID()
    var vehicleID: UUID = UUID()
    var imageRefsData: Data?
    var findingsData: Data?
    var summary: String?
    var disclaimerVersion: Int = 1
    var createdAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

/// The bytes behind a `FileRef` — scan photos, documents, vehicle photos. `.externalStorage`
/// keeps them out of the SQLite file, and CloudKit mirrors them as assets, so they come back
/// after a reinstall or on another device together with the records that point at them.
@Model
final class SDStoredFile {
    /// Same as `FileRef.id`.
    var id: UUID = UUID()
    var relativePath: String = ""
    var kindRaw: String = FileKind.scan.rawValue
    @Attribute(.externalStorage) var data: Data?
    var createdAt: Date = Date.distantPast

    init(id: UUID = UUID()) { self.id = id }
}

enum PersistenceSchema {
    static let models: [any PersistentModel.Type] = [
        SDVehicle.self, SDOdometerReading.self, SDFuelEntry.self, SDServiceRecord.self,
        SDExpense.self, SDReminder.self, SDDocument.self, SDConversation.self,
        SDInsight.self, SDNotification.self, SDDashboardScan.self, SDDamageAnalysis.self,
        SDStoredFile.self
    ]
}
