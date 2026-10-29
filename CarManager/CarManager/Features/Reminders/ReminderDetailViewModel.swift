import Foundation
import Observation

/// Display values for one reminder.
struct ReminderDetailPresentation: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var value: String
    }
    var symbol: String
    var title: String
    var status: String
    var tone: Tone
    var fraction: Double?
    var startLabel: String?
    var endLabel: String?
    var rows: [Row]
    var isActive: Bool
    var vehicleID: VehicleID
}

@MainActor
@Observable
final class ReminderDetailViewModel {
    private(set) var state: ViewState<ReminderDetailPresentation> = .idle
    private(set) var isWorking = false
    /// Shown after "Mark as done": when it is due next, or that it is finished.
    private(set) var confirmation: String?
    private(set) var errorMessage: String?

    private let reminders: any ReminderRepository
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let complete: CompleteReminder
    private let delete: DeleteReminder
    private let presenter: ReminderPresenter

    init(
        reminders: any ReminderRepository, vehicles: any VehicleRepository, odometer: any OdometerRepository,
        complete: CompleteReminder, delete: DeleteReminder, format: DisplayFormat, clock: any ClockProviding
    ) {
        self.reminders = reminders
        self.vehicles = vehicles
        self.odometer = odometer
        self.complete = complete
        self.delete = delete
        self.presenter = ReminderPresenter(format: format, clock: clock)
    }

    func load(id: ReminderID) async {
        if case .loaded = state {} else { state = .loading }
        do {
            guard let reminder = try await reminders.reminder(id: id) else { state = .empty; return }
            async let reading = odometer.current(vehicleID: reminder.vehicleID)
            async let vehicle = vehicles.vehicle(id: reminder.vehicleID)
            let evaluation = ReminderEvaluator.evaluate(
                reminder, currentOdometer: try await reading?.value,
                now: presenter.clock.now, calendar: presenter.clock.calendar
            )
            state = .loaded(present(evaluation, vehicleName: try await vehicle?.displayName))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func markDone(id: ReminderID) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let updated = try await complete(id: id)
            confirmation = updated.isActive
                ? String(localized: "Done. Next one: \(nextDue(updated)).")
                : String(localized: "Done. This reminder doesn't repeat, so it's now switched off.")
            await load(id: id)
        } catch {
            errorMessage = UserMessage.text(for: error)
        }
    }

    /// Returns `true` when the reminder is gone and the screen should close.
    func remove(id: ReminderID) async -> Bool {
        do {
            try await delete(id: id)
            return true
        } catch {
            errorMessage = UserMessage.text(for: error)
            return false
        }
    }

    // MARK: - Presentation

    func present(_ evaluation: ReminderEvaluation, vehicleName: String?) -> ReminderDetailPresentation {
        let reminder = evaluation.reminder
        let format = presenter.format, now = presenter.clock.now
        let fraction = presenter.fraction(for: evaluation, now: now)
        let card = presenter.nextUp(evaluation, fraction: fraction, now: now)

        var rows: [ReminderDetailPresentation.Row] = [.init(label: String(localized: "Due"), value: nextDue(reminder))]
        rows.append(.init(label: String(localized: "Repeat"), value: presenter.recurrenceText(reminder)))
        if let notify = leadText(reminder) { rows.append(.init(label: String(localized: "Notify"), value: notify)) }
        if let done = reminder.lastCompletedAt {
            let at = reminder.lastCompletedOdometer.map { " · " + format.odometer($0) } ?? ""
            rows.append(.init(label: String(localized: "Last done"), value: format.longDate(done) + at))
        }
        if let vehicleName { rows.append(.init(label: String(localized: "Vehicle"), value: vehicleName)) }

        return ReminderDetailPresentation(
            symbol: reminder.kind.symbolName,
            title: reminder.title,
            status: reminder.isActive ? card.subtitle : String(localized: "Switched off"),
            tone: reminder.isActive ? card.tone : .neutral,
            fraction: reminder.isActive ? card.fraction : nil,
            startLabel: card.startLabel,
            endLabel: card.endLabel,
            rows: rows,
            isActive: reminder.isActive,
            vehicleID: reminder.vehicleID
        )
    }

    /// "12 Nov 2026", "97 120 km", or both for "whichever first".
    private func nextDue(_ reminder: Reminder) -> String {
        let format = presenter.format
        switch reminder.trigger {
        case .date(let d): return format.longDate(d.dueDate)
        case .mileage(let m): return format.odometer(m.dueOdometer)
        case .whicheverFirst(let d, let m): return String(localized: "\(format.longDate(d.dueDate)) or \(format.odometer(m.dueOdometer))")
        }
    }

    private func leadText(_ reminder: Reminder) -> String? {
        switch reminder.trigger {
        case .date, .whicheverFirst:
            guard let days = reminder.leadTime.days else { return nil }
            return days == 0 ? String(localized: "On the day") : String(localized: "\(days) days before")
        case .mileage:
            return reminder.leadTime.distance.map { String(localized: "\(presenter.format.distance($0)) before") }
        }
    }
}
