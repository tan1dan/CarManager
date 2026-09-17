import Foundation

/// The single in-memory backing store for this stage.
///
/// IMPORTANT: this is a deliberate placeholder for the SwiftData persistence actor.
/// The architecture calls for SwiftData + CloudKit mirroring; because repositories are
/// protocols, swapping this actor for `PersistenceActor` + `@Model` + mappers touches
/// `Core/Data` only. Nothing in Domain, Application or Presentation changes.
actor InMemoryStore {
    var vehicles: [VehicleID: Vehicle] = [:]
    var odometerReadings: [OdometerReadingID: OdometerReading] = [:]
    var fuelEntries: [FuelEntryID: FuelEntry] = [:]
    var serviceRecords: [ServiceRecordID: ServiceRecord] = [:]
    var expenses: [ExpenseID: Expense] = [:]
    var reminders: [ReminderID: Reminder] = [:]
    var documents: [DocumentID: DocumentMetadata] = [:]
    var conversations: [ConversationID: AIConversation] = [:]
    var insights: [InsightID: AIInsight] = [:]
    var notifications: [NotificationID: AppNotification] = [:]
    var receiptScans: [ReceiptScanID: ReceiptScan] = [:]
    var dashboardScans: [DashboardScanID: DashboardScan] = [:]
    var damageAnalyses: [DamageAnalysisID: DamageAnalysis] = [:]

    @discardableResult
    func mutate<T: Sendable>(_ body: @Sendable (isolated InMemoryStore) throws -> T) rethrows -> T {
        try body(self)
    }
}
