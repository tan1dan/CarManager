import Foundation

public struct CreateVehicleOutput: Sendable {
    public let vehicle: Vehicle
    public let becameDefault: Bool
    public let warnings: [DomainWarning]
}

public struct CreateVehicle: Sendable {
    let vehicles: any VehicleRepository
    let odometer: any OdometerRepository
    let reminders: any ReminderRepository
    let clock: any ClockProviding

    public init(
        vehicles: any VehicleRepository, odometer: any OdometerRepository,
        reminders: any ReminderRepository, clock: any ClockProviding
    ) {
        self.vehicles = vehicles; self.odometer = odometer
        self.reminders = reminders; self.clock = clock
    }

    /// `vehicleLimit` is passed in rather than resolved here, so the use case stays free of
    /// StoreKit and of any @MainActor state.
    public func callAsFunction(_ draft: VehicleDraft, vehicleLimit: Int?) async throws -> CreateVehicleOutput {
        let existingCount = try await vehicles.count()
        if let limit = vehicleLimit, existingCount >= limit {
            throw DomainError.subscription(.vehicleLimitReached)
        }

        let warnings = try VehicleValidator.validate(draft, now: clock.now, calendar: clock.calendar)

        // FIRST VEHICLE RULE: the first vehicle created becomes the default/active one.
        let isFirstVehicle = existingCount == 0
        let now = clock.now

        let vehicle = Vehicle(
            brand: draft.brand.trimmingCharacters(in: .whitespaces),
            model: draft.model.trimmingCharacters(in: .whitespaces),
            year: draft.year, trim: draft.trim, color: draft.color,
            vin: VehicleValidator.normalizedVIN(draft.vin), licensePlate: draft.licensePlate,
            fuelType: draft.fuelType, engineDisplacementCC: draft.engineDisplacementCC,
            purchaseDate: draft.purchaseDate, primaryCurrency: draft.primaryCurrency,
            isDefault: isFirstVehicle, createdAt: now, updatedAt: now
        )

        try await vehicles.insert(vehicle)
        if isFirstVehicle { try await vehicles.setDefault(id: vehicle.id) }

        try await odometer.append(OdometerReading(
            vehicleID: vehicle.id, value: draft.initialOdometer,
            recordedAt: now, source: .manual, createdAt: now
        ))

        // Standard reminders are seeded INACTIVE — we never spam notifications for a car
        // we know nothing about yet.
        for template in ReminderTemplates.defaults(for: draft.fuelType, vehicleID: vehicle.id, now: now) {
            try await reminders.insert(template)
        }

        return CreateVehicleOutput(vehicle: vehicle, becameDefault: isFirstVehicle, warnings: warnings)
    }
}

public enum ReminderTemplates {
    public static func defaults(for fuelType: FuelType, vehicleID: VehicleID, now: Date) -> [Reminder] {
        var kinds: [ReminderKind] = [.technicalInspection, .insurance]
        if fuelType != .electric { kinds.insert(.oilChange, at: 0) }
        return kinds.map { kind in
            Reminder(
                vehicleID: vehicleID, title: kind.rawValue, kind: kind,
                trigger: .date(DateTrigger(dueDate: now.addingTimeInterval(365 * 86_400))),
                recurrence: .everyMonths(12), isActive: false,
                createdAt: now, updatedAt: now
            )
        }
    }
}

public struct UpdateVehicle: Sendable {
    let vehicles: any VehicleRepository
    let clock: any ClockProviding

    public init(vehicles: any VehicleRepository, clock: any ClockProviding) {
        self.vehicles = vehicles; self.clock = clock
    }

    public func callAsFunction(_ vehicle: Vehicle) async throws -> Vehicle {
        var updated = vehicle
        updated.vin = VehicleValidator.normalizedVIN(vehicle.vin)
        updated.updatedAt = clock.now
        try await vehicles.update(updated)
        return updated
    }
}

public struct DeleteVehicle: Sendable {
    let vehicles: any VehicleRepository
    let files: any FileStorage

    public init(vehicles: any VehicleRepository, files: any FileStorage) {
        self.vehicles = vehicles; self.files = files
    }

    /// If the deleted vehicle was the default, the most recently updated remaining vehicle
    /// is promoted.
    public func callAsFunction(id: VehicleID) async throws {
        let wasDefault = try await vehicles.vehicle(id: id)?.isDefault ?? false
        let orphanedFiles = try await vehicles.delete(id: id)
        for ref in orphanedFiles { try? await files.delete(ref) }

        if wasDefault {
            let remaining = try await vehicles.all().sorted { $0.updatedAt > $1.updatedAt }
            if let promoted = remaining.first {
                try await vehicles.setDefault(id: promoted.id)
            }
        }
    }
}

public struct SetDefaultVehicle: Sendable {
    let vehicles: any VehicleRepository
    let preferences: any PreferencesProviding

    public init(vehicles: any VehicleRepository, preferences: any PreferencesProviding) {
        self.vehicles = vehicles; self.preferences = preferences
    }

    public func callAsFunction(id: VehicleID) async throws {
        guard try await vehicles.vehicle(id: id) != nil else {
            throw DomainError.validation(.vehicleNotFound)
        }
        try await vehicles.setDefault(id: id)
        preferences.defaultVehicleID = id
    }
}

public struct LoadGarage: Sendable {
    let vehicles: any VehicleRepository
    public init(vehicles: any VehicleRepository) { self.vehicles = vehicles }
    public func callAsFunction() async throws -> [VehicleSummary] {
        try await vehicles.summaries()
    }
}

public struct LoadVehicleDetail: Sendable {
    let vehicles: any VehicleRepository
    let odometer: any OdometerRepository
    let fuel: any FuelRepository
    let services: any ServiceRepository
    let documents: any DocumentRepository

    public init(
        vehicles: any VehicleRepository, odometer: any OdometerRepository,
        fuel: any FuelRepository, services: any ServiceRepository, documents: any DocumentRepository
    ) {
        self.vehicles = vehicles; self.odometer = odometer
        self.fuel = fuel; self.services = services; self.documents = documents
    }

    public struct Output: Sendable, Equatable {
        public let vehicle: Vehicle
        public let currentOdometer: Odometer?
        public let fuelEntryCount: Int
        public let serviceRecordCount: Int
        public let documentCount: Int
    }

    public func callAsFunction(id: VehicleID) async throws -> Output {
        guard let vehicle = try await vehicles.vehicle(id: id) else {
            throw DomainError.validation(.vehicleNotFound)
        }
        // Concurrent count queries: total latency is the slowest, not the sum.
        async let odo = odometer.current(vehicleID: id)
        async let fuelCount = fuel.count(vehicleID: id)
        async let serviceCount = services.count(vehicleID: id)
        async let docCount = documents.count(vehicleID: id)

        return Output(
            vehicle: vehicle,
            currentOdometer: try await odo?.value,
            fuelEntryCount: try await fuelCount,
            serviceRecordCount: try await serviceCount,
            documentCount: try await docCount
        )
    }
}

public struct UpdateOdometer: Sendable {
    let odometer: any OdometerRepository
    let clock: any ClockProviding

    public init(odometer: any OdometerRepository, clock: any ClockProviding) {
        self.odometer = odometer; self.clock = clock
    }

    /// A value lower than the current maximum is ACCEPTED (odometer replacement, clerical fix)
    /// but returns a warning so the editor can confirm with the user.
    public func callAsFunction(vehicleID: VehicleID, value: Odometer) async throws -> [DomainWarning] {
        var warnings: [DomainWarning] = []
        if let current = try await odometer.current(vehicleID: vehicleID), value < current.value {
            warnings.append(.odometerRegression(
                previous: current.value.kilometers, attempted: value.kilometers
            ))
        }
        let now = clock.now
        try await odometer.append(OdometerReading(
            vehicleID: vehicleID, value: value, recordedAt: now, source: .manual, createdAt: now
        ))
        return warnings
    }
}

public struct LoadVehicleCatalog: Sendable {
    let catalog: any VehicleCatalogProviding
    public init(catalog: any VehicleCatalogProviding) { self.catalog = catalog }
    public func callAsFunction() async throws -> VehicleCatalog {
        try await catalog.catalog()
    }
}
