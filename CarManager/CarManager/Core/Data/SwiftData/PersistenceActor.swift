import Foundation
import SwiftData

/// Owns the `ModelContext` and every read and write that touches it.
///
/// `@ModelActor` puts the context on its own executor, so repository calls never block the
/// main actor — which is exactly why use cases are not `@MainActor`. Everything crossing the
/// boundary is a domain value type; no `PersistentModel` escapes.
@ModelActor
actor PersistenceActor {
    // MARK: - Generic helpers

    private func fetchOne<T: PersistentModel>(_ predicate: Predicate<T>) throws -> T? {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchAll<T: PersistentModel>(
        _ predicate: Predicate<T>? = nil, sortBy: [SortDescriptor<T>] = []
    ) throws -> [T] {
        try modelContext.fetch(FetchDescriptor<T>(predicate: predicate, sortBy: sortBy))
    }

    private func count<T: PersistentModel>(_ predicate: Predicate<T>) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<T>(predicate: predicate))
    }

    /// Writes are saved immediately: a crash between "the user tapped Save" and a later
    /// flush would lose the record, and CloudKit only mirrors what is saved.
    private func save() throws {
        guard modelContext.hasChanges else { return }
        try modelContext.save()
    }

    /// Insert-or-update by domain id. The schema has no unique constraint — CloudKit forbids
    /// one — so uniqueness is enforced here.
    private func upsert<T: PersistentModel>(
        _ id: UUID, _ predicate: Predicate<T>, make: () -> T, apply: (T) -> Void
    ) throws {
        let existing = try fetchOne(predicate)
        let model = existing ?? make()
        apply(model)
        if existing == nil { modelContext.insert(model) }
        try save()
    }

    // MARK: - Vehicles

    func vehicles() throws -> [Vehicle] {
        try fetchAll(sortBy: [SortDescriptor<SDVehicle>(\.createdAt)]).map(\.domain)
    }

    func vehicleSummaries() throws -> [VehicleSummary] {
        try fetchAll(sortBy: [SortDescriptor<SDVehicle>(\.createdAt)]).map { vehicle in
            let vehicleID = vehicle.id
            let readings = try? fetchAll(
                #Predicate<SDOdometerReading> { $0.vehicleID == vehicleID },
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
            )
            return VehicleSummary(
                id: VehicleID(raw: vehicleID),
                displayName: "\(vehicle.brand) \(vehicle.model)",
                year: vehicle.year,
                fuelType: FuelType(rawValue: vehicle.fuelTypeRaw) ?? .other,
                vin: vehicle.vin,
                isDefault: vehicle.isDefault,
                currentOdometer: readings?.first.map { Odometer(kilometers: $0.kilometers) },
                fuelEntryCount: (try? count(#Predicate<SDFuelEntry> { $0.vehicleID == vehicleID })) ?? 0,
                serviceRecordCount: (try? count(#Predicate<SDServiceRecord> { $0.vehicleID == vehicleID })) ?? 0,
                documentCount: (try? count(#Predicate<SDDocument> { $0.vehicleID == vehicleID })) ?? 0
            )
        }
    }

    func vehicle(id: VehicleID) throws -> Vehicle? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDVehicle> { $0.id == raw })?.domain
    }

    func defaultVehicle() throws -> Vehicle? {
        try fetchOne(#Predicate<SDVehicle> { $0.isDefault })?.domain
    }

    func vehicleCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<SDVehicle>())
    }

    func saveVehicle(_ vehicle: Vehicle) throws {
        let raw = vehicle.id.raw
        try upsert(raw, #Predicate<SDVehicle> { $0.id == raw }, make: { SDVehicle(id: raw) }) {
            $0.apply(vehicle)
        }
    }

    /// Cascades by hand: the schema has no SwiftData relationships, and a row left behind
    /// would still sync to the other devices.
    func deleteVehicle(id: VehicleID) throws -> [FileRef] {
        let raw = id.raw
        var orphaned: [FileRef] = []
        if let vehicle = try fetchOne(#Predicate<SDVehicle> { $0.id == raw }) {
            if let photo = vehicle.domain.photoRef { orphaned.append(photo) }
            modelContext.delete(vehicle)
        }
        try modelContext.delete(model: SDOdometerReading.self, where: #Predicate { $0.vehicleID == raw })
        try modelContext.delete(model: SDFuelEntry.self, where: #Predicate { $0.vehicleID == raw })
        try modelContext.delete(model: SDServiceRecord.self, where: #Predicate { $0.vehicleID == raw })
        try modelContext.delete(model: SDExpense.self, where: #Predicate { $0.vehicleID == raw })
        try modelContext.delete(model: SDReminder.self, where: #Predicate { $0.vehicleID == raw })
        try modelContext.delete(model: SDDocument.self, where: #Predicate { $0.vehicleID == raw })
        try modelContext.delete(model: SDInsight.self, where: #Predicate { $0.vehicleID == raw })
        // Damage analyses are about this car's body; their photos go with them. Dashboard
        // scans are kept (like chats) and only lose the link.
        for analysis in try fetchAll(#Predicate<SDDamageAnalysis> { $0.vehicleID == raw }) {
            orphaned += analysis.imageRefs
            modelContext.delete(analysis)
        }
        for scan in try fetchAll(#Predicate<SDDashboardScan> { $0.vehicleID == raw }) {
            scan.vehicleID = nil
        }
        // Nullify, not cascade: a chat is a user asset and outlives the car it discussed.
        for conversation in try fetchAll(#Predicate<SDConversation> { $0.vehicleID == raw }) {
            conversation.vehicleID = nil
        }
        try save()
        return orphaned
    }

    func setDefaultVehicle(id: VehicleID) throws {
        let raw = id.raw
        for vehicle in try fetchAll() as [SDVehicle] {
            vehicle.isDefault = (vehicle.id == raw)
        }
        try save()
    }

    // MARK: - Odometer

    func currentOdometer(vehicleID: VehicleID) throws -> OdometerReading? {
        let raw = vehicleID.raw
        let readings = try fetchAll(
            #Predicate<SDOdometerReading> { $0.vehicleID == raw },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse), SortDescriptor(\.kilometers, order: .reverse)]
        )
        return readings.first?.domain
    }

    func odometerReadings(vehicleID: VehicleID) throws -> [OdometerReading] {
        let raw = vehicleID.raw
        return try fetchAll(
            #Predicate<SDOdometerReading> { $0.vehicleID == raw },
            sortBy: [SortDescriptor(\.recordedAt)]
        ).map(\.domain)
    }

    func appendOdometer(_ reading: OdometerReading) throws {
        let raw = reading.id.raw
        try upsert(raw, #Predicate<SDOdometerReading> { $0.id == raw }, make: { SDOdometerReading(id: raw) }) {
            $0.apply(reading)
        }
    }

    /// The source is JSON, so it cannot be used in a predicate — the match happens in memory.
    func deleteOdometerLinked(to source: OdometerSource) throws {
        for reading in try fetchAll() as [SDOdometerReading] where reading.domain.source == source {
            modelContext.delete(reading)
        }
        try save()
    }

    // MARK: - Fuel

    func fuelEntries(vehicleID: VehicleID) throws -> [FuelEntry] {
        let raw = vehicleID.raw
        return try fetchAll(
            #Predicate<SDFuelEntry> { $0.vehicleID == raw },
            sortBy: [SortDescriptor(\.date, order: .reverse), SortDescriptor(\.kilometers, order: .reverse)]
        ).map(\.domain)
    }

    /// Ascending by (odometer, date) — the exact ordering the consumption segmentation needs.
    func fuelEntriesForConsumption(vehicleID: VehicleID) throws -> [FuelEntry] {
        let raw = vehicleID.raw
        return try fetchAll(
            #Predicate<SDFuelEntry> { $0.vehicleID == raw },
            sortBy: [SortDescriptor(\.kilometers), SortDescriptor(\.date)]
        ).map(\.domain)
    }

    func fuelEntry(id: FuelEntryID) throws -> FuelEntry? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDFuelEntry> { $0.id == raw })?.domain
    }

    func fuelCount(vehicleID: VehicleID) throws -> Int {
        let raw = vehicleID.raw
        return try count(#Predicate<SDFuelEntry> { $0.vehicleID == raw })
    }

    func saveFuelEntry(_ entry: FuelEntry) throws {
        let raw = entry.id.raw
        try upsert(raw, #Predicate<SDFuelEntry> { $0.id == raw }, make: { SDFuelEntry(id: raw) }) {
            $0.apply(entry)
        }
    }

    func deleteFuelEntry(id: FuelEntryID) throws -> [FileRef] {
        let raw = id.raw
        guard let entry = try fetchOne(#Predicate<SDFuelEntry> { $0.id == raw }) else { return [] }
        let refs = entry.domain.receiptRef.map { [$0] } ?? []
        modelContext.delete(entry)
        try save()
        return refs
    }

    // MARK: - Service

    func serviceRecords(_ query: ServiceQuery) throws -> [ServiceRecord] {
        let raw = query.vehicleID.raw
        let records = try fetchAll(
            #Predicate<SDServiceRecord> { $0.vehicleID == raw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ).map(\.domain)
        // Items are a JSON blob, so type/nature/text filtering happens here rather than in
        // the predicate. The vehicle + date narrowing already did the heavy lifting.
        return records.filter { record in
            if let range = query.dateRange, !range.contains(record.date) { return false }
            if let types = query.types, types.isDisjoint(with: Set(record.items.map(\.type))) { return false }
            if let nature = query.nature, !record.items.contains(where: { $0.nature == nature }) { return false }
            if let text = query.searchText, !text.isEmpty {
                let haystack = ([record.workshop, record.note].compactMap { $0 } + record.items.map(\.name))
                    .joined(separator: " ").lowercased()
                if !haystack.contains(text.lowercased()) { return false }
            }
            return true
        }
    }

    func serviceRecord(id: ServiceRecordID) throws -> ServiceRecord? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDServiceRecord> { $0.id == raw })?.domain
    }

    func serviceCount(vehicleID: VehicleID) throws -> Int {
        let raw = vehicleID.raw
        return try count(#Predicate<SDServiceRecord> { $0.vehicleID == raw })
    }

    func saveServiceRecord(_ record: ServiceRecord) throws {
        let raw = record.id.raw
        try upsert(raw, #Predicate<SDServiceRecord> { $0.id == raw }, make: { SDServiceRecord(id: raw) }) {
            $0.apply(record)
        }
    }

    func deleteServiceRecord(id: ServiceRecordID) throws -> [FileRef] {
        let raw = id.raw
        guard let record = try fetchOne(#Predicate<SDServiceRecord> { $0.id == raw }) else { return [] }
        let refs = record.domain.attachmentRefs
        modelContext.delete(record)
        try save()
        return refs
    }

    // MARK: - Expenses

    func expenses(vehicleID: VehicleID) throws -> [Expense] {
        let raw = vehicleID.raw
        return try fetchAll(
            #Predicate<SDExpense> { $0.vehicleID == raw },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ).map(\.domain)
    }

    func expense(id: ExpenseID) throws -> Expense? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDExpense> { $0.id == raw })?.domain
    }

    func saveExpense(_ expense: Expense) throws {
        let raw = expense.id.raw
        try upsert(raw, #Predicate<SDExpense> { $0.id == raw }, make: { SDExpense(id: raw) }) {
            $0.apply(expense)
        }
    }

    func deleteExpense(id: ExpenseID) throws -> [FileRef] {
        let raw = id.raw
        guard let expense = try fetchOne(#Predicate<SDExpense> { $0.id == raw }) else { return [] }
        let refs = expense.domain.receiptRef.map { [$0] } ?? []
        modelContext.delete(expense)
        try save()
        return refs
    }

    // MARK: - Reminders

    func reminders(vehicleID: VehicleID?, activeOnly: Bool) throws -> [Reminder] {
        let sort = [SortDescriptor<SDReminder>(\.createdAt)]
        let all: [SDReminder]
        if let raw = vehicleID?.raw {
            all = try fetchAll(#Predicate<SDReminder> { $0.vehicleID == raw }, sortBy: sort)
        } else {
            all = try fetchAll(sortBy: sort)
        }
        return all.filter { !activeOnly || $0.isActive }.map(\.domain)
    }

    func reminder(id: ReminderID) throws -> Reminder? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDReminder> { $0.id == raw })?.domain
    }

    func saveReminder(_ reminder: Reminder) throws {
        let raw = reminder.id.raw
        try upsert(raw, #Predicate<SDReminder> { $0.id == raw }, make: { SDReminder(id: raw) }) {
            $0.apply(reminder)
        }
    }

    func deleteReminder(id: ReminderID) throws {
        let raw = id.raw
        try modelContext.delete(model: SDReminder.self, where: #Predicate { $0.id == raw })
        try save()
    }

    // MARK: - Documents

    func documents(_ query: DocumentQuery) throws -> [DocumentMetadata] {
        let sort = [SortDescriptor<SDDocument>(\.createdAt, order: .reverse)]
        let all: [SDDocument]
        if let raw = query.vehicleID?.raw {
            all = try fetchAll(#Predicate<SDDocument> { $0.vehicleID == raw }, sortBy: sort)
        } else {
            all = try fetchAll(sortBy: sort)
        }
        return all.map(\.domain).filter { document in
            if let types = query.types, !types.contains(document.type) { return false }
            if let text = query.searchText, !text.isEmpty {
                let haystack = "\(document.name) \(document.note ?? "")".lowercased()
                if !haystack.contains(text.lowercased()) { return false }
            }
            return true
        }
    }

    func document(id: DocumentID) throws -> DocumentMetadata? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDDocument> { $0.id == raw })?.domain
    }

    func documentCount(vehicleID: VehicleID) throws -> Int {
        let raw = vehicleID.raw
        return try count(#Predicate<SDDocument> { $0.vehicleID == raw })
    }

    func saveDocument(_ document: DocumentMetadata) throws {
        let raw = document.id.raw
        try upsert(raw, #Predicate<SDDocument> { $0.id == raw }, make: { SDDocument(id: raw) }) {
            $0.apply(document)
        }
    }

    func deleteDocument(id: DocumentID) throws -> [FileRef] {
        let raw = id.raw
        guard let model = try fetchOne(#Predicate<SDDocument> { $0.id == raw }) else { return [] }
        let document = model.domain
        var refs = [document.fileRef]
        if let thumbnail = document.thumbnailRef { refs.append(thumbnail) }
        modelContext.delete(model)
        try save()
        return refs
    }

    // MARK: - Conversations

    func conversationSummaries(vehicleID: VehicleID?) throws -> [ConversationSummary] {
        let sort = [SortDescriptor<SDConversation>(\.updatedAt, order: .reverse)]
        let all: [SDConversation]
        if let raw = vehicleID?.raw {
            all = try fetchAll(#Predicate<SDConversation> { $0.vehicleID == raw }, sortBy: sort)
        } else {
            all = try fetchAll(sortBy: sort)
        }
        return all.map {
            ConversationSummary(
                id: ConversationID(raw: $0.id), title: $0.title,
                updatedAt: $0.updatedAt, messageCount: $0.messages.count
            )
        }
    }

    func conversation(id: ConversationID) throws -> AIConversation? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDConversation> { $0.id == raw })?.domain
    }

    func createConversation(_ conversation: AIConversation) throws {
        let raw = conversation.id.raw
        try upsert(raw, #Predicate<SDConversation> { $0.id == raw }, make: { SDConversation(id: raw) }) {
            $0.apply(conversation)
        }
    }

    func appendMessage(_ message: AIMessage, to id: ConversationID) throws {
        let raw = id.raw
        guard let conversation = try fetchOne(#Predicate<SDConversation> { $0.id == raw }) else { return }
        conversation.messages.append(message)
        conversation.updatedAt = message.createdAt
        try save()
    }

    func replaceMessage(_ message: AIMessage, in id: ConversationID) throws {
        let raw = id.raw
        guard let conversation = try fetchOne(#Predicate<SDConversation> { $0.id == raw }) else { return }
        var messages = conversation.messages
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index] = message
        conversation.messages = messages
        try save()
    }

    func deleteConversation(id: ConversationID) throws -> [FileRef] {
        let raw = id.raw
        guard let conversation = try fetchOne(#Predicate<SDConversation> { $0.id == raw }) else { return [] }
        let refs = conversation.messages.flatMap(\.attachments)
        modelContext.delete(conversation)
        try save()
        return refs
    }

    // MARK: - Vision scans

    func saveDashboardScan(_ scan: DashboardScan) throws {
        let raw = scan.id.raw
        try upsert(raw, #Predicate<SDDashboardScan> { $0.id == raw }, make: { SDDashboardScan(id: raw) }) { $0.apply(scan) }
    }

    func dashboardScan(id: DashboardScanID) throws -> DashboardScan? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDDashboardScan> { $0.id == raw })?.domain
    }

    func dashboardScans(vehicleID: VehicleID?) throws -> [DashboardScan] {
        let sort = [SortDescriptor<SDDashboardScan>(\.createdAt, order: .reverse)]
        if let raw = vehicleID?.raw {
            return try fetchAll(#Predicate<SDDashboardScan> { $0.vehicleID == raw }, sortBy: sort).map(\.domain)
        }
        return try fetchAll(sortBy: sort).map(\.domain)
    }

    func deleteDashboardScan(id: DashboardScanID) throws -> [FileRef] {
        let raw = id.raw
        guard let scan = try fetchOne(#Predicate<SDDashboardScan> { $0.id == raw }) else { return [] }
        let refs = scan.imageRef.map { [$0] } ?? []
        modelContext.delete(scan)
        try save()
        return refs
    }

    func saveDamageAnalysis(_ analysis: DamageAnalysis) throws {
        let raw = analysis.id.raw
        try upsert(raw, #Predicate<SDDamageAnalysis> { $0.id == raw }, make: { SDDamageAnalysis(id: raw) }) { $0.apply(analysis) }
    }

    func damageAnalysis(id: DamageAnalysisID) throws -> DamageAnalysis? {
        let raw = id.raw
        return try fetchOne(#Predicate<SDDamageAnalysis> { $0.id == raw })?.domain
    }

    func damageAnalyses(vehicleID: VehicleID?) throws -> [DamageAnalysis] {
        let sort = [SortDescriptor<SDDamageAnalysis>(\.createdAt, order: .reverse)]
        if let raw = vehicleID?.raw {
            return try fetchAll(#Predicate<SDDamageAnalysis> { $0.vehicleID == raw }, sortBy: sort).map(\.domain)
        }
        return try fetchAll(sortBy: sort).map(\.domain)
    }

    func deleteDamageAnalysis(id: DamageAnalysisID) throws -> [FileRef] {
        let raw = id.raw
        guard let analysis = try fetchOne(#Predicate<SDDamageAnalysis> { $0.id == raw }) else { return [] }
        let refs = analysis.imageRefs
        modelContext.delete(analysis)
        try save()
        return refs
    }

    // MARK: - Files

    func storeFile(_ ref: FileRef, kind: FileKind, data: Data, at date: Date) throws {
        let raw = ref.id
        try upsert(raw, #Predicate<SDStoredFile> { $0.id == raw }, make: { SDStoredFile(id: raw) }) {
            $0.relativePath = ref.relativePath
            $0.kindRaw = kind.rawValue
            $0.data = data
            $0.createdAt = date
        }
    }

    /// `nil` when there is no record, or CloudKit has not brought the bytes down yet.
    func fileData(id: UUID) throws -> Data? {
        try fetchOne(#Predicate<SDStoredFile> { $0.id == id })?.data
    }

    func storedFileIDs() throws -> Set<UUID> {
        var descriptor = FetchDescriptor<SDStoredFile>()
        descriptor.propertiesToFetch = [\.id]
        return Set(try modelContext.fetch(descriptor).map(\.id))
    }

    func deleteFile(id: UUID) throws {
        try modelContext.delete(model: SDStoredFile.self, where: #Predicate { $0.id == id })
        try save()
    }

    // MARK: - Insights

    func insights(vehicleID: VehicleID) throws -> [AIInsight] {
        let raw = vehicleID.raw
        return try fetchAll(
            #Predicate<SDInsight> { $0.vehicleID == raw && $0.dismissedAt == nil },
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        ).map(\.domain)
    }

    func replaceInsights(_ insights: [AIInsight], vehicleID: VehicleID) throws {
        let raw = vehicleID.raw
        try modelContext.delete(model: SDInsight.self, where: #Predicate { $0.vehicleID == raw })
        for insight in insights {
            let model = SDInsight(id: insight.id.raw)
            model.apply(insight)
            modelContext.insert(model)
        }
        try save()
    }

    func dismissInsight(id: InsightID, at date: Date) throws {
        let raw = id.raw
        try fetchOne(#Predicate<SDInsight> { $0.id == raw })?.dismissedAt = date
        try save()
    }

    // MARK: - Notification inbox

    func notifications(limit: Int) throws -> [AppNotification] {
        var descriptor = FetchDescriptor<SDNotification>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map(\.domain)
    }

    func unreadNotificationCount() throws -> Int {
        try count(#Predicate<SDNotification> { $0.readAt == nil })
    }

    func insertNotification(_ notification: AppNotification) throws {
        let raw = notification.id.raw
        try upsert(raw, #Predicate<SDNotification> { $0.id == raw }, make: { SDNotification(id: raw) }) {
            $0.apply(notification)
        }
    }

    func markNotificationsRead(ids: [NotificationID], at date: Date) throws {
        let raws = Set(ids.map(\.raw))
        for notification in try fetchAll() as [SDNotification] where raws.contains(notification.id) {
            notification.readAt = date
        }
        try save()
    }

    func clearNotifications() throws {
        try modelContext.delete(model: SDNotification.self)
        try save()
    }
}
