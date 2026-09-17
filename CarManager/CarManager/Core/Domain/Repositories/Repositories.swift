import Foundation

// Repositories return DOMAIN VALUE TYPES. SwiftData @Model classes never cross this boundary —
// PersistentModel is not Sendable, so leaking it would mean either a compile error or an
// @unchecked Sendable data race.

public protocol VehicleRepository: Sendable {
    func all() async throws -> [Vehicle]
    func summaries() async throws -> [VehicleSummary]
    func vehicle(id: VehicleID) async throws -> Vehicle?
    func defaultVehicle() async throws -> Vehicle?
    func count() async throws -> Int
    func insert(_ vehicle: Vehicle) async throws
    func update(_ vehicle: Vehicle) async throws
    func delete(id: VehicleID) async throws -> [FileRef]
    /// Transactional: clears isDefault on every other row.
    func setDefault(id: VehicleID) async throws
}

public protocol OdometerRepository: Sendable {
    func current(vehicleID: VehicleID) async throws -> OdometerReading?
    func readings(vehicleID: VehicleID) async throws -> [OdometerReading]
    func append(_ reading: OdometerReading) async throws
    func deleteLinked(source: OdometerSource) async throws
}

public protocol FuelRepository: Sendable {
    func entries(vehicleID: VehicleID) async throws -> [FuelEntry]
    /// Ascending by (odometer, date) — the exact ordering the segmentation algorithm needs.
    func entriesForConsumption(vehicleID: VehicleID) async throws -> [FuelEntry]
    func entry(id: FuelEntryID) async throws -> FuelEntry?
    func latest(vehicleID: VehicleID) async throws -> FuelEntry?
    func count(vehicleID: VehicleID) async throws -> Int
    func insert(_ entry: FuelEntry) async throws
    func update(_ entry: FuelEntry) async throws
    func delete(id: FuelEntryID) async throws -> [FileRef]
}

public protocol ServiceRepository: Sendable {
    func query(_ query: ServiceQuery) async throws -> [ServiceRecord]
    func record(id: ServiceRecordID) async throws -> ServiceRecord?
    func count(vehicleID: VehicleID) async throws -> Int
    func insert(_ record: ServiceRecord) async throws
    func update(_ record: ServiceRecord) async throws
    func delete(id: ServiceRecordID) async throws -> [FileRef]
}

public protocol ExpenseRepository: Sendable {
    func expenses(vehicleID: VehicleID) async throws -> [Expense]
    func expense(id: ExpenseID) async throws -> Expense?
    func insert(_ expense: Expense) async throws
    func update(_ expense: Expense) async throws
    func delete(id: ExpenseID) async throws -> [FileRef]
}

public protocol ReminderRepository: Sendable {
    func reminders(vehicleID: VehicleID?, activeOnly: Bool) async throws -> [Reminder]
    func reminder(id: ReminderID) async throws -> Reminder?
    func insert(_ reminder: Reminder) async throws
    func update(_ reminder: Reminder) async throws
    func delete(id: ReminderID) async throws
}

public protocol DocumentRepository: Sendable {
    func query(_ query: DocumentQuery) async throws -> [DocumentMetadata]
    func document(id: DocumentID) async throws -> DocumentMetadata?
    func count(vehicleID: VehicleID) async throws -> Int
    func insert(_ document: DocumentMetadata) async throws
    func update(_ document: DocumentMetadata) async throws
    func delete(id: DocumentID) async throws -> [FileRef]
}

public protocol AIConversationRepository: Sendable {
    func summaries(vehicleID: VehicleID?) async throws -> [ConversationSummary]
    func conversation(id: ConversationID) async throws -> AIConversation?
    func create(_ conversation: AIConversation) async throws
    func appendMessage(_ message: AIMessage, to id: ConversationID) async throws
    func replaceMessage(_ message: AIMessage, in id: ConversationID) async throws
    func delete(id: ConversationID) async throws -> [FileRef]
}

public protocol AIInsightRepository: Sendable {
    func insights(vehicleID: VehicleID) async throws -> [AIInsight]
    func replaceAll(_ insights: [AIInsight], vehicleID: VehicleID) async throws
    func dismiss(id: InsightID, at date: Date) async throws
}

public protocol NotificationInboxRepository: Sendable {
    func notifications(limit: Int) async throws -> [AppNotification]
    func unreadCount() async throws -> Int
    func insert(_ notification: AppNotification) async throws
    func markRead(ids: [NotificationID], at date: Date) async throws
    func clearAll() async throws
}

public protocol ScanRepository: Sendable {
    func receiptScan(id: ReceiptScanID) async throws -> ReceiptScan?
    func upsert(_ scan: ReceiptScan) async throws
    func insert(_ scan: DashboardScan) async throws
    func dashboardScan(id: DashboardScanID) async throws -> DashboardScan?
    func insert(_ analysis: DamageAnalysis) async throws
    func damageAnalysis(id: DamageAnalysisID) async throws -> DamageAnalysis?
}
