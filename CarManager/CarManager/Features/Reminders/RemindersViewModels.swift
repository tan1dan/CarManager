import Foundation
import Observation

@MainActor
@Observable
final class RemindersViewModel {
    private(set) var state: ViewState<[ReminderEvaluation]> = .idle

    private let evaluate: EvaluateReminderTriggers
    init(evaluate: EvaluateReminderTriggers) { self.evaluate = evaluate }

    /// The most urgent evaluation drives the "Next up" card.
    var nextUp: ReminderEvaluation? {
        guard case .loaded(let evaluations) = state else { return nil }
        return evaluations.first { if case .overdue = $0.status { return true }; return false }
            ?? evaluations.first { if case .due = $0.status { return true }; return false }
            ?? evaluations.first
    }

    func load(vehicleID: VehicleID) async {
        state = .loading
        do {
            let evaluations = try await evaluate(vehicleID: vehicleID)
            state = evaluations.isEmpty ? .empty : .loaded(evaluations)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}

@MainActor
@Observable
final class AddReminderViewModel {
    enum TriggerKind: Hashable { case date, mileage, whicheverFirst }

    var title = ""
    var triggerKind: TriggerKind = .date
    private(set) var state: ViewState<Reminder> = .idle
    /// Denied notification permission is a WARNING, not a failure — the reminder still works.
    private(set) var warnings: [DomainWarning] = []

    private let vehicleID: VehicleID
    private let createReminder: CreateReminder
    private let router: AppRouter
    private let now: Date

    init(vehicleID: VehicleID, createReminder: CreateReminder, router: AppRouter, now: Date) {
        self.vehicleID = vehicleID
        self.createReminder = createReminder
        self.router = router
        self.now = now
    }

    func save() async {
        state = .loading
        let dueDate = DateTrigger(dueDate: now.addingTimeInterval(30 * 86_400))
        let mileage = MileageTrigger(
            baselineOdometer: Odometer(kilometers: 0),
            intervalDistance: Distance(kilometers: 15_000)
        )
        let trigger: ReminderTrigger = switch triggerKind {
        case .date: .date(dueDate)
        case .mileage: .mileage(mileage)
        case .whicheverFirst: .whicheverFirst(dueDate, mileage)
        }

        do {
            let output = try await createReminder(
                vehicleID: vehicleID, title: title, kind: .custom,
                trigger: trigger, recurrence: .none
            )
            warnings = output.warnings
            state = .loaded(output.reminder)
            router.dismissModal()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
