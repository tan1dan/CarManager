import Testing
import Foundation
@testable import CarManager

@Suite("Completing reminders")
@MainActor
struct ReminderCompletionTests {
    private let clock = FixedClock()      // 2025-10-09 UTC

    private func setUp() async throws -> (AppDependencies, VehicleID) {
        let d = makeDependencies(clock: clock)
        let id = try await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock)(
            VehicleDraft(brand: "Audi", model: "A4", initialOdometer: Odometer(kilometers: 90_000)), vehicleLimit: nil
        ).vehicle.id
        return (d, id)
    }

    private func create(_ d: AppDependencies, _ vehicle: VehicleID, trigger: ReminderTrigger, recurrence: RecurrenceRule) async throws -> ReminderID {
        try await CreateReminder(reminders: d.reminders, notifications: d.notifications, clock: clock)(
            vehicleID: vehicle, title: "Test", kind: .custom, trigger: trigger, recurrence: recurrence
        ).reminder.id
    }

    private func complete(_ d: AppDependencies, _ id: ReminderID) async throws -> Reminder {
        try await CompleteReminder(reminders: d.reminders, odometer: d.odometer, notifications: d.notifications, clock: clock)(id: id)
    }

    @Test("Done early, a yearly reminder keeps its schedule: twelve months after the old due date")
    func yearly() async throws {
        let (d, car) = try await setUp()
        let due = clock.now.addingTimeInterval(5 * 86_400)
        let id = try await create(d, car, trigger: .date(DateTrigger(dueDate: due)), recurrence: .everyMonths(12))
        let done = try await complete(d, id)
        guard case .date(let next) = done.trigger else { Issue.record("trigger changed kind"); return }
        #expect(next.dueDate == clock.calendar.date(byAdding: .month, value: 12, to: due))
        #expect(done.isActive && done.lastCompletedAt == clock.now)
    }

    @Test("A mileage reminder restarts from the current odometer")
    func mileage() async throws {
        let (d, car) = try await setUp()
        let id = try await create(d, car, trigger: .mileage(MileageTrigger(
            baselineOdometer: Odometer(kilometers: 75_000), intervalDistance: Distance(kilometers: 15_000)
        )), recurrence: .everyDistance(Distance(kilometers: 15_000)))
        let done = try await complete(d, id)
        guard case .mileage(let m) = done.trigger else { Issue.record("trigger changed kind"); return }
        #expect(m.baselineOdometer.kilometers == 90_000)
        #expect(m.dueOdometer.kilometers == 105_000)
        #expect(done.lastCompletedOdometer?.kilometers == 90_000)
    }

    @Test("A one-off reminder is switched off and drops out of Home's list")
    func oneOff() async throws {
        let (d, car) = try await setUp()
        let id = try await create(d, car, trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(86_400))), recurrence: .none)
        let done = try await complete(d, id)
        #expect(!done.isActive)
        let active = try await EvaluateReminderTriggers(reminders: d.reminders, odometer: d.odometer, clock: clock)(vehicleID: car)
        #expect(!active.contains { $0.id == id })
    }

    @Test("Done late, a yearly reminder restarts from the day it was done")
    func yearlyLate() async throws {
        let (d, car) = try await setUp()
        let id = try await create(d, car, trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(1 * 86_400))), recurrence: .everyMonths(12))
        // Mark it done 10 days after it was due.
        let late = ReminderScheduler.complete(try #require(try await d.reminders.reminder(id: id)),
                                              at: clock.now.addingTimeInterval(11 * 86_400), odometer: nil, calendar: clock.calendar)
        guard case .date(let next) = late.trigger else { Issue.record("trigger changed kind"); return }
        #expect(next.dueDate == clock.calendar.date(byAdding: .month, value: 12, to: clock.now.addingTimeInterval(11 * 86_400)))
    }

    @Test("Seasonal reminders jump to the next listed month")
    func seasonal() {
        let next = ReminderScheduler.nextDueDate(after: clock.now, recurrence: .seasonal(months: [4, 11]), calendar: clock.calendar)
        #expect(next.map { clock.calendar.component(.month, from: $0) } == 11)
    }

    @Test("The detail screen shows the reminder instead of an empty page")
    func detailLoads() async throws {
        let (d, car) = try await setUp()
        let id = try await create(d, car, trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(14 * 86_400))), recurrence: .everyMonths(12))
        let viewModel = ReminderDetailViewModel(
            reminders: d.reminders, vehicles: d.vehicles, odometer: d.odometer,
            complete: CompleteReminder(reminders: d.reminders, odometer: d.odometer, notifications: d.notifications, clock: clock),
            delete: DeleteReminder(reminders: d.reminders, notifications: d.notifications),
            format: DisplayFormat(locale: Locale(identifier: "en_US"), calendar: clock.calendar), clock: clock
        )
        await viewModel.load(id: id)
        let p = try #require(viewModel.state.value)
        #expect(p.title == "Test")
        #expect(p.status.contains("14 days"))
        #expect(p.rows.map(\.label).starts(with: ["Due", "Repeat"]))
        #expect(p.rows.contains { $0.label == "Vehicle" && $0.value == "Audi A4" })

        await viewModel.markDone(id: id)
        #expect(viewModel.confirmation?.hasPrefix("Done. Next one:") == true)
        #expect(viewModel.state.value?.rows.contains { $0.label == "Last done" } == true)
    }
}
