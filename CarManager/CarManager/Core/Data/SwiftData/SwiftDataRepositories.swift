import Foundation

// Thin adapters: the protocol surface the Application layer sees, forwarded to the
// persistence actor. They exist so repositories stay swappable (tests use the in-memory set)
// and so no `ModelContext` detail reaches a use case.

struct SwiftDataVehicleRepository: VehicleRepository {
    let store: PersistenceActor

    func all() async throws -> [Vehicle] { try await store.vehicles() }
    func summaries() async throws -> [VehicleSummary] { try await store.vehicleSummaries() }
    func vehicle(id: VehicleID) async throws -> Vehicle? { try await store.vehicle(id: id) }
    func defaultVehicle() async throws -> Vehicle? { try await store.defaultVehicle() }
    func count() async throws -> Int { try await store.vehicleCount() }
    func insert(_ vehicle: Vehicle) async throws { try await store.saveVehicle(vehicle) }
    func update(_ vehicle: Vehicle) async throws { try await store.saveVehicle(vehicle) }
    func delete(id: VehicleID) async throws -> [FileRef] { try await store.deleteVehicle(id: id) }
    func setDefault(id: VehicleID) async throws { try await store.setDefaultVehicle(id: id) }
}

struct SwiftDataOdometerRepository: OdometerRepository {
    let store: PersistenceActor

    func current(vehicleID: VehicleID) async throws -> OdometerReading? {
        try await store.currentOdometer(vehicleID: vehicleID)
    }
    func readings(vehicleID: VehicleID) async throws -> [OdometerReading] {
        try await store.odometerReadings(vehicleID: vehicleID)
    }
    func append(_ reading: OdometerReading) async throws { try await store.appendOdometer(reading) }
    func deleteLinked(source: OdometerSource) async throws {
        try await store.deleteOdometerLinked(to: source)
    }
}

struct SwiftDataFuelRepository: FuelRepository {
    let store: PersistenceActor

    func entries(vehicleID: VehicleID) async throws -> [FuelEntry] {
        try await store.fuelEntries(vehicleID: vehicleID)
    }
    func entriesForConsumption(vehicleID: VehicleID) async throws -> [FuelEntry] {
        try await store.fuelEntriesForConsumption(vehicleID: vehicleID)
    }
    func entry(id: FuelEntryID) async throws -> FuelEntry? { try await store.fuelEntry(id: id) }
    func latest(vehicleID: VehicleID) async throws -> FuelEntry? {
        try await store.fuelEntries(vehicleID: vehicleID).first
    }
    func count(vehicleID: VehicleID) async throws -> Int {
        try await store.fuelCount(vehicleID: vehicleID)
    }
    func insert(_ entry: FuelEntry) async throws { try await store.saveFuelEntry(entry) }
    func update(_ entry: FuelEntry) async throws { try await store.saveFuelEntry(entry) }
    func delete(id: FuelEntryID) async throws -> [FileRef] { try await store.deleteFuelEntry(id: id) }
}

struct SwiftDataServiceRepository: ServiceRepository {
    let store: PersistenceActor

    func query(_ query: ServiceQuery) async throws -> [ServiceRecord] {
        try await store.serviceRecords(query)
    }
    func record(id: ServiceRecordID) async throws -> ServiceRecord? {
        try await store.serviceRecord(id: id)
    }
    func count(vehicleID: VehicleID) async throws -> Int {
        try await store.serviceCount(vehicleID: vehicleID)
    }
    func insert(_ record: ServiceRecord) async throws { try await store.saveServiceRecord(record) }
    func update(_ record: ServiceRecord) async throws { try await store.saveServiceRecord(record) }
    func delete(id: ServiceRecordID) async throws -> [FileRef] {
        try await store.deleteServiceRecord(id: id)
    }
}

struct SwiftDataExpenseRepository: ExpenseRepository {
    let store: PersistenceActor

    func expenses(vehicleID: VehicleID) async throws -> [Expense] {
        try await store.expenses(vehicleID: vehicleID)
    }
    func expense(id: ExpenseID) async throws -> Expense? { try await store.expense(id: id) }
    func insert(_ expense: Expense) async throws { try await store.saveExpense(expense) }
    func update(_ expense: Expense) async throws { try await store.saveExpense(expense) }
    func delete(id: ExpenseID) async throws -> [FileRef] { try await store.deleteExpense(id: id) }
}

struct SwiftDataReminderRepository: ReminderRepository {
    let store: PersistenceActor

    func reminders(vehicleID: VehicleID?, activeOnly: Bool) async throws -> [Reminder] {
        try await store.reminders(vehicleID: vehicleID, activeOnly: activeOnly)
    }
    func reminder(id: ReminderID) async throws -> Reminder? { try await store.reminder(id: id) }
    func insert(_ reminder: Reminder) async throws { try await store.saveReminder(reminder) }
    func update(_ reminder: Reminder) async throws { try await store.saveReminder(reminder) }
    func delete(id: ReminderID) async throws { try await store.deleteReminder(id: id) }
}

struct SwiftDataDocumentRepository: DocumentRepository {
    let store: PersistenceActor

    func query(_ query: DocumentQuery) async throws -> [DocumentMetadata] {
        try await store.documents(query)
    }
    func document(id: DocumentID) async throws -> DocumentMetadata? {
        try await store.document(id: id)
    }
    func count(vehicleID: VehicleID) async throws -> Int {
        try await store.documentCount(vehicleID: vehicleID)
    }
    func insert(_ document: DocumentMetadata) async throws { try await store.saveDocument(document) }
    func update(_ document: DocumentMetadata) async throws { try await store.saveDocument(document) }
    func delete(id: DocumentID) async throws -> [FileRef] { try await store.deleteDocument(id: id) }
}

struct SwiftDataAIConversationRepository: AIConversationRepository {
    let store: PersistenceActor

    func summaries(vehicleID: VehicleID?) async throws -> [ConversationSummary] {
        try await store.conversationSummaries(vehicleID: vehicleID)
    }
    func conversation(id: ConversationID) async throws -> AIConversation? {
        try await store.conversation(id: id)
    }
    func create(_ conversation: AIConversation) async throws {
        try await store.createConversation(conversation)
    }
    func appendMessage(_ message: AIMessage, to id: ConversationID) async throws {
        try await store.appendMessage(message, to: id)
    }
    func replaceMessage(_ message: AIMessage, in id: ConversationID) async throws {
        try await store.replaceMessage(message, in: id)
    }
    func delete(id: ConversationID) async throws -> [FileRef] {
        try await store.deleteConversation(id: id)
    }
}

struct SwiftDataAIInsightRepository: AIInsightRepository {
    let store: PersistenceActor

    func insights(vehicleID: VehicleID) async throws -> [AIInsight] {
        try await store.insights(vehicleID: vehicleID)
    }
    func replaceAll(_ insights: [AIInsight], vehicleID: VehicleID) async throws {
        try await store.replaceInsights(insights, vehicleID: vehicleID)
    }
    func dismiss(id: InsightID, at date: Date) async throws {
        try await store.dismissInsight(id: id, at: date)
    }
}

struct SwiftDataNotificationInboxRepository: NotificationInboxRepository {
    let store: PersistenceActor

    func notifications(limit: Int) async throws -> [AppNotification] {
        try await store.notifications(limit: limit)
    }
    func unreadCount() async throws -> Int { try await store.unreadNotificationCount() }
    func insert(_ notification: AppNotification) async throws {
        try await store.insertNotification(notification)
    }
    func markRead(ids: [NotificationID], at date: Date) async throws {
        try await store.markNotificationsRead(ids: ids, at: date)
    }
    func clearAll() async throws { try await store.clearNotifications() }
}

/// Dashboard scans and damage analyses are kept (and synced); receipt scans are NOT — a
/// receipt lives only until the user confirms or discards it, so nothing extracted is ever
/// stored without that confirmation.
struct SwiftDataScanRepository: ScanRepository {
    let store: PersistenceActor
    let receipts: InMemoryScanRepository

    func receiptScan(id: ReceiptScanID) async throws -> ReceiptScan? { try await receipts.receiptScan(id: id) }
    func upsert(_ scan: ReceiptScan) async throws { try await receipts.upsert(scan) }

    func insert(_ scan: DashboardScan) async throws { try await store.saveDashboardScan(scan) }
    func dashboardScan(id: DashboardScanID) async throws -> DashboardScan? { try await store.dashboardScan(id: id) }
    func dashboardScans(vehicleID: VehicleID?) async throws -> [DashboardScan] { try await store.dashboardScans(vehicleID: vehicleID) }
    func deleteDashboardScan(id: DashboardScanID) async throws -> [FileRef] { try await store.deleteDashboardScan(id: id) }

    func insert(_ analysis: DamageAnalysis) async throws { try await store.saveDamageAnalysis(analysis) }
    func damageAnalysis(id: DamageAnalysisID) async throws -> DamageAnalysis? { try await store.damageAnalysis(id: id) }
    func damageAnalyses(vehicleID: VehicleID?) async throws -> [DamageAnalysis] { try await store.damageAnalyses(vehicleID: vehicleID) }
    func deleteDamageAnalysis(id: DamageAnalysisID) async throws -> [FileRef] { try await store.deleteDamageAnalysis(id: id) }
}
