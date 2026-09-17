import Testing
import Foundation
@testable import CarManager

@Suite("Add flow")
@MainActor
struct AddFlowTests {
    private let clock = FixedClock()

    @Test("Every quick-log action maps to a real destination", arguments: [
        ModalRoute.fuelEditor(.create(VehicleID())),
        .serviceEditor(.create(VehicleID())),
        .expenseEditor(.create(VehicleID())),
        .reminderEditor(.create(VehicleID())),
        .documentEditor(nil)
    ])
    func quickLogModals(_ route: ModalRoute) {
        let router = makeRouter(context: .make())
        router.present(.quickLog)
        router.replaceModal(with: route)

        #expect(router.activeModal == route)
    }

    @Test("Adding fuel writes a linked odometer reading and no expense row")
    func addFuelWritesOdometer() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()

        let output = try await AddFuelEntry(
            fuel: dependencies.fuel, odometer: dependencies.odometer, clock: clock
        )(FuelEntryDraft(
            vehicleID: vehicleID, date: clock.now,
            odometer: Odometer(kilometers: 82_540), volume: Volume(liters: 48),
            totalCost: Money(84.20, .eur), fuelType: .diesel, isFullTank: true
        ))

        #expect(output.entry.volume.liters == 48)
        #expect(try await dependencies.odometer.current(vehicleID: vehicleID)?.value.kilometers == 82_540)
        // Fuel is NOT duplicated as an expense row.
        #expect(try await dependencies.expenses.expenses(vehicleID: vehicleID).isEmpty)
    }

    @Test("A zero-volume fill-up is rejected")
    func rejectsZeroVolume() async throws {
        let dependencies = makeDependencies(clock: clock)

        await #expect(throws: DomainError.validation(.nonPositiveVolume)) {
            try await AddFuelEntry(
                fuel: dependencies.fuel, odometer: dependencies.odometer, clock: clock
            )(FuelEntryDraft(
                vehicleID: VehicleID(), date: clock.now,
                odometer: Odometer(kilometers: 100), volume: Volume(liters: 0),
                totalCost: Money(10, .eur), fuelType: .petrol
            ))
        }
    }

    @Test("An odometer that goes backwards is a warning, not a refusal")
    func odometerRegressionWarns() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()
        let addFuel = AddFuelEntry(fuel: dependencies.fuel, odometer: dependencies.odometer, clock: clock)

        _ = try await addFuel(FuelEntryDraft(
            vehicleID: vehicleID, date: clock.now, odometer: Odometer(kilometers: 1000),
            volume: Volume(liters: 40), totalCost: Money(60, .eur), fuelType: .petrol
        ))
        let second = try await addFuel(FuelEntryDraft(
            vehicleID: vehicleID, date: clock.now, odometer: Odometer(kilometers: 500),
            volume: Volume(liters: 40), totalCost: Money(60, .eur), fuelType: .petrol
        ))

        #expect(second.warnings.contains { if case .odometerRegression = $0 { return true }; return false })
        #expect(try await dependencies.fuel.count(vehicleID: vehicleID) == 2)
    }

    @Test("A service record with several items auto-completes every matching reminder")
    func serviceCompletesMatchingReminders() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()

        let oilChange = Reminder(
            vehicleID: vehicleID, title: "Oil change", kind: .oilChange,
            trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(86_400))),
            createdAt: clock.now, updatedAt: clock.now
        )
        let filters = Reminder(
            vehicleID: vehicleID, title: "Filters", kind: .filterReplacement,
            trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(86_400))),
            createdAt: clock.now, updatedAt: clock.now
        )
        let brakes = Reminder(
            vehicleID: vehicleID, title: "Brakes", kind: .brakePads,
            trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(86_400))),
            createdAt: clock.now, updatedAt: clock.now
        )
        for reminder in [oilChange, filters, brakes] {
            try await dependencies.reminders.insert(reminder)
        }

        let output = try await AddServiceRecord(
            services: dependencies.services, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )(
            vehicleID: vehicleID, date: clock.now, odometerValue: Odometer(kilometers: 82_120),
            items: [
                ServiceItem(type: .oilChange, name: "Oil change"),
                ServiceItem(type: .filters, name: "Air filter")
            ],
            workshop: "AutoService", totalCost: Money(210, .eur)
        )

        // Both matching reminders complete; the unrelated brake reminder does not.
        #expect(Set(output.completedReminderIDs) == Set([oilChange.id, filters.id]))
    }

    @Test("A service record needs at least one item")
    func serviceRequiresItems() async throws {
        let dependencies = makeDependencies(clock: clock)

        await #expect(throws: DomainError.validation(.noServiceItems)) {
            try await AddServiceRecord(
                services: dependencies.services, odometer: dependencies.odometer,
                reminders: dependencies.reminders, clock: clock
            )(
                vehicleID: VehicleID(), date: clock.now, odometerValue: nil,
                items: [], workshop: nil, totalCost: Money(10, .eur)
            )
        }
    }

    @Test("Creating a reminder schedules a notification through the port")
    func reminderSchedulesNotification() async throws {
        let spy = SpyNotificationScheduler()
        let dependencies = AppDependencies.testing(
            preferences: InMemoryPreferences(onboardingCompletedVersion: 1), clock: clock
        ) { $0.notifications = spy }

        _ = try await CreateReminder(
            reminders: dependencies.reminders, notifications: spy, clock: clock
        )(
            vehicleID: VehicleID(), title: "Insurance", kind: .insurance,
            trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(60 * 86_400))),
            recurrence: .everyMonths(12)
        )

        let scheduled = await spy.scheduled
        #expect(scheduled.count == 1)
        #expect(scheduled.first?.identifier.hasPrefix("reminder.") == true)
    }

    @Test("Denied notification permission is a warning, not a failure")
    func deniedPermissionIsWarning() async throws {
        let spy = SpyNotificationScheduler(status: .denied)
        let dependencies = makeDependencies(clock: clock)

        let output = try await CreateReminder(
            reminders: dependencies.reminders, notifications: spy, clock: clock
        )(
            vehicleID: VehicleID(), title: "Insurance", kind: .insurance,
            trigger: .date(DateTrigger(dueDate: clock.now.addingTimeInterval(86_400))),
            recurrence: .none
        )

        #expect(output.warnings.contains(.notificationsNotAuthorized))
        #expect(output.reminder.title == "Insurance")
    }

    @Test("Adding a document rejects an expiry that precedes its start date")
    func documentValidatesDates() async throws {
        let dependencies = makeDependencies(clock: clock)

        await #expect(throws: DomainError.validation(.expirationBeforeStart)) {
            try await AddDocument(
                documents: dependencies.documents, files: dependencies.files, clock: clock
            )(
                vehicleID: nil, name: "Insurance", type: .insurance,
                startDate: clock.now, expirationDate: clock.now.addingTimeInterval(-86_400),
                fileData: Data("pdf".utf8)
            )
        }
    }
}

@Suite("AI navigation and chat")
@MainActor
struct AINavigationTests {
    private let clock = FixedClock()

    @Test("Every AI hub action maps to a destination")
    func aiHubDestinations() {
        let premium = RouteGuard.Context.make(
            auth: .authenticated(UserProfile(authProvider: .email, createdAt: clock.now)),
            entitlement: .premium(now: clock.now),
            disclaimers: [AIDisclaimer.dashboard.version, AIDisclaimer.damage.version]
        )
        let guardEvaluator = RouteGuard()

        #expect(guardEvaluator.evaluate(.tab(.ai, path: [.aiChat(nil)]), context: premium) == .allow)
        #expect(guardEvaluator.evaluate(.fullScreen(.camera(.dashboard)), context: premium) == .allow)
        #expect(guardEvaluator.evaluate(.fullScreen(.camera(.receipt)), context: premium) == .allow)
        #expect(guardEvaluator.evaluate(.fullScreen(.camera(.damage)), context: premium) == .allow)
        #expect(guardEvaluator.evaluate(
            .tab(.ai, path: [.conversationHistory]), context: premium) == .allow)
    }

    @Test("Asking the AI persists the user message before the response arrives")
    func askAIPersistsUserMessageFirst() async throws {
        let dependencies = makeDependencies(clock: clock)
        let askAI = AskAI(
            conversations: dependencies.conversations,
            provider: dependencies.ai,
            buildContext: BuildAIContext(
                vehicles: dependencies.vehicles, odometer: dependencies.odometer,
                fuel: dependencies.fuel, services: dependencies.services,
                expenses: dependencies.expenses, clock: clock
            ),
            clock: clock
        )

        var conversationID: ConversationID?
        var sawUserMessage = false
        var deltas: [String] = []
        var completed: AIMessage?

        for try await event in askAI(.init(conversationID: nil, vehicleID: nil, text: "Why is my consumption up?")) {
            switch event {
            case .conversationCreated(let id): conversationID = id
            case .userMessageSaved: sawUserMessage = true
            case .delta(let chunk): deltas.append(chunk)
            case .assistantCompleted(let message): completed = message
            }
        }

        #expect(sawUserMessage)
        #expect(!deltas.isEmpty)
        let assistant = try #require(completed)
        #expect(!assistant.isPartial)

        let stored = try await dependencies.conversations.conversation(id: try #require(conversationID))
        // Exactly two persisted messages per turn — deltas are never written one by one.
        #expect(stored?.messages.count == 2)
        #expect(stored?.messages.first?.role == .user)
        #expect(stored?.messages.last?.role == .assistant)
    }

    @Test("The AI context is bounded and never carries VIN, plate or notes")
    func aiContextIsRedacted() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )
        let output = try await createVehicle(
            VehicleDraft(
                brand: "Audi", model: "A4", year: 2021, fuelType: .diesel,
                initialOdometer: Odometer(kilometers: 82_540)
            ),
            vehicleLimit: nil
        )

        let context = try await BuildAIContext(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            fuel: dependencies.fuel, services: dependencies.services,
            expenses: dependencies.expenses, clock: clock
        )(vehicleID: output.vehicle.id)

        #expect(context.vehicle.brand == "Audi")
        #expect(context.vehicle.currentOdometerKm == 82_540)
        // Coverage tells the model how little data exists, so it can decline rather than invent.
        #expect(context.coverage.fuelEntryCount == 0)
        #expect(!context.coverage.hasSufficientDataForConsumption)

        // Redaction is structural: the encoded context contains no VIN or plate field at all.
        let mirror = Mirror(reflecting: context.vehicle)
        let fields = mirror.children.compactMap(\.label)
        #expect(!fields.contains("vin"))
        #expect(!fields.contains("licensePlate"))
    }
}

@Suite("Settings and premium navigation")
@MainActor
struct SettingsNavigationTests {

    @Test("Every settings destination is reachable", arguments: [
        AppRoute.manageVehicles, .defaultVehicle, .subscriptionSettings,
        .supportSettings, .legalSettings, .about
    ])
    func settingsDestinations(_ route: AppRoute) {
        #expect(RouteGuard().evaluate(
            .tab(.profile, path: [.settings, route]), context: .make()) == .allow)
    }

    @Test("Every settings section is reachable", arguments: SettingsSection.allCases)
    func settingsSections(_ section: SettingsSection) {
        #expect(RouteGuard().evaluate(
            .tab(.profile, path: [.settings, .settingsSection(section)]), context: .make()) == .allow)
    }

    @Test("The paywall is reachable from settings without a subscription")
    func paywallFromSettings() {
        let router = makeRouter(context: .make(entitlement: .free))
        router.present(.paywall(.settingsUpgrade))

        #expect(router.activeModal == .paywall(.settingsUpgrade))
    }

    @Test("Legal documents open as sheets from the paywall")
    func legalFromPaywall() {
        let router = makeRouter(context: .make())
        router.present(.paywall(.settingsUpgrade))
        router.present(.legal(.termsOfUse))

        #expect(router.activeModal == .legal(.termsOfUse))
        router.dismissModal()
        #expect(router.activeModal == .paywall(.settingsUpgrade))
    }

    @Test("Purchasing updates the entitlement store and unlocks gated features")
    func purchaseUnlocksFeatures() async throws {
        let clock = FixedClock()
        let subscriptions = StubSubscriptionProvider(clock: clock)
        let store = EntitlementStore(subscriptions: subscriptions, clock: clock)

        await store.bootstrap()
        #expect(!store.isPremium)

        let outcome = try await store.purchase(.yearly)
        guard case .success = outcome else {
            Issue.record("Expected the purchase to succeed, got \(outcome)")
            return
        }
        #expect(store.isPremium)
    }

    @Test("Restore with no purchase is a neutral outcome, not an error")
    func restoreNothingToRestore() async throws {
        let clock = FixedClock()
        let store = EntitlementStore(
            subscriptions: StubSubscriptionProvider(clock: clock), clock: clock
        )

        let outcome = try await store.restore()
        #expect(outcome == .nothingToRestore)
    }
}
