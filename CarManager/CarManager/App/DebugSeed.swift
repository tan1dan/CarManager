#if DEBUG
import Foundation
import UIKit

/// Seeds sample data so a screen can be inspected without typing it in every launch.
///
/// Guarded twice: `#if DEBUG` and an explicit `-seedSampleData` launch argument. It cannot
/// run in a release build, and it does not run in a debug build unless asked for.
enum DebugSeed {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedSampleData")
    }

    static func run(_ dependencies: AppDependencies) async {
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") {
            await DemoSeed.run(dependencies)
            return
        }
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

        let day: TimeInterval = 86_400
        await seedRecords(dependencies, vehicleID: vehicleID, now: now)
        for (title, age) in [("Check engine light meaning", day), ("Best winter tires for Audi A4", 15 * day)] {
            let date = now.addingTimeInterval(-age)
            try? await dependencies.conversations.create(AIConversation(
                vehicleID: vehicleID, title: title,
                messages: [AIMessage(role: .user, text: title, createdAt: date)],
                createdAt: date, updatedAt: date
            ))
        }
    }

    /// Eight months of believable history, so every chart and list has something to draw.
    private static func seedRecords(_ d: AppDependencies, vehicleID: VehicleID, now: Date) async {
        let day: TimeInterval = 86_400
        let addFuel = AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: d.clock)
        // Full tank every ~2 weeks; consumption drifts between 5.7 and 6.4 L/100 km.
        let stations = ["Shell V-Power", "Circle K", "Orlen", "BP", "Shell V-Power", "Moya"]
        let consumption = [6.0, 5.9, 6.1, 5.8, 6.0, 5.7, 5.9, 6.0, 5.9, 6.3, 6.4, 6.2, 6.1, 6.3, 6.4, 6.2]
        let distances = consumption.indices.map { 520.0 + Double(($0 * 37) % 90) }
        // History ends just below the 82 540 km the vehicle was created with.
        var km = 82_100 - distances.reduce(0, +)
        for (i, rate) in consumption.enumerated() {
            let distance = distances[i]
            km += distance
            let liters = (distance * rate / 100 * 10).rounded() / 10
            let date = now.addingTimeInterval(-Double(consumption.count - i) * 15 * day + 2 * day)
            let price = Decimal(1.72 + Double(i % 4) * 0.03)
            _ = try? await addFuel(FuelEntryDraft(
                vehicleID: vehicleID, date: date, odometer: Odometer(kilometers: km),
                volume: Volume(liters: liters), totalCost: Money((price * Decimal(liters)).rounded(scale: 2), .eur),
                fuelType: .diesel, station: stations[i % stations.count], isFullTank: true
            ))
        }

        let addService = AddServiceRecord(services: d.services, odometer: d.odometer, reminders: d.reminders, clock: d.clock)
        _ = try? await addService(
            vehicleID: vehicleID, date: now.addingTimeInterval(-9 * day), odometerValue: Odometer(kilometers: 82_120),
            items: [ServiceItem(type: .oilChange, name: "Oil & filter change"), ServiceItem(type: .filters, name: "Air filter")],
            workshop: "AutoService Kraków", totalCost: Money(180, .eur)
        )
        _ = try? await addService(
            vehicleID: vehicleID, date: now.addingTimeInterval(-128 * day), odometerValue: Odometer(kilometers: 76_300),
            items: [ServiceItem(type: .brakes, name: "Brake pads, front", nature: .repair)],
            workshop: "AutoService Kraków", totalCost: Money(232, .eur)
        )
        _ = try? await addService(
            vehicleID: vehicleID, date: now.addingTimeInterval(-262 * day), odometerValue: Odometer(kilometers: 71_940),
            items: [ServiceItem(type: .tires, name: "Seasonal tyre change")],
            workshop: "Tyre Point", totalCost: Money(60, .eur)
        )

        let addExpense = AddExpense(expenses: d.expenses, odometer: d.odometer, clock: d.clock)
        for (title, category, amount, age) in [
            ("Insurance", ExpenseCategory.insurance, Decimal(640), 40.0), ("Car wash", .carWash, 18, 5),
            ("Parking", .parking, 24, 12), ("Car wash", .carWash, 18, 47), ("Road tax", .taxes, 120, 160),
            ("Parking", .parking, 36, 75), ("Phone mount", .accessories, 29, 110)
        ] {
            _ = try? await addExpense(vehicleID: vehicleID, title: title, category: category,
                                      cost: Money(amount, .eur), date: now.addingTimeInterval(-age * day))
        }

        let addDocument = AddDocument(documents: d.documents, files: d.files, clock: d.clock)
        for (name, type, expiry) in [
            ("Insurance policy", DocumentType.insurance, now.addingTimeInterval(14 * day)),
            ("Registration", .registration, now.addingTimeInterval(600 * day)),
            ("Tech. inspection", .technicalInspection, now.addingTimeInterval(150 * day)),
            ("Purchase invoice", .purchaseInvoice, nil as Date?)
        ] {
            _ = try? await addDocument(vehicleID: vehicleID, name: name, type: type, expirationDate: expiry, fileData: samplePDF(title: name))
        }

        for (kind, title, body, age) in [
            (NotificationKind.documentExpiring, "Insurance expires soon", "14 days remaining", 0.1),
            (.reminderDue, "Oil change due", "Within 520 km", 0.3),
            (.aiInsight, "New AI insight", "Fuel efficiency dropped 9%", 3.0),
            (.fuelLogged, "Fuel logged", "Shell V-Power · 48 L", 4.0)
        ] {
            try? await d.inbox.insert(AppNotification(
                vehicleID: vehicleID, kind: kind, titleKey: title, bodyKey: body,
                createdAt: now.addingTimeInterval(-age * day)
            ))
        }
    }

    /// A one-page A4 PDF with a title and placeholder lines, so the viewer has something real to show.
    static func samplePDF(title: String) -> Data {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            context.beginPage()
            (title as NSString).draw(at: CGPoint(x: 56, y: 64), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 26)])
            ("Sample document · generated for debugging" as NSString)
                .draw(at: CGPoint(x: 56, y: 104), withAttributes: [.font: UIFont.systemFont(ofSize: 12), .foregroundColor: UIColor.gray])
            UIColor(white: 0.88, alpha: 1).setFill()
            for row in 0..<14 {
                let width: CGFloat = row % 3 == 2 ? 260 : 483
                UIBezierPath(roundedRect: CGRect(x: 56, y: 160 + CGFloat(row) * 34, width: width, height: 12), cornerRadius: 6).fill()
            }
        }
    }
}

/// `-seedDemo`: one car with three months of believable history, for screenshots and demos.
/// 30 fill-ups, 5 service visits, a driver licence, expenses, reminders and an AI chat.
enum DemoSeed {
    static func run(_ d: AppDependencies) async {
        guard (try? await d.vehicles.count()) == 0 else { return }
        let now = d.clock.now, day: TimeInterval = 86_400
        let start = now.addingTimeInterval(-90 * day)
        let startKm = 27_850.0
        // Like a real user: the car is added with today's mileage, history is entered after.
        let todayKm = 37_410.0

        guard let car = try? await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: d.clock)(
            VehicleDraft(brand: "Porsche", model: "Macan S Diesel", year: 2023, trim: "S", vin: "WP1ZZZ95ZPLB12345",
                         licensePlate: "WX 4821K", fuelType: .diesel, initialOdometer: Odometer(kilometers: todayKm)),
            vehicleLimit: nil
        ).vehicle.id else { return }

        // 30 full tanks, one every 3 days. Consumption drifts between 7.9 and 9.4 L/100 km:
        // city weeks are thirstier, two motorway trips pull it down.
        let addFuel = AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: d.clock)
        let stations = ["Orlen", "Shell V-Power", "BP", "Circle K", "Moya", "Orlen", "Amic"]
        var km = startKm
        for i in 0..<30 {
            let distance = 230 + Double((i * 53) % 140) + (i == 9 || i == 22 ? 260 : 0)
            let rate = [8.6, 8.9, 8.3, 9.1, 8.7, 8.2, 9.4, 8.8, 8.5, 7.9][i % 10] + (i >= 20 ? 0.2 : 0)
            km += distance
            let liters = (distance * rate / 100 * 10).rounded() / 10
            let price = Decimal(6.19 + Double((i * 7) % 9) * 0.04)          // PLN-ish €/L feel, in EUR below
            let date = start.addingTimeInterval(Double(i) * 3 * day + Double(i % 3) * 3_600 * 5)
            _ = try? await addFuel(FuelEntryDraft(
                vehicleID: car, date: date, odometer: Odometer(kilometers: km.rounded()),
                volume: Volume(liters: liters),
                totalCost: Money((price / 4.3 * Decimal(liters)).rounded(scale: 2), .eur),
                fuelType: .diesel, station: stations[i % stations.count], isFullTank: true
            ))
        }

        // Five workshop visits spread over the quarter.
        let addService = AddServiceRecord(services: d.services, odometer: d.odometer, reminders: d.reminders, clock: d.clock)
        let services: [(Double, Double, [ServiceItem], String, Decimal)] = [
            (6, 28_120, [ServiceItem(type: .tires, name: "Winter tyres fitted")], "Vulco Warszawa", 95),
            (24, 29_640, [ServiceItem(type: .oilChange, name: "Oil & filter change"), ServiceItem(type: .filters, name: "Cabin filter")], "Porsche Centrum Warszawa", 389),
            (47, 31_470, [ServiceItem(type: .electrical, name: "Battery check & software update")], "Porsche Centrum Warszawa", 120),
            (63, 32_880, [ServiceItem(type: .brakes, name: "Front brake pads", nature: .repair)], "AutoSerwis Mokotów", 410),
            (81, 34_560, [ServiceItem(type: .other, name: "AdBlue top-up & wiper blades")], "AutoSerwis Mokotów", 64)
        ]
        for (offset, odo, items, workshop, cost) in services {
            _ = try? await addService(vehicleID: car, date: start.addingTimeInterval(offset * day),
                                      odometerValue: Odometer(kilometers: odo), items: items,
                                      workshop: workshop, totalCost: Money(cost, .eur))
        }

        // Everyday costs.
        let addExpense = AddExpense(expenses: d.expenses, odometer: d.odometer, clock: d.clock)
        let expenses: [(String, ExpenseCategory, Decimal, Double)] = [
            ("OC/AC insurance", .insurance, 1_180, 12), ("Car wash", .carWash, 18, 20), ("Parking Śródmieście", .parking, 36, 29),
            ("Car wash", .carWash, 22, 44), ("A2 motorway toll", .other, 41, 27), ("Parking airport", .parking, 64, 66),
            ("Car wash", .carWash, 18, 72), ("Phone mount", .accessories, 29, 55), ("A2 motorway toll", .other, 41, 68),
            ("Parking Śródmieście", .parking, 24, 86)
        ]
        for (title, category, amount, offset) in expenses {
            _ = try? await addExpense(vehicleID: car, title: title, category: category, cost: Money(amount, .eur),
                                      date: start.addingTimeInterval(offset * day))
        }

        // Documents: the driver licence, plus the policy and inspection that go with the car.
        let addDocument = AddDocument(documents: d.documents, files: d.files, clock: d.clock)
        let documents: [(String, DocumentType, Date?)] = [
            ("Driver licence", .driverLicense, now.addingTimeInterval(1_640 * day)),
            ("OC/AC insurance policy", .insurance, now.addingTimeInterval(285 * day)),
            ("Technical inspection", .technicalInspection, now.addingTimeInterval(19 * day))
        ]
        for (name, type, expiry) in documents {
            _ = try? await addDocument(vehicleID: car, name: name, type: type, expirationDate: expiry,
                                       fileData: DebugSeed.samplePDF(title: name))
        }

        // Reminders: mileage and date based, one due soon so Home has something to say.
        // A spy scheduler: seeding must not stop at the system permission prompt.
        let createReminder = CreateReminder(reminders: d.reminders, notifications: SpyNotificationScheduler(), clock: d.clock)
        _ = try? await createReminder(vehicleID: car, title: "Oil change", kind: .oilChange,
            trigger: .mileage(MileageTrigger(baselineOdometer: Odometer(kilometers: 29_640), intervalDistance: Distance(kilometers: 15_000))),
            recurrence: .everyDistance(Distance(kilometers: 15_000)))
        _ = try? await createReminder(vehicleID: car, title: "Technical inspection", kind: .technicalInspection,
            trigger: .date(DateTrigger(dueDate: now.addingTimeInterval(19 * day))), recurrence: .everyYears(1),
            leadTime: ReminderLeadTime(days: 30, distance: nil))
        _ = try? await createReminder(vehicleID: car, title: "Tyre swap", kind: .tireChange,
            trigger: .date(DateTrigger(dueDate: now.addingTimeInterval(160 * day))), recurrence: .seasonal(months: [4, 10]))
        _ = try? await createReminder(vehicleID: car, title: "Insurance renewal", kind: .insurance,
            trigger: .date(DateTrigger(dueDate: now.addingTimeInterval(285 * day))), recurrence: .everyMonths(12),
            leadTime: ReminderLeadTime(days: 30, distance: nil))
        _ = try? await createReminder(vehicleID: car, title: "Brake fluid", kind: .custom,
            trigger: .date(DateTrigger(dueDate: now.addingTimeInterval(400 * day))), recurrence: .everyYears(2))

        // One past AI conversation and a couple of inbox items.
        let asked = now.addingTimeInterval(-6 * day)
        try? await d.conversations.create(AIConversation(
            vehicleID: car, title: "Why did consumption go up?",
            messages: [
                AIMessage(role: .user, text: "Why did my consumption go up from 8.3 to 9.4 L/100 km this month?", createdAt: asked),
                AIMessage(role: .assistant, text: "On a 2023 Macan S Diesel the most common reasons are winter tyres and lower temperatures (often +5–10%), more short city trips, and a DPF regeneration cycle. Check tyre pressure first — winter tyres are often under-inflated after fitting.", createdAt: asked.addingTimeInterval(8))
            ],
            createdAt: asked, updatedAt: asked.addingTimeInterval(8)
        ))
        for (kind, title, body, age) in [
            (NotificationKind.documentExpiring, "Technical inspection soon", "Due in 19 days", 0.2),
            (.reminderDue, "Brake pads replaced", "Service record saved · AutoSerwis Mokotów", 27.0)
        ] {
            try? await d.inbox.insert(AppNotification(vehicleID: car, kind: kind, titleKey: title, bodyKey: body,
                                                      createdAt: now.addingTimeInterval(-age * day)))
        }
    }
}
#endif
