import Foundation
import Observation

/// Display values for Reminders (Figma 15, empty 26).
struct RemindersPresentation: Equatable, Sendable {
    struct NextUp: Equatable, Sendable {
        var id: ReminderID
        var title: String
        var subtitle: String
        var fraction: Double?
        var startLabel: String?
        var endLabel: String?
        var tone: Tone
    }
    struct Row: Equatable, Sendable, Identifiable {
        var id: ReminderID
        var symbol: String
        var title: String
        var subtitle: String
        var fraction: Double
        var tone: Tone
    }
    var nextUp: NextUp?
    var rows: [Row]
}

@MainActor
@Observable
final class RemindersViewModel {
    private(set) var state: ViewState<RemindersPresentation> = .idle

    private let evaluate: EvaluateReminderTriggers
    private let deleteReminder: DeleteReminder
    private let format: DisplayFormat
    private let clock: any ClockProviding

    init(evaluate: EvaluateReminderTriggers, deleteReminder: DeleteReminder, format: DisplayFormat, clock: any ClockProviding) {
        self.evaluate = evaluate
        self.deleteReminder = deleteReminder
        self.format = format
        self.clock = clock
    }

    func load(vehicleID: VehicleID) async {
        if case .loaded = state {} else { state = .loading }
        do {
            let evaluations = try await evaluate(vehicleID: vehicleID)
            state = evaluations.isEmpty ? .empty : .loaded(present(evaluations))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func delete(_ id: ReminderID, vehicleID: VehicleID) async {
        try? await deleteReminder(id: id)
        await load(vehicleID: vehicleID)
    }

    func present(_ evaluations: [ReminderEvaluation]) -> RemindersPresentation {
        ReminderPresenter(format: format, clock: clock).present(evaluations)
    }
}

/// Turns reminder evaluations into display text. Shared by the Reminders list and the
/// reminder detail screen so both say the same thing.
struct ReminderPresenter {
    let format: DisplayFormat
    let clock: any ClockProviding

    func present(_ evaluations: [ReminderEvaluation]) -> RemindersPresentation {
        let now = clock.now
        let ranked = evaluations
            .map { (evaluation: $0, fraction: fraction(for: $0, now: now)) }
            .sorted { lhs, rhs in
                let l = Self.urgency(lhs.evaluation.status), r = Self.urgency(rhs.evaluation.status)
                return l != r ? l > r : lhs.fraction > rhs.fraction
            }
        let rows = ranked.map { item in
            RemindersPresentation.Row(
                id: item.evaluation.id,
                symbol: item.evaluation.reminder.kind.symbolName,
                title: item.evaluation.reminder.title,
                subtitle: recurrenceText(item.evaluation.reminder),
                fraction: item.fraction,
                tone: tone(item.evaluation.status, fraction: item.fraction)
            )
        }
        return RemindersPresentation(nextUp: ranked.first.map { nextUp($0.evaluation, fraction: $0.fraction, now: now) }, rows: rows)
    }

    static func urgency(_ status: ReminderStatus) -> Int {
        switch status {
        case .overdue: 3
        case .due: 2
        case .upcoming(let days): days == nil ? 0 : 1
        case .indeterminate: -1
        }
    }

    func tone(_ status: ReminderStatus, fraction: Double) -> Tone {
        switch status {
        case .overdue, .due: .danger
        case .upcoming(let days) where days != nil: .warning
        case .indeterminate: .neutral
        default: fraction >= 0.85 ? .warning : .accent
        }
    }

    /// How much of the interval is used up. Mileage uses the evaluator's figure; a date
    /// reminder runs from its last completion (or creation) to the due date.
    func fraction(for evaluation: ReminderEvaluation, now: Date) -> Double {
        if let progress = evaluation.progress { return progress.fraction }
        guard case .date(let trigger) = evaluation.reminder.trigger else { return 0 }
        let start = periodStart(evaluation.reminder, due: trigger.dueDate)
        let span = trigger.dueDate.timeIntervalSince(start)
        guard span > 0 else { return 1 }
        return min(max(now.timeIntervalSince(start) / span, 0), 1)
    }

    /// Where the current period began: the last completion, else one recurrence interval
    /// before the due date, else when the reminder was created.
    func periodStart(_ reminder: Reminder, due: Date) -> Date {
        if let completed = reminder.lastCompletedAt { return completed }
        let back: DateComponents? = switch reminder.recurrence {
        case .everyMonths(let n), .both(let n, _): DateComponents(month: -n)
        case .everyYears(let n): DateComponents(year: -n)
        default: nil
        }
        if let back, let start = format.calendar.date(byAdding: back, to: due) { return min(start, reminder.createdAt) }
        return reminder.createdAt
    }

    func dueDate(_ reminder: Reminder) -> Date? {
        switch reminder.trigger {
        case .date(let t), .whicheverFirst(let t, _): t.dueDate
        case .mileage: nil
        }
    }

    func nextUp(_ evaluation: ReminderEvaluation, fraction: Double, now: Date) -> RemindersPresentation.NextUp {
        let reminder = evaluation.reminder
        var parts: [String] = []
        switch evaluation.status {
        case .overdue(let days):
            parts.append(days.map { String(localized: "Overdue by \($0) days") } ?? String(localized: "Overdue"))
        case .due:
            parts.append(String(localized: "Due today"))
        case .indeterminate:
            parts.append(String(localized: "Log the odometer to track this"))
        case .upcoming:
            if let remaining = evaluation.progress?.remainingDistance {
                parts.append(String(localized: "Due within \(format.distance(remaining))"))
            } else if let due = dueDate(reminder) {
                let days = format.calendar.dateComponents([.day], from: now, to: due).day ?? 0
                parts.append(String(localized: "Due in \(days) days"))
            }
        }
        if let due = dueDate(reminder) { parts.append(format.shortDate(due, relativeTo: now)) }

        var start: String?, end: String?
        switch reminder.trigger {
        case .mileage(let m), .whicheverFirst(_, let m):
            start = format.odometer(m.baselineOdometer); end = format.odometer(m.dueOdometer)
        case .date(let d):
            start = format.shortDate(periodStart(reminder, due: d.dueDate), relativeTo: now)
            end = format.shortDate(d.dueDate, relativeTo: now)
        }
        let isIndeterminate = evaluation.status == .indeterminate
        return .init(
            id: reminder.id, title: reminder.title, subtitle: parts.joined(separator: " · "),
            fraction: isIndeterminate ? nil : fraction, startLabel: start, endLabel: end,
            tone: tone(evaluation.status, fraction: fraction)
        )
    }

    /// "Every 15 000 km", "Yearly · 14 Nov", "Seasonal · Apr / Nov".
    func recurrenceText(_ reminder: Reminder) -> String {
        let due = dueDate(reminder).map { format.shortDate($0, relativeTo: clock.now) }
        switch reminder.recurrence {
        case .none:
            if case .mileage(let m) = reminder.trigger { return String(localized: "At \(format.odometer(m.dueOdometer))") }
            return [String(localized: "Once"), due].compactMap { $0 }.joined(separator: " · ")
        case .everyMonths(let n):
            let base = n == 12 ? String(localized: "recurrence.yearly", defaultValue: "Yearly") : n == 1 ? String(localized: "recurrence.monthly", defaultValue: "Monthly") : String(localized: "Every \(n) months")
            return [base, due].compactMap { $0 }.joined(separator: " · ")
        case .everyYears(let n):
            return n == 1 ? String(localized: "recurrence.yearly", defaultValue: "Yearly") : String(localized: "Every \(n) years")
        case .everyDistance(let d):
            return String(localized: "Every \(format.distance(d))")
        case .both(let months, let distance):
            return String(localized: "Every \(months) months or \(format.distance(distance))")
        case .seasonal(let months):
            let names = months.sorted().compactMap { month in
                format.calendar.date(from: DateComponents(year: 2000, month: month, day: 1)).map { format.month($0) }
            }
            return String(localized: "Seasonal · \(names.joined(separator: " / "))")
        }
    }
}

@MainActor
@Observable
final class AddReminderViewModel {
    enum TriggerKind: Hashable { case date, mileage }
    enum Repeat: Hashable { case never, months6, yearly, years2 }

    var triggerKind: TriggerKind = .date
    var title = ""
    var kind: ReminderKind = .insurance {
        didSet { if kind.prefersMileage != oldValue.prefersMileage { triggerKind = kind.prefersMileage ? .mileage : .date } }
    }
    var dueDate: Date
    var repeatRule: Repeat = .yearly
    var leadDays = 7
    var intervalText = "15000"
    var lastDoneText = ""
    var repeatsByDistance = true
    var leadDistance = 1_000.0
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var vehicleName = ""
    private(set) var currentOdometer: Double?

    let leadDayOptions: [(Int, String)] = [(0, String(localized: "On the day")), (1, String(localized: "1 day before")), (7, String(localized: "7 days before")), (14, String(localized: "14 days before")), (30, String(localized: "30 days before"))]
    var leadDistanceOptions: [(Double, String)] {
        [500.0, 1_000, 2_000].map { ($0, String(localized: "\(format.distance(Distance(kilometers: $0))) before")) }
    }
    let repeatOptions: [(Repeat, String)] = [(.never, String(localized: "Never")), (.months6, String(localized: "Every 6 months")), (.yearly, String(localized: "Every 12 months")), (.years2, String(localized: "Every 2 years"))]

    private let vehicleID: VehicleID
    private let createReminder: CreateReminder
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let router: AppRouter
    let format: DisplayFormat
    let now: Date

    init(
        vehicleID: VehicleID, createReminder: CreateReminder, vehicles: any VehicleRepository,
        odometer: any OdometerRepository, router: AppRouter, format: DisplayFormat, now: Date
    ) {
        self.vehicleID = vehicleID
        self.createReminder = createReminder
        self.vehicles = vehicles
        self.odometer = odometer
        self.router = router
        self.format = format
        self.now = now
        self.dueDate = format.calendar.date(byAdding: .month, value: 1, to: now) ?? now
    }

    func prepare() async {
        if let vehicle = try? await vehicles.vehicle(id: vehicleID) { vehicleName = vehicle.displayName }
        if let current = try? await odometer.current(vehicleID: vehicleID) { currentOdometer = current.value.kilometers }
    }

    var kindOptions: [(ReminderKind, String)] { ReminderKind.allCases.map { ($0, $0.displayName) } }
    var titlePlaceholder: String { kind.displayName }
    private var interval: Double? { NumberInput.double(intervalText).flatMap { $0 > 0 ? $0 : nil } }
    private var baseline: Double? { NumberInput.double(lastDoneText) ?? currentOdometer }

    var canSave: Bool {
        guard !isSaving else { return false }
        switch triggerKind {
        case .date: return true
        case .mileage: return interval != nil && baseline != nil
        }
    }

    /// What will actually happen, in plain words (Figma 30 banner).
    var explanation: String {
        switch triggerKind {
        case .date:
            let fire = format.calendar.date(byAdding: .day, value: -leadDays, to: dueDate) ?? dueDate
            if fire <= now { return String(localized: "That's already inside the notice window — it shows as due soon right away.") }
            if leadDays == 0 { return String(localized: "You'll get a notification on \(format.longDate(fire)).") }
            return String(localized: "You'll get a notification on \(format.longDate(fire)), \(String(localized: "\(leadDays) days before it's due")).")
        case .mileage:
            guard let interval, let baseline else { return String(localized: "Log the odometer once so the app knows where to count from.") }
            let due = Odometer(kilometers: baseline + interval)
            return String(localized: "Due at \(format.odometer(due)). iOS can't trigger on distance, so the app flags it as you log mileage.")
        }
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let trigger: ReminderTrigger
        let recurrence: RecurrenceRule
        let lead: ReminderLeadTime
        switch triggerKind {
        case .date:
            trigger = .date(DateTrigger(dueDate: dueDate))
            recurrence = switch repeatRule {
            case .never: .none
            case .months6: .everyMonths(6)
            case .yearly: .everyMonths(12)
            case .years2: .everyYears(2)
            }
            lead = ReminderLeadTime(days: leadDays, distance: nil)
        case .mileage:
            let distance = Distance(kilometers: interval ?? 0)
            trigger = .mileage(MileageTrigger(baselineOdometer: Odometer(kilometers: baseline ?? 0), intervalDistance: distance))
            recurrence = repeatsByDistance ? .everyDistance(distance) : .none
            lead = ReminderLeadTime(days: nil, distance: Distance(kilometers: leadDistance))
        }
        do {
            _ = try await createReminder(
                vehicleID: vehicleID, title: trimmed.isEmpty ? kind.displayName : trimmed, kind: kind,
                trigger: trigger, recurrence: recurrence, leadTime: lead
            )
            router.dismissModal()
        } catch {
            errorMessage = UserMessage.text(for: error)
        }
    }

    func cancel() { router.dismissModal() }
}
