import Foundation

public enum FuelType: String, CaseIterable, Codable, Sendable, Identifiable {
    case petrol, diesel, lpg, cng, hybridPetrol, hybridDiesel, electric, pluginHybrid, other
    public var id: String { rawValue }
    public var usesLiquidVolume: Bool { self != .electric }
}

public enum OwnershipScope: String, Codable, Sendable {
    /// Reserved for a future CloudKit-shared ("family") scope. See ADR / A-07.
    case personal
}

public struct Vehicle: Identifiable, Hashable, Sendable {
    public let id: VehicleID
    public var brand: String
    public var model: String
    public var year: Int?
    public var trim: String?
    public var color: String?
    public var vin: String?
    public var licensePlate: String?
    public var registrationCountry: String?
    public var fuelType: FuelType
    public var engineDisplacementCC: Int?
    public var purchaseDate: Date?
    public var purchasePrice: Money?
    public var primaryCurrency: CurrencyCode
    public var photoRef: FileRef?
    public var isDefault: Bool
    public var ownershipScope: OwnershipScope
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: VehicleID = VehicleID(),
        brand: String,
        model: String,
        year: Int? = nil,
        trim: String? = nil,
        color: String? = nil,
        vin: String? = nil,
        licensePlate: String? = nil,
        registrationCountry: String? = nil,
        fuelType: FuelType,
        engineDisplacementCC: Int? = nil,
        purchaseDate: Date? = nil,
        purchasePrice: Money? = nil,
        primaryCurrency: CurrencyCode = .eur,
        photoRef: FileRef? = nil,
        isDefault: Bool = false,
        ownershipScope: OwnershipScope = .personal,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.brand = brand
        self.model = model
        self.year = year
        self.trim = trim
        self.color = color
        self.vin = vin
        self.licensePlate = licensePlate
        self.registrationCountry = registrationCountry
        self.fuelType = fuelType
        self.engineDisplacementCC = engineDisplacementCC
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.primaryCurrency = primaryCurrency
        self.photoRef = photoRef
        self.isDefault = isDefault
        self.ownershipScope = ownershipScope
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String { "\(brand) \(model)" }
}

/// Lightweight garage-list projection — built from count queries, never full record loads.
public struct VehicleSummary: Identifiable, Hashable, Sendable {
    public let id: VehicleID
    public let displayName: String
    public let year: Int?
    public let fuelType: FuelType
    public let vin: String?
    public let isDefault: Bool
    public let currentOdometer: Odometer?
    public let fuelEntryCount: Int
    public let serviceRecordCount: Int
    public let documentCount: Int

    public init(
        id: VehicleID, displayName: String, year: Int?, fuelType: FuelType, vin: String? = nil,
        isDefault: Bool, currentOdometer: Odometer?, fuelEntryCount: Int,
        serviceRecordCount: Int, documentCount: Int
    ) {
        self.id = id
        self.displayName = displayName
        self.year = year
        self.fuelType = fuelType
        self.vin = vin
        self.isDefault = isDefault
        self.currentOdometer = currentOdometer
        self.fuelEntryCount = fuelEntryCount
        self.serviceRecordCount = serviceRecordCount
        self.documentCount = documentCount
    }
}

/// Input for CreateVehicle / UpdateVehicle. Carries no identity of its own.
public struct VehicleDraft: Hashable, Sendable {
    public var brand: String
    public var model: String
    public var year: Int?
    public var trim: String?
    public var color: String?
    public var vin: String?
    public var licensePlate: String?
    public var fuelType: FuelType
    public var engineDisplacementCC: Int?
    public var purchaseDate: Date?
    public var primaryCurrency: CurrencyCode
    public var initialOdometer: Odometer

    public init(
        brand: String = "",
        model: String = "",
        year: Int? = nil,
        trim: String? = nil,
        color: String? = nil,
        vin: String? = nil,
        licensePlate: String? = nil,
        fuelType: FuelType = .petrol,
        engineDisplacementCC: Int? = nil,
        purchaseDate: Date? = nil,
        primaryCurrency: CurrencyCode = .eur,
        initialOdometer: Odometer = Odometer(kilometers: 0)
    ) {
        self.brand = brand
        self.model = model
        self.year = year
        self.trim = trim
        self.color = color
        self.vin = vin
        self.licensePlate = licensePlate
        self.fuelType = fuelType
        self.engineDisplacementCC = engineDisplacementCC
        self.purchaseDate = purchaseDate
        self.primaryCurrency = primaryCurrency
        self.initialOdometer = initialOdometer
    }
}
