import Foundation

struct InMemoryVehicleRepository: VehicleRepository {
    let store: InMemoryStore

    func all() async throws -> [Vehicle] {
        await store.vehicles.values.sorted { $0.createdAt < $1.createdAt }
    }

    func summaries() async throws -> [VehicleSummary] {
        await store.mutate { store in
            store.vehicles.values
                .sorted { $0.createdAt < $1.createdAt }
                .map { vehicle in
                    let odo = store.odometerReadings.values
                        .filter { $0.vehicleID == vehicle.id }
                        .max { $0.recordedAt < $1.recordedAt }
                    return VehicleSummary(
                        id: vehicle.id, displayName: vehicle.displayName, year: vehicle.year,
                        fuelType: vehicle.fuelType, vin: vehicle.vin, isDefault: vehicle.isDefault,
                        currentOdometer: odo?.value,
                        fuelEntryCount: store.fuelEntries.values.filter { $0.vehicleID == vehicle.id }.count,
                        serviceRecordCount: store.serviceRecords.values.filter { $0.vehicleID == vehicle.id }.count,
                        documentCount: store.documents.values.filter { $0.vehicleID == vehicle.id }.count
                    )
                }
        }
    }

    func vehicle(id: VehicleID) async throws -> Vehicle? { await store.vehicles[id] }
    func defaultVehicle() async throws -> Vehicle? { await store.vehicles.values.first { $0.isDefault } }
    func count() async throws -> Int { await store.vehicles.count }
    func insert(_ vehicle: Vehicle) async throws { await store.mutate { $0.vehicles[vehicle.id] = vehicle } }
    func update(_ vehicle: Vehicle) async throws { await store.mutate { $0.vehicles[vehicle.id] = vehicle } }

    func delete(id: VehicleID) async throws -> [FileRef] {
        await store.mutate { store in
            var orphaned: [FileRef] = []
            if let photo = store.vehicles[id]?.photoRef { orphaned.append(photo) }
            store.vehicles.removeValue(forKey: id)
            // Cascade — records are meaningless without their vehicle.
            store.odometerReadings = store.odometerReadings.filter { $0.value.vehicleID != id }
            store.fuelEntries = store.fuelEntries.filter { $0.value.vehicleID != id }
            store.serviceRecords = store.serviceRecords.filter { $0.value.vehicleID != id }
            store.expenses = store.expenses.filter { $0.value.vehicleID != id }
            store.reminders = store.reminders.filter { $0.value.vehicleID != id }
            store.documents = store.documents.filter { $0.value.vehicleID != id }
            store.insights = store.insights.filter { $0.value.vehicleID != id }
            // Nullify, not cascade: a chat is a user asset and outlives the car it discussed.
            for (key, var conversation) in store.conversations where conversation.vehicleID == id {
                conversation.vehicleID = nil
                store.conversations[key] = conversation
            }
            return orphaned
        }
    }

    func setDefault(id: VehicleID) async throws {
        await store.mutate { store in
            for (key, var vehicle) in store.vehicles {
                vehicle.isDefault = (key == id)
                store.vehicles[key] = vehicle
            }
        }
    }
}

struct InMemoryOdometerRepository: OdometerRepository {
    let store: InMemoryStore

    func current(vehicleID: VehicleID) async throws -> OdometerReading? {
        await store.odometerReadings.values
            .filter { $0.vehicleID == vehicleID }
            .max { ($0.recordedAt, $0.value) < ($1.recordedAt, $1.value) }
    }

    func readings(vehicleID: VehicleID) async throws -> [OdometerReading] {
        await store.odometerReadings.values
            .filter { $0.vehicleID == vehicleID }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    func append(_ reading: OdometerReading) async throws {
        await store.mutate { $0.odometerReadings[reading.id] = reading }
    }

    func deleteLinked(source: OdometerSource) async throws {
        await store.mutate { $0.odometerReadings = $0.odometerReadings.filter { $0.value.source != source } }
    }
}

struct InMemoryFuelRepository: FuelRepository {
    let store: InMemoryStore

    func entries(vehicleID: VehicleID) async throws -> [FuelEntry] {
        await store.fuelEntries.values
            .filter { $0.vehicleID == vehicleID }
            .sorted { $0.date > $1.date }
    }

    /// Ascending by (odometer, date) — the ordering the segmentation algorithm requires.
    func entriesForConsumption(vehicleID: VehicleID) async throws -> [FuelEntry] {
        await store.fuelEntries.values
            .filter { $0.vehicleID == vehicleID }
            .sorted { ($0.odometer, $0.date) < ($1.odometer, $1.date) }
    }

    func entry(id: FuelEntryID) async throws -> FuelEntry? { await store.fuelEntries[id] }

    func latest(vehicleID: VehicleID) async throws -> FuelEntry? {
        try await entries(vehicleID: vehicleID).first
    }

    func count(vehicleID: VehicleID) async throws -> Int {
        await store.fuelEntries.values.filter { $0.vehicleID == vehicleID }.count
    }

    func insert(_ entry: FuelEntry) async throws { await store.mutate { $0.fuelEntries[entry.id] = entry } }
    func update(_ entry: FuelEntry) async throws { await store.mutate { $0.fuelEntries[entry.id] = entry } }

    func delete(id: FuelEntryID) async throws -> [FileRef] {
        await store.mutate { store in
            let refs = store.fuelEntries[id]?.receiptRef.map { [$0] } ?? []
            store.fuelEntries.removeValue(forKey: id)
            return refs
        }
    }
}

struct InMemoryServiceRepository: ServiceRepository {
    let store: InMemoryStore

    func query(_ query: ServiceQuery) async throws -> [ServiceRecord] {
        await store.serviceRecords.values
            .filter { record in
                guard record.vehicleID == query.vehicleID else { return false }
                if let range = query.dateRange, !range.contains(record.date) { return false }
                if let types = query.types, types.isDisjoint(with: Set(record.items.map(\.type))) { return false }
                if let nature = query.nature,
                   !record.items.contains(where: { $0.nature == nature }) { return false }
                if let text = query.searchText, !text.isEmpty {
                    let haystack = ([record.workshop, record.note].compactMap { $0 }
                        + record.items.map(\.name)).joined(separator: " ").lowercased()
                    if !haystack.contains(text.lowercased()) { return false }
                }
                return true
            }
            .sorted { $0.date > $1.date }
    }

    func record(id: ServiceRecordID) async throws -> ServiceRecord? { await store.serviceRecords[id] }

    func count(vehicleID: VehicleID) async throws -> Int {
        await store.serviceRecords.values.filter { $0.vehicleID == vehicleID }.count
    }

    func insert(_ record: ServiceRecord) async throws { await store.mutate { $0.serviceRecords[record.id] = record } }
    func update(_ record: ServiceRecord) async throws { await store.mutate { $0.serviceRecords[record.id] = record } }

    func delete(id: ServiceRecordID) async throws -> [FileRef] {
        await store.mutate { store in
            let refs = store.serviceRecords[id]?.attachmentRefs ?? []
            store.serviceRecords.removeValue(forKey: id)
            return refs
        }
    }
}

struct InMemoryExpenseRepository: ExpenseRepository {
    let store: InMemoryStore

    func expenses(vehicleID: VehicleID) async throws -> [Expense] {
        await store.expenses.values
            .filter { $0.vehicleID == vehicleID }
            .sorted { $0.date > $1.date }
    }

    func expense(id: ExpenseID) async throws -> Expense? { await store.expenses[id] }
    func insert(_ expense: Expense) async throws { await store.mutate { $0.expenses[expense.id] = expense } }
    func update(_ expense: Expense) async throws { await store.mutate { $0.expenses[expense.id] = expense } }

    func delete(id: ExpenseID) async throws -> [FileRef] {
        await store.mutate { store in
            let refs = store.expenses[id]?.receiptRef.map { [$0] } ?? []
            store.expenses.removeValue(forKey: id)
            return refs
        }
    }
}

struct InMemoryReminderRepository: ReminderRepository {
    let store: InMemoryStore

    func reminders(vehicleID: VehicleID?, activeOnly: Bool) async throws -> [Reminder] {
        await store.reminders.values
            .filter { reminder in
                if let vehicleID, reminder.vehicleID != vehicleID { return false }
                if activeOnly, !reminder.isActive { return false }
                return true
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func reminder(id: ReminderID) async throws -> Reminder? { await store.reminders[id] }
    func insert(_ reminder: Reminder) async throws { await store.mutate { $0.reminders[reminder.id] = reminder } }
    func update(_ reminder: Reminder) async throws { await store.mutate { $0.reminders[reminder.id] = reminder } }
    func delete(id: ReminderID) async throws { await store.mutate { $0.reminders.removeValue(forKey: id) } }
}

struct InMemoryDocumentRepository: DocumentRepository {
    let store: InMemoryStore

    func query(_ query: DocumentQuery) async throws -> [DocumentMetadata] {
        await store.documents.values
            .filter { document in
                if let vehicleID = query.vehicleID, document.vehicleID != vehicleID { return false }
                if let types = query.types, !types.contains(document.type) { return false }
                if let text = query.searchText, !text.isEmpty {
                    let haystack = "\(document.name) \(document.note ?? "")".lowercased()
                    if !haystack.contains(text.lowercased()) { return false }
                }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func document(id: DocumentID) async throws -> DocumentMetadata? { await store.documents[id] }

    func count(vehicleID: VehicleID) async throws -> Int {
        await store.documents.values.filter { $0.vehicleID == vehicleID }.count
    }

    func insert(_ document: DocumentMetadata) async throws { await store.mutate { $0.documents[document.id] = document } }
    func update(_ document: DocumentMetadata) async throws { await store.mutate { $0.documents[document.id] = document } }

    func delete(id: DocumentID) async throws -> [FileRef] {
        await store.mutate { store in
            var refs: [FileRef] = []
            if let document = store.documents[id] {
                refs.append(document.fileRef)
                if let thumbnail = document.thumbnailRef { refs.append(thumbnail) }
            }
            store.documents.removeValue(forKey: id)
            return refs
        }
    }
}

struct InMemoryAIConversationRepository: AIConversationRepository {
    let store: InMemoryStore

    func summaries(vehicleID: VehicleID?) async throws -> [ConversationSummary] {
        await store.conversations.values
            .filter { vehicleID == nil || $0.vehicleID == vehicleID }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map {
                ConversationSummary(
                    id: $0.id, title: $0.title, updatedAt: $0.updatedAt, messageCount: $0.messages.count
                )
            }
    }

    func conversation(id: ConversationID) async throws -> AIConversation? { await store.conversations[id] }
    func create(_ conversation: AIConversation) async throws {
        await store.mutate { $0.conversations[conversation.id] = conversation }
    }

    func appendMessage(_ message: AIMessage, to id: ConversationID) async throws {
        await store.mutate { store in
            guard var conversation = store.conversations[id] else { return }
            conversation.messages.append(message)
            conversation.updatedAt = message.createdAt
            store.conversations[id] = conversation
        }
    }

    func replaceMessage(_ message: AIMessage, in id: ConversationID) async throws {
        await store.mutate { store in
            guard var conversation = store.conversations[id],
                  let index = conversation.messages.firstIndex(where: { $0.id == message.id })
            else { return }
            conversation.messages[index] = message
            store.conversations[id] = conversation
        }
    }

    func delete(id: ConversationID) async throws -> [FileRef] {
        await store.mutate { store in
            let refs = store.conversations[id]?.messages.flatMap(\.attachments) ?? []
            store.conversations.removeValue(forKey: id)
            return refs
        }
    }
}

struct InMemoryAIInsightRepository: AIInsightRepository {
    let store: InMemoryStore

    func insights(vehicleID: VehicleID) async throws -> [AIInsight] {
        await store.insights.values
            .filter { $0.vehicleID == vehicleID && $0.dismissedAt == nil }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    func replaceAll(_ insights: [AIInsight], vehicleID: VehicleID) async throws {
        await store.mutate { store in
            store.insights = store.insights.filter { $0.value.vehicleID != vehicleID }
            for insight in insights { store.insights[insight.id] = insight }
        }
    }

    func dismiss(id: InsightID, at date: Date) async throws {
        await store.mutate { store in
            store.insights[id]?.dismissedAt = date
        }
    }
}

struct InMemoryNotificationInboxRepository: NotificationInboxRepository {
    let store: InMemoryStore

    func notifications(limit: Int) async throws -> [AppNotification] {
        await Array(store.notifications.values.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    func unreadCount() async throws -> Int {
        await store.notifications.values.filter { !$0.isRead }.count
    }

    func insert(_ notification: AppNotification) async throws {
        await store.mutate { $0.notifications[notification.id] = notification }
    }

    func markRead(ids: [NotificationID], at date: Date) async throws {
        await store.mutate { store in
            for id in ids { store.notifications[id]?.readAt = date }
        }
    }

    func clearAll() async throws { await store.mutate { $0.notifications.removeAll() } }
}

struct InMemoryScanRepository: ScanRepository {
    let store: InMemoryStore

    func receiptScan(id: ReceiptScanID) async throws -> ReceiptScan? { await store.receiptScans[id] }
    func upsert(_ scan: ReceiptScan) async throws { await store.mutate { $0.receiptScans[scan.id] = scan } }
    func insert(_ scan: DashboardScan) async throws { await store.mutate { $0.dashboardScans[scan.id] = scan } }
    func dashboardScan(id: DashboardScanID) async throws -> DashboardScan? { await store.dashboardScans[id] }
    func insert(_ analysis: DamageAnalysis) async throws { await store.mutate { $0.damageAnalyses[analysis.id] = analysis } }
    func damageAnalysis(id: DamageAnalysisID) async throws -> DamageAnalysis? { await store.damageAnalyses[id] }
}
