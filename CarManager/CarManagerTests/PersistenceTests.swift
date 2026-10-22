import Testing
import Foundation
@testable import CarManager

/// These run against the REAL SwiftData stack (in-memory store, no CloudKit), so the
/// mapping, the predicates and the sort orders are the ones production uses.
@Suite("SwiftData persistence")
struct PersistenceTests {
    private let clock = FixedClock()

    private func makeStore() -> PersistenceActor {
        let (container, mode) = PersistenceContainer.make(inMemory: true)
        #expect(mode == .inMemory)
        return PersistenceActor(modelContainer: container)
    }

    private func vehicle(
        _ brand: String = "Audi", model: String = "A4", isDefault: Bool = false, offset: TimeInterval = 0
    ) -> Vehicle {
        Vehicle(
            brand: brand, model: model, year: 2021, vin: "WAUZZZ8K9BA123456",
            fuelType: .diesel, purchasePrice: Money(24_500, .eur), isDefault: isDefault,
            createdAt: clock.now.addingTimeInterval(offset),
            updatedAt: clock.now.addingTimeInterval(offset)
        )
    }

    @Test("A vehicle survives the round trip with every field intact")
    func vehicleRoundTrip() async throws {
        let store = makeStore()
        var original = vehicle()
        original.photoRef = FileRef(relativePath: "photos/audi.jpg", checksum: "abc")
        original.trim = "Quattro"
        original.engineDisplacementCC = 1_968

        try await store.saveVehicle(original)
        let loaded = try #require(try await store.vehicle(id: original.id))

        #expect(loaded == original)
        // Decimal money must not drift through storage.
        #expect(loaded.purchasePrice?.amount == Decimal(24_500))
        #expect(loaded.photoRef?.relativePath == "photos/audi.jpg")
    }

    @Test("Saving the same id twice updates the row instead of duplicating it")
    func upsert() async throws {
        let store = makeStore()
        var v = vehicle()
        try await store.saveVehicle(v)
        v.model = "A6"
        v.updatedAt = clock.now.addingTimeInterval(60)
        try await store.saveVehicle(v)

        let all = try await store.vehicles()
        #expect(all.count == 1)
        #expect(all.first?.model == "A6")
    }

    @Test("Vehicles come back oldest first, the way the garage lists them")
    func vehicleOrder() async throws {
        let store = makeStore()
        try await store.saveVehicle(vehicle("VW", model: "Golf", offset: 100))
        try await store.saveVehicle(vehicle("Audi", model: "A4", offset: 0))

        #expect(try await store.vehicles().map(\.brand) == ["Audi", "VW"])
    }

    @Test("Setting a default clears the flag on every other vehicle")
    func singleDefault() async throws {
        let store = makeStore()
        let first = vehicle("Audi", isDefault: true)
        let second = vehicle("VW", model: "Golf", offset: 10)
        try await store.saveVehicle(first)
        try await store.saveVehicle(second)

        try await store.setDefaultVehicle(id: second.id)

        let all = try await store.vehicles()
        #expect(all.filter(\.isDefault).map(\.id) == [second.id])
        #expect(try await store.defaultVehicle()?.id == second.id)
    }

    @Test("Deleting a vehicle removes its records, keeps its chats, and reports orphaned files")
    func cascade() async throws {
        let store = makeStore()
        var v = vehicle()
        v.photoRef = FileRef(relativePath: "photos/audi.jpg")
        try await store.saveVehicle(v)
        let other = vehicle("VW", model: "Golf", offset: 10)
        try await store.saveVehicle(other)

        try await store.appendOdometer(OdometerReading(
            vehicleID: v.id, value: Odometer(kilometers: 82_540), recordedAt: clock.now,
            source: .manual, createdAt: clock.now
        ))
        try await store.saveFuelEntry(fuelEntry(vehicleID: v.id, km: 82_540, date: clock.now))
        try await store.saveReminder(Reminder(
            vehicleID: v.id, title: "Oil change", kind: .oilChange,
            trigger: .date(DateTrigger(dueDate: clock.now)), createdAt: clock.now, updatedAt: clock.now
        ))
        try await store.saveFuelEntry(fuelEntry(vehicleID: other.id, km: 1_000, date: clock.now))
        let chat = AIConversation(vehicleID: v.id, title: "Check engine", createdAt: clock.now, updatedAt: clock.now)
        try await store.createConversation(chat)

        let orphaned = try await store.deleteVehicle(id: v.id)

        #expect(orphaned.map(\.relativePath) == ["photos/audi.jpg"])
        #expect(try await store.vehicle(id: v.id) == nil)
        #expect(try await store.fuelCount(vehicleID: v.id) == 0)
        #expect(try await store.reminders(vehicleID: v.id, activeOnly: false).isEmpty)
        #expect(try await store.odometerReadings(vehicleID: v.id).isEmpty)
        // The other vehicle is untouched.
        #expect(try await store.fuelCount(vehicleID: other.id) == 1)
        // A chat outlives the car it discussed; it just loses the link.
        let keptChat = try #require(try await store.conversation(id: chat.id))
        #expect(keptChat.vehicleID == nil)
    }

    private func fuelEntry(vehicleID: VehicleID, km: Double, date: Date, full: Bool = true) -> FuelEntry {
        FuelEntry(
            vehicleID: vehicleID, date: date, odometer: Odometer(kilometers: km),
            volume: Volume(liters: 45), pricePerUnit: Money(Decimal(1.75), .eur),
            totalCost: Money(Decimal(78.75), .eur), fuelType: .diesel, isFullTank: full,
            createdAt: date, updatedAt: date
        )
    }

    @Test("Fuel history is newest first, while the consumption feed is oldest first by odometer")
    func fuelOrdering() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        let day: TimeInterval = 86_400
        try await store.saveFuelEntry(fuelEntry(vehicleID: v.id, km: 1_000, date: clock.now))
        try await store.saveFuelEntry(fuelEntry(vehicleID: v.id, km: 500, date: clock.now.addingTimeInterval(-day)))
        try await store.saveFuelEntry(fuelEntry(vehicleID: v.id, km: 1_500, date: clock.now.addingTimeInterval(day)))

        #expect(try await store.fuelEntries(vehicleID: v.id).map(\.odometer.kilometers) == [1_500, 1_000, 500])
        #expect(try await store.fuelEntriesForConsumption(vehicleID: v.id).map(\.odometer.kilometers) == [500, 1_000, 1_500])
    }

    @Test("Deleting a fuel entry hands back its receipt so the file can be removed")
    func deleteFuelReturnsFiles() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        var entry = fuelEntry(vehicleID: v.id, km: 1_000, date: clock.now)
        entry.receiptRef = FileRef(relativePath: "receipts/1.jpg")
        try await store.saveFuelEntry(entry)

        let refs = try await store.deleteFuelEntry(id: entry.id)

        #expect(refs.map(\.relativePath) == ["receipts/1.jpg"])
        #expect(try await store.fuelEntry(id: entry.id) == nil)
    }

    @Test("The current odometer is the newest reading, not the highest number")
    func currentOdometer() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        // A typo corrected later: the newer, lower reading wins.
        try await store.appendOdometer(OdometerReading(
            vehicleID: v.id, value: Odometer(kilometers: 99_999),
            recordedAt: clock.now.addingTimeInterval(-3_600), source: .manual, createdAt: clock.now
        ))
        try await store.appendOdometer(OdometerReading(
            vehicleID: v.id, value: Odometer(kilometers: 82_540),
            recordedAt: clock.now, source: .manual, createdAt: clock.now
        ))

        #expect(try await store.currentOdometer(vehicleID: v.id)?.value.kilometers == 82_540)
    }

    @Test("Readings linked to a deleted record are removed with it")
    func deleteLinkedOdometer() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        let entry = fuelEntry(vehicleID: v.id, km: 1_000, date: clock.now)
        try await store.saveFuelEntry(entry)
        try await store.appendOdometer(OdometerReading(
            vehicleID: v.id, value: Odometer(kilometers: 1_000), recordedAt: clock.now,
            source: .fuelEntry(entry.id), createdAt: clock.now
        ))
        try await store.appendOdometer(OdometerReading(
            vehicleID: v.id, value: Odometer(kilometers: 1_100), recordedAt: clock.now,
            source: .manual, createdAt: clock.now
        ))

        try await store.deleteOdometerLinked(to: .fuelEntry(entry.id))

        let readings = try await store.odometerReadings(vehicleID: v.id)
        #expect(readings.count == 1)
        #expect(readings.first?.source == .manual)
    }

    @Test("A service record keeps its items, parts and money through storage")
    func serviceRoundTrip() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        let record = ServiceRecord(
            vehicleID: v.id, date: clock.now, odometer: Odometer(kilometers: 82_120),
            items: [
                ServiceItem(type: .oilChange, name: "Oil & filter", partCost: Money(Decimal(60), .eur),
                            laborCost: Money(Decimal(40), .eur),
                            parts: [PartUsage(name: "Castrol 5W-30", partNumber: "C530", quantity: 5,
                                              unitCost: Money(Decimal(12), .eur))]),
                ServiceItem(type: .filters, name: "Air filter", nature: .repair)
            ],
            workshop: "AutoService Kraków", totalCost: Money(Decimal(180), .eur),
            attachmentRefs: [FileRef(relativePath: "docs/invoice.pdf")],
            createdAt: clock.now, updatedAt: clock.now
        )

        try await store.saveServiceRecord(record)
        let loaded = try #require(try await store.serviceRecord(id: record.id))

        #expect(loaded == record)
        #expect(loaded.items.first?.parts.first?.unitCost?.amount == Decimal(12))
        #expect(loaded.isRepair)
    }

    @Test("Service queries filter on type, nature and text")
    func serviceQuery() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        let oil = ServiceRecord(
            vehicleID: v.id, date: clock.now, items: [ServiceItem(type: .oilChange, name: "Oil")],
            workshop: "Kraków", totalCost: Money(Decimal(180), .eur), createdAt: clock.now, updatedAt: clock.now
        )
        let brakes = ServiceRecord(
            vehicleID: v.id, date: clock.now.addingTimeInterval(-86_400),
            items: [ServiceItem(type: .brakes, name: "Pads", nature: .repair)],
            workshop: "Tyre Point", totalCost: Money(Decimal(232), .eur), createdAt: clock.now, updatedAt: clock.now
        )
        try await store.saveServiceRecord(oil)
        try await store.saveServiceRecord(brakes)

        #expect(try await store.serviceRecords(ServiceQuery(vehicleID: v.id)).map(\.id) == [oil.id, brakes.id])
        #expect(try await store.serviceRecords(ServiceQuery(vehicleID: v.id, types: [.brakes])).map(\.id) == [brakes.id])
        #expect(try await store.serviceRecords(ServiceQuery(vehicleID: v.id, nature: .repair)).map(\.id) == [brakes.id])
        #expect(try await store.serviceRecords(ServiceQuery(vehicleID: v.id, searchText: "kraków")).map(\.id) == [oil.id])
    }

    @Test("Reminder triggers and recurrence rules survive, payloads and all")
    func reminderRoundTrip() async throws {
        let store = makeStore()
        let v = vehicle()
        try await store.saveVehicle(v)
        let reminder = Reminder(
            vehicleID: v.id, title: "Tyre swap", kind: .tireChange,
            trigger: .whicheverFirst(
                DateTrigger(dueDate: clock.now.addingTimeInterval(86_400 * 30)),
                MileageTrigger(baselineOdometer: Odometer(kilometers: 82_000),
                               intervalDistance: Distance(kilometers: 15_000))
            ),
            recurrence: .seasonal(months: [4, 11]),
            lastCompletedOdometer: Odometer(kilometers: 70_000),
            leadTime: ReminderLeadTime(days: 7, distance: Distance(kilometers: 500)),
            createdAt: clock.now, updatedAt: clock.now
        )

        try await store.saveReminder(reminder)

        #expect(try await store.reminder(id: reminder.id) == reminder)
        #expect(try await store.reminders(vehicleID: nil, activeOnly: true).count == 1)
    }

    @Test("Conversations store their messages and append in order")
    func conversationMessages() async throws {
        let store = makeStore()
        let chat = AIConversation(title: "Check engine", createdAt: clock.now, updatedAt: clock.now)
        try await store.createConversation(chat)

        let question = AIMessage(role: .user, text: "What does it mean?", createdAt: clock.now)
        let answer = AIMessage(role: .assistant, text: "A fault was found.",
                               isPartial: true, createdAt: clock.now.addingTimeInterval(1))
        try await store.appendMessage(question, to: chat.id)
        try await store.appendMessage(answer, to: chat.id)

        var finished = answer
        finished.text = "A fault was found. Drive gently to a mechanic."
        finished.isPartial = false
        try await store.replaceMessage(finished, in: chat.id)

        let loaded = try #require(try await store.conversation(id: chat.id))
        #expect(loaded.messages.map(\.role) == [.user, .assistant])
        #expect(loaded.messages.last?.isPartial == false)
        #expect(loaded.messages.last?.text.hasSuffix("mechanic.") == true)
        #expect(loaded.updatedAt == answer.createdAt)

        let summaries = try await store.conversationSummaries(vehicleID: nil)
        #expect(summaries.first?.messageCount == 2)
    }

    @Test("Replacing insights swaps only the given vehicle's rows, and dismissed ones drop out")
    func insights() async throws {
        let store = makeStore()
        let a = vehicle("Audi")
        let b = vehicle("VW", model: "Golf", offset: 10)
        try await store.saveVehicle(a)
        try await store.saveVehicle(b)
        let keep = AIInsight(vehicleID: b.id, headline: "Keep me", body: "",
                             generatedAt: clock.now, validUntil: clock.now)
        try await store.replaceInsights([keep], vehicleID: b.id)
        let first = AIInsight(vehicleID: a.id, headline: "Old", body: "",
                              generatedAt: clock.now, validUntil: clock.now)
        try await store.replaceInsights([first], vehicleID: a.id)

        let fresh = AIInsight(vehicleID: a.id, headline: "New", body: "",
                              generatedAt: clock.now, validUntil: clock.now)
        try await store.replaceInsights([fresh], vehicleID: a.id)

        #expect(try await store.insights(vehicleID: a.id).map(\.headline) == ["New"])
        #expect(try await store.insights(vehicleID: b.id).map(\.headline) == ["Keep me"])

        try await store.dismissInsight(id: fresh.id, at: clock.now)
        #expect(try await store.insights(vehicleID: a.id).isEmpty)
    }

    @Test("The inbox is newest first, respects the limit and counts only unread items")
    func notifications() async throws {
        let store = makeStore()
        let ids = (0..<3).map { _ in NotificationID() }
        for (index, id) in ids.enumerated() {
            try await store.insertNotification(AppNotification(
                id: id, kind: .reminderDue, titleKey: "t\(index)", bodyKey: "b",
                createdAt: clock.now.addingTimeInterval(Double(index) * 60)
            ))
        }

        #expect(try await store.notifications(limit: 2).map(\.titleKey) == ["t2", "t1"])
        #expect(try await store.unreadNotificationCount() == 3)

        try await store.markNotificationsRead(ids: [ids[0], ids[1]], at: clock.now)
        #expect(try await store.unreadNotificationCount() == 1)

        try await store.clearNotifications()
        #expect(try await store.notifications(limit: 10).isEmpty)
    }

    @Test("Garage summaries count each vehicle's own records")
    func summaries() async throws {
        let store = makeStore()
        let a = vehicle("Audi")
        let b = vehicle("VW", model: "Golf", offset: 10)
        try await store.saveVehicle(a)
        try await store.saveVehicle(b)
        try await store.saveFuelEntry(fuelEntry(vehicleID: a.id, km: 1_000, date: clock.now))
        try await store.saveFuelEntry(fuelEntry(vehicleID: a.id, km: 1_500, date: clock.now))
        try await store.appendOdometer(OdometerReading(
            vehicleID: a.id, value: Odometer(kilometers: 1_500), recordedAt: clock.now,
            source: .manual, createdAt: clock.now
        ))
        try await store.saveDocument(DocumentMetadata(
            vehicleID: b.id, name: "Insurance", type: .insurance,
            fileRef: FileRef(relativePath: "docs/ins.pdf"), createdAt: clock.now, updatedAt: clock.now
        ))

        let summaries = try await store.vehicleSummaries()

        #expect(summaries.map(\.displayName) == ["Audi A4", "VW Golf"])
        #expect(summaries[0].fuelEntryCount == 2)
        #expect(summaries[0].currentOdometer?.kilometers == 1_500)
        #expect(summaries[0].documentCount == 0)
        #expect(summaries[1].documentCount == 1)
        #expect(summaries[1].currentOdometer == nil)
    }
}

/// The use cases run unchanged on top of the real store — that is the point of the
/// repository protocols.
@Suite("Use cases on SwiftData")
@MainActor
struct PersistenceIntegrationTests {
    private let clock = FixedClock()

    @Test("Creating a vehicle writes the vehicle, its first odometer reading and its reminders")
    func createVehicle() async throws {
        let dependencies = AppDependencies.persistence(clock: clock)
        let create = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )

        let output = try await create(
            VehicleDraft(brand: "Škoda", model: "Fabia", year: 2021, fuelType: .petrol,
                         initialOdometer: Odometer(kilometers: 82_540)),
            vehicleLimit: nil
        )

        #expect(output.becameDefault)
        let stored = try #require(try await dependencies.vehicles.defaultVehicle())
        #expect(stored.displayName == "Škoda Fabia")
        #expect(try await dependencies.odometer.current(vehicleID: stored.id)?.value.kilometers == 82_540)
    }
}
