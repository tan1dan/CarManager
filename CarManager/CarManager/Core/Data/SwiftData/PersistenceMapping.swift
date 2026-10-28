import Foundation

// Domain ⇄ persistence mapping. Every conversion is explicit and lives here, so a schema
// change never leaks into Domain and a domain change fails to compile here first.

// MARK: - JSON helpers

/// Complex values are stored as JSON. Dates use a fixed strategy so a store written by one
/// build is readable by the next.
enum JSONBox {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? encoder.encode(value)
    }

    /// Returns `nil` rather than throwing: a row written by a newer build must not crash an
    /// older one. Callers substitute a sane default.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}

// MARK: - Codable mirrors of domain types that are not themselves Codable

private struct MessageDTO: Codable {
    var id: UUID
    var role: String
    var text: String
    var attachments: [FileRef]
    var isPartial: Bool
    var failureDescription: String?
    var createdAt: Date

    init(_ message: AIMessage) {
        id = message.id.raw
        role = message.role.rawValue
        text = message.text
        attachments = message.attachments
        isPartial = message.isPartial
        failureDescription = message.failureDescription
        createdAt = message.createdAt
    }

    var domain: AIMessage {
        AIMessage(
            id: MessageID(raw: id), role: AIMessageRole(rawValue: role) ?? .assistant,
            text: text, attachments: attachments, isPartial: isPartial,
            failureDescription: failureDescription, createdAt: createdAt
        )
    }
}

private struct PartUsageDTO: Codable {
    var id: UUID
    var name: String
    var partNumber: String?
    var quantity: Int
    var unitCost: Money?

    init(_ part: PartUsage) {
        id = part.id; name = part.name; partNumber = part.partNumber
        quantity = part.quantity; unitCost = part.unitCost
    }

    var domain: PartUsage {
        PartUsage(id: id, name: name, partNumber: partNumber, quantity: quantity, unitCost: unitCost)
    }
}

private struct ServiceItemDTO: Codable {
    var id: UUID
    var type: String
    var name: String
    var nature: String
    var partCost: Money?
    var laborCost: Money?
    var parts: [PartUsageDTO]

    init(_ item: ServiceItem) {
        id = item.id; type = item.type.rawValue; name = item.name
        nature = item.nature.rawValue; partCost = item.partCost; laborCost = item.laborCost
        parts = item.parts.map(PartUsageDTO.init)
    }

    var domain: ServiceItem {
        ServiceItem(
            id: id, type: ServiceType(rawValue: type) ?? .other, name: name,
            nature: ServiceNature(rawValue: nature) ?? .scheduledMaintenance,
            partCost: partCost, laborCost: laborCost, parts: parts.map(\.domain)
        )
    }
}

// MARK: - Vehicle

extension SDVehicle {
    func apply(_ vehicle: Vehicle) {
        id = vehicle.id.raw
        brand = vehicle.brand
        model = vehicle.model
        year = vehicle.year
        trim = vehicle.trim
        color = vehicle.color
        vin = vehicle.vin
        licensePlate = vehicle.licensePlate
        registrationCountry = vehicle.registrationCountry
        fuelTypeRaw = vehicle.fuelType.rawValue
        engineDisplacementCC = vehicle.engineDisplacementCC
        purchaseDate = vehicle.purchaseDate
        purchasePriceData = JSONBox.encode(vehicle.purchasePrice)
        currencyCode = vehicle.primaryCurrency.iso4217
        photoRefData = JSONBox.encode(vehicle.photoRef)
        isDefault = vehicle.isDefault
        ownershipScopeRaw = vehicle.ownershipScope.rawValue
        createdAt = vehicle.createdAt
        updatedAt = vehicle.updatedAt
    }

    var domain: Vehicle {
        Vehicle(
            id: VehicleID(raw: id), brand: brand, model: model, year: year, trim: trim,
            color: color, vin: vin, licensePlate: licensePlate,
            registrationCountry: registrationCountry,
            fuelType: FuelType(rawValue: fuelTypeRaw) ?? .other,
            engineDisplacementCC: engineDisplacementCC, purchaseDate: purchaseDate,
            purchasePrice: JSONBox.decode(Money.self, from: purchasePriceData),
            primaryCurrency: CurrencyCode(currencyCode),
            photoRef: JSONBox.decode(FileRef.self, from: photoRefData),
            isDefault: isDefault,
            ownershipScope: OwnershipScope(rawValue: ownershipScopeRaw) ?? .personal,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Odometer

extension SDOdometerReading {
    func apply(_ reading: OdometerReading) {
        id = reading.id.raw
        vehicleID = reading.vehicleID.raw
        kilometers = reading.value.kilometers
        recordedAt = reading.recordedAt
        sourceData = JSONBox.encode(reading.source)
        createdAt = reading.createdAt
    }

    var domain: OdometerReading {
        OdometerReading(
            id: OdometerReadingID(raw: id), vehicleID: VehicleID(raw: vehicleID),
            value: Odometer(kilometers: kilometers), recordedAt: recordedAt,
            source: JSONBox.decode(OdometerSource.self, from: sourceData) ?? .manual,
            createdAt: createdAt
        )
    }
}

// MARK: - Fuel

extension SDFuelEntry {
    func apply(_ entry: FuelEntry) {
        id = entry.id.raw
        vehicleID = entry.vehicleID.raw
        date = entry.date
        kilometers = entry.odometer.kilometers
        liters = entry.volume.liters
        pricePerUnitData = JSONBox.encode(entry.pricePerUnit)
        totalCostData = JSONBox.encode(entry.totalCost)
        fuelTypeRaw = entry.fuelType.rawValue
        station = entry.station
        isFullTank = entry.isFullTank
        missedPreviousFillUp = entry.missedPreviousFillUp
        note = entry.note
        receiptRefData = JSONBox.encode(entry.receiptRef)
        sourceData = JSONBox.encode(entry.source)
        createdAt = entry.createdAt
        updatedAt = entry.updatedAt
    }

    var domain: FuelEntry {
        let currency = CurrencyCode(
            JSONBox.decode(Money.self, from: totalCostData)?.currency.iso4217 ?? CurrencyCode.eur.iso4217
        )
        return FuelEntry(
            id: FuelEntryID(raw: id), vehicleID: VehicleID(raw: vehicleID), date: date,
            odometer: Odometer(kilometers: kilometers), volume: Volume(liters: liters),
            pricePerUnit: JSONBox.decode(Money.self, from: pricePerUnitData) ?? .zero(currency),
            totalCost: JSONBox.decode(Money.self, from: totalCostData) ?? .zero(currency),
            fuelType: FuelType(rawValue: fuelTypeRaw) ?? .other, station: station,
            isFullTank: isFullTank, missedPreviousFillUp: missedPreviousFillUp, note: note,
            receiptRef: JSONBox.decode(FileRef.self, from: receiptRefData),
            source: JSONBox.decode(RecordSource.self, from: sourceData) ?? .manual,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Service

extension SDServiceRecord {
    func apply(_ record: ServiceRecord) {
        id = record.id.raw
        vehicleID = record.vehicleID.raw
        date = record.date
        kilometers = record.odometer?.kilometers
        itemsData = JSONBox.encode(record.items.map(ServiceItemDTO.init))
        workshop = record.workshop
        totalCostData = JSONBox.encode(record.totalCost)
        note = record.note
        attachmentRefsData = JSONBox.encode(record.attachmentRefs)
        sourceData = JSONBox.encode(record.source)
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var domain: ServiceRecord {
        let total = JSONBox.decode(Money.self, from: totalCostData) ?? .zero(.eur)
        return ServiceRecord(
            id: ServiceRecordID(raw: id), vehicleID: VehicleID(raw: vehicleID), date: date,
            odometer: kilometers.map { Odometer(kilometers: $0) },
            items: (JSONBox.decode([ServiceItemDTO].self, from: itemsData) ?? []).map(\.domain),
            workshop: workshop, totalCost: total, note: note,
            attachmentRefs: JSONBox.decode([FileRef].self, from: attachmentRefsData) ?? [],
            source: JSONBox.decode(RecordSource.self, from: sourceData) ?? .manual,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Expense

extension SDExpense {
    func apply(_ expense: Expense) {
        id = expense.id.raw
        vehicleID = expense.vehicleID.raw
        title = expense.title
        categoryRaw = expense.category.rawValue
        costData = JSONBox.encode(expense.cost)
        date = expense.date
        kilometers = expense.odometer?.kilometers
        note = expense.note
        receiptRefData = JSONBox.encode(expense.receiptRef)
        sourceData = JSONBox.encode(expense.source)
        createdAt = expense.createdAt
        updatedAt = expense.updatedAt
    }

    var domain: Expense {
        Expense(
            id: ExpenseID(raw: id), vehicleID: VehicleID(raw: vehicleID), title: title,
            category: ExpenseCategory(rawValue: categoryRaw) ?? .other,
            cost: JSONBox.decode(Money.self, from: costData) ?? .zero(.eur), date: date,
            odometer: kilometers.map { Odometer(kilometers: $0) }, note: note,
            receiptRef: JSONBox.decode(FileRef.self, from: receiptRefData),
            source: JSONBox.decode(RecordSource.self, from: sourceData) ?? .manual,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Reminder

extension SDReminder {
    func apply(_ reminder: Reminder) {
        id = reminder.id.raw
        vehicleID = reminder.vehicleID.raw
        title = reminder.title
        kindRaw = reminder.kind.rawValue
        triggerData = JSONBox.encode(reminder.trigger)
        recurrenceData = JSONBox.encode(reminder.recurrence)
        note = reminder.note
        isActive = reminder.isActive
        lastCompletedAt = reminder.lastCompletedAt
        lastCompletedKilometers = reminder.lastCompletedOdometer?.kilometers
        leadTimeData = JSONBox.encode(reminder.leadTime)
        createdAt = reminder.createdAt
        updatedAt = reminder.updatedAt
    }

    var domain: Reminder {
        Reminder(
            id: ReminderID(raw: id), vehicleID: VehicleID(raw: vehicleID), title: title,
            kind: ReminderKind(rawValue: kindRaw) ?? .custom,
            // A reminder whose trigger cannot be read is shown as a far-future date rather
            // than silently dropped: the user can still see and fix it.
            trigger: JSONBox.decode(ReminderTrigger.self, from: triggerData)
                ?? .date(DateTrigger(dueDate: .distantFuture)),
            recurrence: JSONBox.decode(RecurrenceRule.self, from: recurrenceData) ?? .none,
            note: note, isActive: isActive, lastCompletedAt: lastCompletedAt,
            lastCompletedOdometer: lastCompletedKilometers.map { Odometer(kilometers: $0) },
            leadTime: JSONBox.decode(ReminderLeadTime.self, from: leadTimeData) ?? ReminderLeadTime(),
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Document

extension SDDocument {
    func apply(_ document: DocumentMetadata) {
        id = document.id.raw
        vehicleID = document.vehicleID?.raw
        name = document.name
        typeRaw = document.type.rawValue
        startDate = document.startDate
        expirationDate = document.expirationDate
        note = document.note
        fileRefData = JSONBox.encode(document.fileRef)
        fileSize = Int(document.fileSize)
        mimeType = document.mimeType
        pageCount = document.pageCount
        thumbnailRefData = JSONBox.encode(document.thumbnailRef)
        reminderID = document.reminderID?.raw
        createdAt = document.createdAt
        updatedAt = document.updatedAt
    }

    var domain: DocumentMetadata {
        DocumentMetadata(
            id: DocumentID(raw: id), vehicleID: vehicleID.map { VehicleID(raw: $0) },
            name: name, type: DocumentType(rawValue: typeRaw) ?? .other,
            startDate: startDate, expirationDate: expirationDate, note: note,
            fileRef: JSONBox.decode(FileRef.self, from: fileRefData) ?? FileRef(relativePath: ""),
            fileSize: Int64(fileSize), mimeType: mimeType, pageCount: pageCount,
            thumbnailRef: JSONBox.decode(FileRef.self, from: thumbnailRefData),
            reminderID: reminderID.map { ReminderID(raw: $0) },
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Conversation

extension SDConversation {
    func apply(_ conversation: AIConversation) {
        id = conversation.id.raw
        vehicleID = conversation.vehicleID?.raw
        title = conversation.title
        messages = conversation.messages
        contextVersion = conversation.contextVersion
        createdAt = conversation.createdAt
        updatedAt = conversation.updatedAt
    }

    /// Messages live as one JSON blob: they are always read and written with their
    /// conversation, and a row per message would multiply CloudKit traffic for no gain.
    var messages: [AIMessage] {
        get { (JSONBox.decode([MessageDTO].self, from: messagesData) ?? []).map(\.domain) }
        set { messagesData = JSONBox.encode(newValue.map(MessageDTO.init)) }
    }

    var domain: AIConversation {
        AIConversation(
            id: ConversationID(raw: id), vehicleID: vehicleID.map { VehicleID(raw: $0) },
            title: title, messages: messages, contextVersion: contextVersion,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }
}

// MARK: - Insight

extension SDInsight {
    func apply(_ insight: AIInsight) {
        id = insight.id.raw
        vehicleID = insight.vehicleID.raw
        headline = insight.headline
        body = insight.body
        severityRaw = insight.severity.rawValue
        metricsData = JSONBox.encode(insight.supportingMetrics)
        generatedAt = insight.generatedAt
        validUntil = insight.validUntil
        dismissedAt = insight.dismissedAt
    }

    var domain: AIInsight {
        AIInsight(
            id: InsightID(raw: id), vehicleID: VehicleID(raw: vehicleID), headline: headline,
            body: body, severity: InsightSeverity(rawValue: severityRaw) ?? .info,
            supportingMetrics: JSONBox.decode([MetricReference].self, from: metricsData) ?? [],
            generatedAt: generatedAt, validUntil: validUntil, dismissedAt: dismissedAt
        )
    }
}

// MARK: - Notification

extension SDNotification {
    func apply(_ notification: AppNotification) {
        id = notification.id.raw
        vehicleID = notification.vehicleID?.raw
        kindRaw = notification.kind.rawValue
        titleKey = notification.titleKey
        bodyKey = notification.bodyKey
        argumentsData = JSONBox.encode(notification.arguments)
        createdAt = notification.createdAt
        readAt = notification.readAt
    }

    var domain: AppNotification {
        AppNotification(
            id: NotificationID(raw: id), vehicleID: vehicleID.map { VehicleID(raw: $0) },
            kind: NotificationKind(rawValue: kindRaw) ?? .aiInsight,
            titleKey: titleKey, bodyKey: bodyKey,
            arguments: JSONBox.decode([String].self, from: argumentsData) ?? [],
            createdAt: createdAt, readAt: readAt
        )
    }
}

// MARK: - Vision scans

private struct DashboardFindingDTO: Codable {
    var warningName: String
    var likelyCauses: [String]
    var severity: String
    var recommendedAction: String
    var drivingSafety: String
    var confidence: Double

    init(_ f: DashboardFinding) {
        warningName = f.warningName; likelyCauses = f.likelyCauses; severity = f.severity.rawValue
        recommendedAction = f.recommendedAction; drivingSafety = f.drivingSafety.rawValue; confidence = f.confidence
    }

    /// Unknown stored values (written by a newer build) read back as the cautious default.
    var domain: DashboardFinding {
        DashboardFinding(
            warningName: warningName, likelyCauses: likelyCauses,
            severity: FindingSeverity(rawValue: severity) ?? .soon,
            recommendedAction: recommendedAction,
            drivingSafety: DrivingSafetyAssessment(rawValue: drivingSafety) ?? .unknown,
            confidence: confidence
        )
    }
}

private struct DamageFindingDTO: Codable {
    struct Cost: Codable { var low: Decimal; var high: Decimal; var currency: String; var basis: String; var confidence: Double }
    var damageType: String
    var severity: String
    var suggestedRepair: String
    var cosmeticRepairPossible: Bool?
    var cost: Cost?

    init(_ f: DamageFinding) {
        damageType = f.damageType; severity = f.severity.rawValue; suggestedRepair = f.suggestedRepair
        cosmeticRepairPossible = f.cosmeticRepairPossible
        cost = f.estimatedCost.map {
            Cost(low: $0.low.amount, high: $0.high.amount, currency: $0.low.currency.iso4217,
                 basis: $0.basis.rawValue, confidence: $0.confidence)
        }
    }

    var domain: DamageFinding {
        DamageFinding(
            damageType: damageType, severity: DamageSeverity(rawValue: severity) ?? .unknown,
            suggestedRepair: suggestedRepair, cosmeticRepairPossible: cosmeticRepairPossible,
            estimatedCost: cost.map {
                CostEstimateRange(low: Money($0.low, CurrencyCode($0.currency)), high: Money($0.high, CurrencyCode($0.currency)),
                                  basis: EstimateBasis(rawValue: $0.basis) ?? .aiEstimate, confidence: $0.confidence)
            }
        )
    }
}

extension SDDashboardScan {
    func apply(_ scan: DashboardScan) {
        id = scan.id.raw
        vehicleID = scan.vehicleID?.raw
        imageRefData = JSONBox.encode(scan.imageRef)
        findingsData = JSONBox.encode(scan.findings.map(DashboardFindingDTO.init))
        summary = scan.summary
        disclaimerKindRaw = scan.disclaimer.kind.rawValue
        disclaimerVersion = scan.disclaimer.version
        createdAt = scan.createdAt
    }

    var imageRef: FileRef? { JSONBox.decode(FileRef.self, from: imageRefData) }

    var domain: DashboardScan {
        DashboardScan(
            id: DashboardScanID(raw: id), vehicleID: vehicleID.map { VehicleID(raw: $0) },
            imageRef: imageRef ?? FileRef(relativePath: ""),
            findings: (JSONBox.decode([DashboardFindingDTO].self, from: findingsData) ?? []).map(\.domain),
            disclaimer: AIDisclaimer(kind: .notProfessionalDiagnostics, textKey: AIDisclaimer.dashboard.textKey, version: disclaimerVersion),
            createdAt: createdAt, summary: summary
        )
    }
}

extension SDDamageAnalysis {
    func apply(_ analysis: DamageAnalysis) {
        id = analysis.id.raw
        vehicleID = analysis.vehicleID.raw
        imageRefsData = JSONBox.encode(analysis.imageRefs)
        findingsData = JSONBox.encode(analysis.findings.map(DamageFindingDTO.init))
        summary = analysis.summary
        disclaimerVersion = analysis.disclaimer.version
        createdAt = analysis.createdAt
    }

    var imageRefs: [FileRef] { JSONBox.decode([FileRef].self, from: imageRefsData) ?? [] }

    var domain: DamageAnalysis {
        DamageAnalysis(
            id: DamageAnalysisID(raw: id), vehicleID: VehicleID(raw: vehicleID), imageRefs: imageRefs,
            findings: (JSONBox.decode([DamageFindingDTO].self, from: findingsData) ?? []).map(\.domain),
            disclaimer: AIDisclaimer(kind: .costEstimateOnly, textKey: AIDisclaimer.damage.textKey, version: disclaimerVersion),
            createdAt: createdAt, summary: summary
        )
    }
}
