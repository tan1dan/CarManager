import Testing
import Foundation
@testable import CarManager

/// End-to-end journeys through the real view models, stores and use cases — what a person
/// does on the screens, minus the taps.
@Suite("User journeys")
@MainActor
struct UserJourneyTests {
    private let clock = FixedClock()

    private func makeApp(premium: Bool = true) async -> (AppModel, AppDependencies) {
        let dependencies = AppDependencies.testing(preferences: InMemoryPreferences(onboardingCompletedVersion: 1), clock: clock) {
            if premium {
                $0.subscriptions = PreviewSubscriptionProvider(entitlement: .premium(now: clock.now), clock: clock)
            }
        }
        let app = AppModel(dependencies: dependencies)
        await app.entitlements.bootstrap()
        await app.vehicles.bootstrap()
        return (app, dependencies)
    }

    private func addVehicle(_ app: AppModel, _ d: AppDependencies, brand: String, model: String, km: String) async throws -> Vehicle {
        let editor = VehicleEditorViewModel(
            mode: .create,
            createVehicle: CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock),
            updateVehicle: UpdateVehicle(vehicles: d.vehicles, clock: clock),
            loadCatalog: LoadVehicleCatalog(catalog: d.vehicleCatalog),
            vehicles: d.vehicles, vehicleStore: app.vehicles, featureGate: app.featureGate,
            router: app.router, clock: clock
        )
        editor.selectBrand(brand)
        editor.selectModel(model)
        editor.mileageText = km
        await editor.save()
        return try #require(editor.state.value)
    }

    private func home(_ app: AppModel, _ d: AppDependencies) async -> HomeViewModel {
        let viewModel = HomeViewModel(
            loadAnalytics: LoadVehicleAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services,
                                                expenses: d.expenses, odometer: d.odometer, clock: clock),
            loadDashboard: LoadHomeDashboard(
                vehicles: d.vehicles, odometer: d.odometer, fuel: d.fuel,
                evaluateReminders: EvaluateReminderTriggers(reminders: d.reminders, odometer: d.odometer, clock: clock),
                evaluateDocuments: EvaluateDocumentExpiries(documents: d.documents, clock: clock),
                insights: d.insights, inbox: d.inbox
            ),
            formatter: HomeFormatter(clock: clock, unitSystem: .metric)
        )
        await viewModel.load(vehicleID: app.selectedVehicleID, userName: "Alex")
        return viewModel
    }

    @Test("Adding a car shows it on Home and as Primary in the Garage")
    func addFirstCar() async throws {
        let (app, d) = await makeApp(premium: false)
        #expect(await home(app, d).state == .empty)

        let audi = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82540")
        #expect(app.selectedVehicleID == audi.id)
        #expect(await home(app, d).state.value?.vehicle.id == audi.id)
        #expect(try await d.vehicles.summaries().first { $0.isDefault }?.id == audi.id)
    }

    @Test("A newly added second car becomes the active one; switching back updates Garage too")
    func secondCarAndSwitching() async throws {
        let (app, d) = await makeApp()
        let audi = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82540")
        let golf = try await addVehicle(app, d, brand: "Volkswagen", model: "Golf", km: "40000")

        #expect(app.selectedVehicleID == golf.id)
        #expect(await home(app, d).state.value?.vehicle.id == golf.id)

        // Home's switcher / Garage's "Make primary".
        await app.vehicles.select(audi.id)
        #expect(await home(app, d).state.value?.vehicle.id == audi.id)
        let summaries = try await d.vehicles.summaries()
        #expect(summaries.filter(\.isDefault).map(\.id) == [audi.id])
    }

    @Test("Records added after the car show on Home and in the vehicle's analytics")
    func recordsReachHome() async throws {
        let (app, d) = await makeApp()
        let audi = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82000")
        let addFuel = AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: clock)
        for (km, liters) in [(82_100.0, 40.0), (82_700.0, 36.0)] {
            _ = try await addFuel(FuelEntryDraft(
                vehicleID: audi.id, date: clock.now, odometer: Odometer(kilometers: km),
                volume: Volume(liters: liters), totalCost: Money(Decimal(liters * 1.8), .eur),
                fuelType: .diesel, station: "BP", isFullTank: true
            ))
        }

        let dashboard = try #require(await home(app, d).state.value)
        #expect(dashboard.latestFuelEntry?.odometer.kilometers == 82_700)
        #expect(dashboard.currentOdometer?.kilometers == 82_700)

        let analytics = try await LoadVehicleAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services,
                                                       expenses: d.expenses, odometer: d.odometer, clock: clock)(vehicleID: audi.id)
        #expect(analytics.averageConsumption.map { abs($0 - 6.0) < 0.01 } == true)   // 36 L / 600 km
        #expect(analytics.fuelEntries.count == 2)
    }

    @Test("A new car's detail screen shows its mileage and the records added to it")
    func newCarDetail() async throws {
        let (app, d) = await makeApp()
        _ = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82540")
        let golf = try await addVehicle(app, d, brand: "Volkswagen", model: "Golf", km: "45000")
        _ = try await AddFuelEntry(fuel: d.fuel, odometer: d.odometer, clock: clock)(FuelEntryDraft(
            vehicleID: golf.id, date: clock.now, odometer: Odometer(kilometers: 45_210),
            volume: Volume(liters: 42), totalCost: Money(Decimal(72.5), .eur), fuelType: .petrol, isFullTank: true
        ))
        _ = try await AddExpense(expenses: d.expenses, odometer: d.odometer, clock: clock)(
            vehicleID: golf.id, title: "Car wash", category: .carWash, cost: Money(15, .eur), date: clock.now
        )

        let detail = VehicleDetailsViewModel(
            loadDetail: LoadVehicleDetail(vehicles: d.vehicles, odometer: d.odometer, fuel: d.fuel,
                                          services: d.services, documents: d.documents),
            loadAnalytics: LoadVehicleAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services,
                                                expenses: d.expenses, odometer: d.odometer, clock: clock),
            deleteVehicle: DeleteVehicle(vehicles: d.vehicles, files: d.files),
            vehicleStore: app.vehicles, router: app.router,
            format: DisplayFormat(locale: Locale(identifier: "en_US"), calendar: clock.calendar)
        )
        await detail.load(vehicleID: golf.id)
        let p = try #require(detail.state.value)
        #expect(p.name.contains("Golf"))
        #expect(p.stats.first?.value.contains("45,210") == true)
        #expect(p.tiles.first { $0.title == "Fuel" }?.subtitle == "1 fill-up")
        let expenses = p.tiles.first { $0.title == "Expenses" }?.subtitle ?? ""
        #expect(expenses.contains("87.5"), "\(expenses)")   // 72.50 + 15
    }

    @Test("A new car takes the currency chosen in Settings")
    func newCarUsesDefaultCurrency() async throws {
        let (app, d) = await makeApp()
        d.preferences.defaultCurrency = CurrencyCode("PLN")
        let editor = VehicleEditorViewModel(
            mode: .create,
            createVehicle: CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock),
            updateVehicle: UpdateVehicle(vehicles: d.vehicles, clock: clock),
            loadCatalog: LoadVehicleCatalog(catalog: d.vehicleCatalog),
            vehicles: d.vehicles, vehicleStore: app.vehicles, featureGate: app.featureGate,
            router: app.router, clock: clock, defaultCurrency: d.preferences.defaultCurrency
        )
        editor.selectBrand("Skoda"); editor.selectModel("Octavia"); editor.mileageText = "1000"
        await editor.save()
        #expect(editor.state.value?.primaryCurrency == CurrencyCode("PLN"))
    }

    @Test("Garage shows every car as the same card, primary first, and Make primary reorders it")
    func garageCards() async throws {
        let (app, d) = await makeApp()
        let audi = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82540")
        let golf = try await addVehicle(app, d, brand: "Volkswagen", model: "Golf", km: "40000")
        let formatter = GarageFormatter(unitSystem: .metric)

        var cards = formatter.makeModel(from: try await d.vehicles.summaries()).cards
        #expect(cards.map(\.id) == [golf.id, audi.id])           // newest added is primary
        #expect(cards.map(\.isPrimary) == [true, false])
        #expect(cards.allSatisfy { $0.stats.count == 3 })       // same full card for everyone

        await app.vehicles.select(audi.id)                      // "Make primary"
        cards = formatter.makeModel(from: try await d.vehicles.summaries()).cards
        #expect(cards.first?.id == audi.id && cards.first?.isPrimary == true)
        #expect(app.selectedVehicleID == audi.id)               // Home follows
    }

    @Test("Pushing the screen that is already on top does not stack a copy")
    func noDuplicatePush() async {
        let (app, _) = await makeApp()
        app.auth.adopt(UserProfile(authProvider: .apple, createdAt: clock.now))   // signed in, like the real app
        app.router.push(.settings, in: .profile)
        app.router.push(.settings, in: .profile)
        #expect(app.router.router(for: .profile).path == [.settings])
        app.router.select(tab: .profile)
        app.router.pop()
        #expect(app.router.router(for: .profile).path.isEmpty)
    }

    @Test("Signing out and back in keeps the garage and Home's car")
    func signOutAndIn() async throws {
        let (app, d) = await makeApp()
        let audi = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82540")
        let profile = UserProfile(displayName: "Alex", authProvider: .apple, createdAt: clock.now)
        app.auth.adopt(profile)

        try await app.auth.signOut()
        #expect(!app.auth.state.isAuthenticated)
        app.router.resetForSignOut()

        // Signing in again (RootView refreshes the store on the transition).
        app.auth.adopt(profile)
        await app.vehicles.refresh()
        #expect(app.selectedVehicleID == audi.id)
        #expect(await home(app, d).state.value?.vehicle.id == audi.id)
    }

    @Test("Deleting the active car moves Home to the remaining one")
    func deleteActiveCar() async throws {
        let (app, d) = await makeApp()
        let audi = try await addVehicle(app, d, brand: "Audi", model: "A4", km: "82540")
        let golf = try await addVehicle(app, d, brand: "Volkswagen", model: "Golf", km: "40000")
        #expect(app.selectedVehicleID == golf.id)

        try await DeleteVehicle(vehicles: d.vehicles, files: d.files)(id: golf.id)
        await app.vehicles.refresh()
        #expect(app.selectedVehicleID == audi.id)
        #expect(await home(app, d).state.value?.vehicle.id == audi.id)
    }
}
