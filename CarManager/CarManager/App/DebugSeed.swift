#if DEBUG
import Foundation

/// Seeds sample data so a screen can be inspected without typing it in every launch.
///
/// Guarded twice: `#if DEBUG` and an explicit `-seedSampleData` launch argument. It cannot
/// run in a release build, and it does not run in a debug build unless asked for.
enum DebugSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSampleData")
    }

    static func run(_ dependencies: AppDependencies) async {
        guard isRequested else { return }
        guard (try? await dependencies.vehicles.count()) == 0 else { return }

        let now = dependencies.clock.now
        let create = CreateVehicle(
            vehicles: dependencies.vehicles,
            odometer: dependencies.odometer,
            reminders: dependencies.reminders,
            clock: dependencies.clock
        )

        let audi = try? await create(
            VehicleDraft(
                brand: "Audi", model: "A4", year: 2021, trim: "Quattro",
                vin: "WAUZZZ8K9BA123456", fuelType: .diesel,
                initialOdometer: Odometer(kilometers: 82_540)
            ),
            vehicleLimit: nil
        )

        _ = try? await create(
            VehicleDraft(brand: "VW", model: "Golf GTI", year: 2018, fuelType: .petrol),
            vehicleLimit: nil
        )

        guard let vehicleID = audi?.vehicle.id else { return }

        let reminders = CreateReminder(
            reminders: dependencies.reminders,
            notifications: dependencies.notifications,
            clock: dependencies.clock
        )
        _ = try? await reminders(
            vehicleID: vehicleID, title: "Oil change", kind: .oilChange,
            trigger: .mileage(MileageTrigger(
                baselineOdometer: Odometer(kilometers: 82_120),
                intervalDistance: Distance(kilometers: 15_000)
            )),
            recurrence: .everyDistance(Distance(kilometers: 15_000))
        )
        _ = try? await reminders(
            vehicleID: vehicleID, title: "Insurance renewal", kind: .insurance,
            trigger: .date(DateTrigger(dueDate: now.addingTimeInterval(14 * 86_400))),
            recurrence: .everyMonths(12)
        )

        try? await dependencies.insights.replaceAll(
            [AIInsight(
                vehicleID: vehicleID,
                headline: "Fuel consumption up 9% this month",
                body: "Fuel consumption up 9% this month. Check tire pressure and air filter.",
                severity: .attention,
                generatedAt: now,
                validUntil: now.addingTimeInterval(86_400)
            )],
            vehicleID: vehicleID
        )
    }
}
#endif
