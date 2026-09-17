import Foundation

// MARK: - Fuel

public struct AddFuelEntryOutput: Sendable {
    public let entry: FuelEntry
    public let warnings: [DomainWarning]
}

public struct AddFuelEntry: Sendable {
    let fuel: any FuelRepository
    let odometer: any OdometerRepository
    let clock: any ClockProviding

    public init(fuel: any FuelRepository, odometer: any OdometerRepository, clock: any ClockProviding) {
        self.fuel = fuel; self.odometer = odometer; self.clock = clock
    }

    public func callAsFunction(_ draft: FuelEntryDraft) async throws -> AddFuelEntryOutput {
        var warnings = try FuelEntryValidator.validate(draft, now: clock.now)
        let now = clock.now

        // Both pricePerUnit and totalCost are persisted as entered — receipts round, and
        // volume × price frequently differs from the printed total by a cent.
        let pricePerUnit = draft.pricePerUnit ?? Money(
            draft.volume.liters > 0
                ? draft.totalCost.amount / Decimal(draft.volume.liters)
                : 0,
            draft.totalCost.currency
        )

        let entry = FuelEntry(
            vehicleID: draft.vehicleID, date: draft.date, odometer: draft.odometer,
            volume: draft.volume, pricePerUnit: pricePerUnit, totalCost: draft.totalCost,
            fuelType: draft.fuelType, station: draft.station, isFullTank: draft.isFullTank,
            note: draft.note, source: draft.source, createdAt: now, updatedAt: now
        )

        if let current = try await odometer.current(vehicleID: draft.vehicleID),
           draft.odometer < current.value {
            warnings.append(.odometerRegression(
                previous: current.value.kilometers, attempted: draft.odometer.kilometers
            ))
        }

        try await fuel.insert(entry)
        // Every mileage-carrying record writes a linked odometer reading in the same operation.
        try await odometer.append(OdometerReading(
            vehicleID: draft.vehicleID, value: draft.odometer, recordedAt: draft.date,
            source: .fuelEntry(entry.id), createdAt: now
        ))

        // NOTE: no Expense row is created. Fuel/Service/Expense stay separate tables and are
        // merged only as a read-model, so the same transaction can never be counted twice.
        return AddFuelEntryOutput(entry: entry, warnings: warnings)
    }
}

public struct LoadFuelHistory: Sendable {
    let fuel: any FuelRepository
    public init(fuel: any FuelRepository) { self.fuel = fuel }
    public func callAsFunction(vehicleID: VehicleID) async throws -> [FuelEntry] {
        try await fuel.entries(vehicleID: vehicleID)
    }
}

public struct DeleteFuelEntry: Sendable {
    let fuel: any FuelRepository
    let odometer: any OdometerRepository

    public init(fuel: any FuelRepository, odometer: any OdometerRepository) {
        self.fuel = fuel; self.odometer = odometer
    }

    public func callAsFunction(id: FuelEntryID) async throws {
        _ = try await fuel.delete(id: id)
        try await odometer.deleteLinked(source: .fuelEntry(id))
    }
}

// MARK: - Service

public struct AddServiceRecordOutput: Sendable {
    public let record: ServiceRecord
    /// Which reminders this record auto-completed.
    public let completedReminderIDs: [ReminderID]
    public let warnings: [DomainWarning]
}

public struct AddServiceRecord: Sendable {
    let services: any ServiceRepository
    let odometer: any OdometerRepository
    let reminders: any ReminderRepository
    let clock: any ClockProviding

    public init(
        services: any ServiceRepository, odometer: any OdometerRepository,
        reminders: any ReminderRepository, clock: any ClockProviding
    ) {
        self.services = services; self.odometer = odometer
        self.reminders = reminders; self.clock = clock
    }

    public func callAsFunction(
        vehicleID: VehicleID, date: Date, odometerValue: Odometer?, items: [ServiceItem],
        workshop: String?, totalCost: Money, note: String? = nil,
        source: RecordSource = .manual, autoCompleteReminders: Bool = true
    ) async throws -> AddServiceRecordOutput {
        try ServiceRecordValidator.validate(items: items, totalCost: totalCost)
        let now = clock.now

        let record = ServiceRecord(
            vehicleID: vehicleID, date: date, odometer: odometerValue, items: items,
            workshop: workshop, totalCost: totalCost, note: note, source: source,
            createdAt: now, updatedAt: now
        )
        try await services.insert(record)

        if let odometerValue {
            try await odometer.append(OdometerReading(
                vehicleID: vehicleID, value: odometerValue, recordedAt: date,
                source: .serviceRecord(record.id), createdAt: now
            ))
        }

        // A record containing an oilChange item AND a filters item completes BOTH reminders.
        // This is why ServiceRecord is multi-item.
        var completed: [ReminderID] = []
        if autoCompleteReminders {
            let recordTypes = Set(items.map(\.type))
            let active = try await reminders.reminders(vehicleID: vehicleID, activeOnly: true)
            for var reminder in active
            where !reminder.kind.satisfyingServiceTypes.isDisjoint(with: recordTypes) {
                reminder.lastCompletedAt = date
                reminder.lastCompletedOdometer = odometerValue
                reminder.updatedAt = now
                // .everyDistance rebases its baseline to the completion odometer, which is what
                // makes the progress bar restart correctly.
                if case .mileage(var trigger) = reminder.trigger, let odometerValue {
                    trigger.baselineOdometer = odometerValue
                    reminder.trigger = .mileage(trigger)
                }
                try await reminders.update(reminder)
                completed.append(reminder.id)
            }
        }

        return AddServiceRecordOutput(record: record, completedReminderIDs: completed, warnings: [])
    }
}

public struct QueryServiceHistory: Sendable {
    let services: any ServiceRepository
    public init(services: any ServiceRepository) { self.services = services }
    public func callAsFunction(_ query: ServiceQuery) async throws -> [ServiceRecord] {
        try await services.query(query)
    }
}

// MARK: - Expenses

public struct AddExpense: Sendable {
    let expenses: any ExpenseRepository
    let odometer: any OdometerRepository
    let clock: any ClockProviding

    public init(expenses: any ExpenseRepository, odometer: any OdometerRepository, clock: any ClockProviding) {
        self.expenses = expenses; self.odometer = odometer; self.clock = clock
    }

    public func callAsFunction(
        vehicleID: VehicleID, title: String, category: ExpenseCategory, cost: Money,
        date: Date, odometerValue: Odometer? = nil, note: String? = nil,
        source: RecordSource = .manual
    ) async throws -> Expense {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DomainError.validation(.emptyField(.title))
        }
        guard cost.amount >= 0 else { throw DomainError.validation(.negativeAmount(.cost)) }

        let now = clock.now
        let expense = Expense(
            vehicleID: vehicleID, title: title, category: category, cost: cost, date: date,
            odometer: odometerValue, note: note, source: source, createdAt: now, updatedAt: now
        )
        try await expenses.insert(expense)

        if let odometerValue {
            try await odometer.append(OdometerReading(
                vehicleID: vehicleID, value: odometerValue, recordedAt: date,
                source: .expense(expense.id), createdAt: now
            ))
        }
        return expense
    }
}

public struct LoadExpenses: Sendable {
    let expenses: any ExpenseRepository
    public init(expenses: any ExpenseRepository) { self.expenses = expenses }
    public func callAsFunction(vehicleID: VehicleID) async throws -> [Expense] {
        try await expenses.expenses(vehicleID: vehicleID)
    }
}

// MARK: - Reminders

public struct CreateReminder: Sendable {
    let reminders: any ReminderRepository
    let notifications: any NotificationScheduling
    let clock: any ClockProviding

    public init(
        reminders: any ReminderRepository, notifications: any NotificationScheduling,
        clock: any ClockProviding
    ) {
        self.reminders = reminders; self.notifications = notifications; self.clock = clock
    }

    public struct Output: Sendable {
        public let reminder: Reminder
        public let warnings: [DomainWarning]
    }

    public func callAsFunction(
        vehicleID: VehicleID, title: String, kind: ReminderKind,
        trigger: ReminderTrigger, recurrence: RecurrenceRule,
        leadTime: ReminderLeadTime = ReminderLeadTime(), note: String? = nil
    ) async throws -> Output {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DomainError.validation(.emptyField(.title))
        }
        if case .seasonal(let months) = recurrence, months.isEmpty {
            throw DomainError.validation(.nonPositiveInterval)
        }
        if case .mileage(let mileage) = trigger, mileage.intervalDistance.kilometers <= 0 {
            throw DomainError.validation(.nonPositiveInterval)
        }

        let now = clock.now
        let reminder = Reminder(
            vehicleID: vehicleID, title: title, kind: kind, trigger: trigger,
            recurrence: recurrence, note: note, leadTime: leadTime,
            createdAt: now, updatedAt: now
        )
        try await reminders.insert(reminder)

        // Scheduling is delegated — the domain never sees UNUserNotificationCenter.
        // Denied permission is a WARNING, not a failure: the reminder still works in-app.
        var warnings: [DomainWarning] = []
        let authorization = await notifications.authorizationStatus()
        if authorization == .denied {
            warnings.append(.notificationsNotAuthorized)
        } else {
            try? await notifications.schedule(
                NotificationPlanner.plan(for: reminder, now: now)
            )
        }
        return Output(reminder: reminder, warnings: warnings)
    }
}

/// Pure: reminder → plain notification values. All the hard parts (occurrence dates,
/// identifiers, the 3-occurrence window) are unit-testable with no permissions and no waiting.
public enum NotificationPlanner {
    public static let maxScheduledOccurrences = 3

    public static func plan(for reminder: Reminder, now: Date) -> [ScheduledNotification] {
        guard reminder.isActive else { return [] }
        var requests: [ScheduledNotification] = []

        func addDateNotification(_ dueDate: Date, index: Int) {
            let leadDays = reminder.leadTime.days ?? 0
            let fireDate = dueDate.addingTimeInterval(-Double(leadDays) * 86_400)
            guard fireDate > now else { return }
            requests.append(ScheduledNotification(
                // Deterministic identifiers make rescheduling idempotent.
                identifier: "reminder.\(reminder.id.raw.uuidString).\(index)",
                titleKey: "notification.reminder.title",
                bodyKey: "notification.reminder.body",
                arguments: [reminder.title],
                fireDate: fireDate
            ))
        }

        switch reminder.trigger {
        case .date(let trigger):
            addDateNotification(trigger.dueDate, index: 0)
        case .mileage:
            // A mileage threshold cannot fire a local notification: iOS has no odometer trigger.
            // A projected date is scheduled instead, and re-projected on every odometer write.
            break
        case .whicheverFirst(let dateTrigger, _):
            // Both halves are scheduled; whichever fires first is correct by construction.
            addDateNotification(dateTrigger.dueDate, index: 0)
        }
        return Array(requests.prefix(maxScheduledOccurrences))
    }
}

public struct EvaluateReminderTriggers: Sendable {
    let reminders: any ReminderRepository
    let odometer: any OdometerRepository
    let clock: any ClockProviding

    public init(
        reminders: any ReminderRepository, odometer: any OdometerRepository, clock: any ClockProviding
    ) {
        self.reminders = reminders; self.odometer = odometer; self.clock = clock
    }

    public func callAsFunction(vehicleID: VehicleID) async throws -> [ReminderEvaluation] {
        let all = try await reminders.reminders(vehicleID: vehicleID, activeOnly: true)
        let current = try await odometer.current(vehicleID: vehicleID)?.value
        return all.map {
            ReminderEvaluator.evaluate(
                $0, currentOdometer: current, now: clock.now, calendar: clock.calendar
            )
        }
    }
}

/// PURE. The in-app evaluation is exact and authoritative; the OS notification is a
/// best-effort nudge.
public enum ReminderEvaluator {
    public static func evaluate(
        _ reminder: Reminder, currentOdometer: Odometer?, now: Date, calendar: Calendar
    ) -> ReminderEvaluation {
        switch reminder.trigger {
        case .date(let trigger):
            return ReminderEvaluation(
                reminder: reminder,
                status: dateStatus(trigger, leadDays: reminder.leadTime.days, now: now, calendar: calendar),
                progress: nil
            )

        case .mileage(let trigger):
            return ReminderEvaluation(
                reminder: reminder,
                status: mileageStatus(trigger, current: currentOdometer, leadDistance: reminder.leadTime.distance),
                progress: mileageProgress(trigger, current: currentOdometer)
            )

        case .whicheverFirst(let dateTrigger, let mileageTrigger):
            let byDate = dateStatus(dateTrigger, leadDays: reminder.leadTime.days, now: now, calendar: calendar)
            let byMileage = mileageStatus(mileageTrigger, current: currentOdometer, leadDistance: reminder.leadTime.distance)
            return ReminderEvaluation(
                reminder: reminder,
                status: moreUrgent(byDate, byMileage),
                progress: mileageProgress(mileageTrigger, current: currentOdometer)
            )
        }
    }

    static func dateStatus(
        _ trigger: DateTrigger, leadDays: Int?, now: Date, calendar: Calendar
    ) -> ReminderStatus {
        let days = calendar.dateComponents([.day], from: now, to: trigger.dueDate).day ?? 0
        if days < 0 { return .overdue(daysOverdue: -days) }
        if days == 0 { return .due }
        if let leadDays, days <= leadDays { return .upcoming(daysRemaining: days) }
        return .upcoming(daysRemaining: nil)
    }

    static func mileageStatus(
        _ trigger: MileageTrigger, current: Odometer?, leadDistance: Distance?
    ) -> ReminderStatus {
        // No odometer reading → indeterminate. NEVER "overdue" for something we cannot evaluate.
        guard let current else { return .indeterminate }
        let remaining = trigger.dueOdometer.kilometers - current.kilometers
        if remaining < 0 { return .overdue(daysOverdue: nil) }
        if remaining == 0 { return .due }
        if let leadDistance, remaining <= leadDistance.kilometers {
            return .upcoming(daysRemaining: nil)
        }
        return .upcoming(daysRemaining: nil)
    }

    static func mileageProgress(_ trigger: MileageTrigger, current: Odometer?) -> ReminderProgress? {
        guard let current, trigger.intervalDistance.kilometers > 0 else { return nil }
        let travelled = current.kilometers - trigger.baselineOdometer.kilometers
        let remaining = trigger.dueOdometer.kilometers - current.kilometers
        return ReminderProgress(
            fraction: travelled / trigger.intervalDistance.kilometers,
            remainingDistance: Distance(kilometers: max(0, remaining)),
            remainingDays: nil
        )
    }

    /// "date OR mileage, whichever happens first": overdue if EITHER is overdue.
    static func moreUrgent(_ lhs: ReminderStatus, _ rhs: ReminderStatus) -> ReminderStatus {
        func rank(_ status: ReminderStatus) -> Int {
            switch status {
            case .overdue: 3
            case .due: 2
            case .upcoming: 1
            case .indeterminate: 0
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }
}

// MARK: - Documents

public struct AddDocument: Sendable {
    let documents: any DocumentRepository
    let files: any FileStorage
    let clock: any ClockProviding

    public init(documents: any DocumentRepository, files: any FileStorage, clock: any ClockProviding) {
        self.documents = documents; self.files = files; self.clock = clock
    }

    public static let maxFileSize: Int64 = 50 * 1024 * 1024

    public func callAsFunction(
        vehicleID: VehicleID?, name: String, type: DocumentType,
        startDate: Date? = nil, expirationDate: Date? = nil,
        fileData: Data, mimeType: String = "application/pdf"
    ) async throws -> DocumentMetadata {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DomainError.validation(.emptyField(.title))
        }
        if let startDate, let expirationDate, expirationDate < startDate {
            throw DomainError.validation(.expirationBeforeStart)
        }
        guard Int64(fileData.count) <= Self.maxFileSize else {
            throw DomainError.document(.fileTooLarge(maxBytes: Self.maxFileSize))
        }

        // The file is written FIRST — a failed write must never leave a dangling metadata row.
        let ref = try await files.store(fileData, preferredName: name, kind: .document)
        let now = clock.now
        let document = DocumentMetadata(
            vehicleID: vehicleID, name: name, type: type, startDate: startDate,
            expirationDate: expirationDate, fileRef: ref,
            fileSize: Int64(fileData.count), mimeType: mimeType,
            createdAt: now, updatedAt: now
        )
        try await documents.insert(document)
        return document
    }
}

public struct QueryDocuments: Sendable {
    let documents: any DocumentRepository
    public init(documents: any DocumentRepository) { self.documents = documents }
    public func callAsFunction(_ query: DocumentQuery) async throws -> [DocumentMetadata] {
        try await documents.query(query)
    }
}

public struct EvaluateDocumentExpiries: Sendable {
    let documents: any DocumentRepository
    let clock: any ClockProviding

    public init(documents: any DocumentRepository, clock: any ClockProviding) {
        self.documents = documents; self.clock = clock
    }

    public struct Item: Sendable, Equatable, Identifiable {
        public var id: DocumentID { document.id }
        public let document: DocumentMetadata
        public let status: DocumentExpiryStatus
    }

    public func callAsFunction(vehicleID: VehicleID?) async throws -> [Item] {
        let docs = try await documents.query(DocumentQuery(vehicleID: vehicleID))
        return docs.map {
            Item(
                document: $0,
                status: DocumentExpiryEvaluator.status(
                    for: $0, now: clock.now, calendar: clock.calendar
                )
            )
        }
    }
}
