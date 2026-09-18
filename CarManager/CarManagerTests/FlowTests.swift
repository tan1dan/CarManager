import Testing
import Foundation
@testable import CarManager

@Suite("Vehicle flow")
@MainActor
struct VehicleFlowTests {
    private let clock = FixedClock()

    @Test("The first vehicle created becomes the default")
    func firstVehicleBecomesDefault() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )

        let output = try await createVehicle(
            VehicleDraft(brand: "Audi", model: "A4", fuelType: .diesel), vehicleLimit: 1
        )

        #expect(output.becameDefault)
        #expect(try await dependencies.vehicles.defaultVehicle()?.id == output.vehicle.id)
    }

    @Test("A second vehicle does not steal the default flag")
    func secondVehicleIsNotDefault() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )

        let first = try await createVehicle(
            VehicleDraft(brand: "Audi", model: "A4", fuelType: .diesel), vehicleLimit: nil
        )
        let second = try await createVehicle(
            VehicleDraft(brand: "VW", model: "Golf", fuelType: .petrol), vehicleLimit: nil
        )

        #expect(!second.becameDefault)
        #expect(try await dependencies.vehicles.defaultVehicle()?.id == first.vehicle.id)
    }

    @Test("The free-tier limit refuses a second vehicle")
    func freeTierVehicleLimit() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )
        _ = try await createVehicle(
            VehicleDraft(brand: "Audi", model: "A4", fuelType: .diesel), vehicleLimit: 1
        )

        await #expect(throws: DomainError.subscription(.vehicleLimitReached)) {
            try await createVehicle(
                VehicleDraft(brand: "VW", model: "Golf", fuelType: .petrol), vehicleLimit: 1
            )
        }
    }

    @Test("Creating a vehicle writes its initial odometer reading")
    func initialOdometerReading() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )

        let output = try await createVehicle(
            VehicleDraft(
                brand: "Audi", model: "A4", fuelType: .diesel,
                initialOdometer: Odometer(kilometers: 82_540)
            ),
            vehicleLimit: nil
        )

        let current = try await dependencies.odometer.current(vehicleID: output.vehicle.id)
        #expect(current?.value.kilometers == 82_540)
    }

    @Test("Standard reminders are seeded inactive, so we never spam a brand-new car")
    func seededRemindersAreInactive() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )

        let output = try await createVehicle(
            VehicleDraft(brand: "Audi", model: "A4", fuelType: .diesel), vehicleLimit: nil
        )

        let all = try await dependencies.reminders.reminders(vehicleID: output.vehicle.id, activeOnly: false)
        let active = try await dependencies.reminders.reminders(vehicleID: output.vehicle.id, activeOnly: true)
        #expect(!all.isEmpty)
        #expect(active.isEmpty)
    }

    @Test("Validation rejects an empty brand")
    func validationRejectsEmptyBrand() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )

        await #expect(throws: DomainError.validation(.emptyField(.brand))) {
            try await createVehicle(VehicleDraft(brand: "  ", model: "A4", fuelType: .diesel), vehicleLimit: nil)
        }
    }

    @Test("Deleting the default vehicle promotes another one")
    func deletePromotesAnother() async throws {
        let dependencies = makeDependencies(clock: clock)
        let createVehicle = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )
        let first = try await createVehicle(
            VehicleDraft(brand: "Audi", model: "A4", fuelType: .diesel), vehicleLimit: nil
        )
        let second = try await createVehicle(
            VehicleDraft(brand: "VW", model: "Golf", fuelType: .petrol), vehicleLimit: nil
        )

        try await DeleteVehicle(vehicles: dependencies.vehicles, files: dependencies.files)(id: first.vehicle.id)

        #expect(try await dependencies.vehicles.defaultVehicle()?.id == second.vehicle.id)
    }
}

@Suite("Receipt scan flow")
@MainActor
struct ReceiptScanFlowTests {
    private let clock = FixedClock()

    private func makeScanner(_ dependencies: AppDependencies) -> ScanReceipt {
        ScanReceipt(
            vision: dependencies.vision, textRecognizer: dependencies.textRecognizer,
            preprocessor: dependencies.imagePreprocessor, files: dependencies.files,
            scans: dependencies.scans, clock: clock
        )
    }

    private func makeConfirmer(_ dependencies: AppDependencies) -> ConfirmReceiptScan {
        ConfirmReceiptScan(
            addFuel: AddFuelEntry(fuel: dependencies.fuel, odometer: dependencies.odometer, clock: clock),
            addService: AddServiceRecord(
                services: dependencies.services, odometer: dependencies.odometer,
                reminders: dependencies.reminders, clock: clock
            ),
            addExpense: AddExpense(
                expenses: dependencies.expenses, odometer: dependencies.odometer, clock: clock
            ),
            scans: dependencies.scans
        )
    }

    @Test("Scanning stops at review and persists NO financial record")
    func scanNeverPersistsFinancialRecords() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()

        let scan = try await makeScanner(dependencies)(
            imageData: Data("receipt".utf8), vehicleID: vehicleID
        )

        #expect(scan.status == .awaitingReview)
        #expect(try await dependencies.fuel.count(vehicleID: vehicleID) == 0)
        #expect(try await dependencies.services.count(vehicleID: vehicleID) == 0)
        #expect(try await dependencies.expenses.expenses(vehicleID: vehicleID).isEmpty)
    }

    @Test("ConfirmedReceipt cannot be built from an unreviewed draft")
    func confirmedReceiptRequiresReview() async throws {
        let dependencies = makeDependencies(clock: clock)
        let scan = try await makeScanner(dependencies)(
            imageData: Data("receipt".utf8), vehicleID: VehicleID()
        )

        // Nothing accepted yet — the type refuses to construct.
        #expect(ConfirmedReceipt(reviewing: scan, at: clock.now) == nil)
    }

    @Test("Accepting the required fields makes confirmation possible")
    func acceptedFieldsAllowConfirmation() async throws {
        let dependencies = makeDependencies(clock: clock)
        var scan = try await makeScanner(dependencies)(
            imageData: Data("receipt".utf8), vehicleID: VehicleID()
        )
        scan.draft.total.isAccepted = true
        scan.draft.date.isAccepted = true

        #expect(ConfirmedReceipt(reviewing: scan, at: clock.now) != nil)
    }

    @Test("Confirmation writes exactly one record, of exactly one kind")
    func confirmWritesExactlyOneRecord() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()
        var scan = try await makeScanner(dependencies)(
            imageData: Data("receipt".utf8), vehicleID: vehicleID
        )
        scan.draft.total.isAccepted = true
        scan.draft.date.isAccepted = true
        scan.draft.suggestedRecordKind = .expense
        try await dependencies.scans.upsert(scan)

        let confirmed = try #require(ConfirmedReceipt(reviewing: scan, at: clock.now))
        let ref = try await makeConfirmer(dependencies)(confirmed)

        guard case .expense = ref else {
            Issue.record("Expected an expense record, got \(ref)")
            return
        }
        #expect(try await dependencies.expenses.expenses(vehicleID: vehicleID).count == 1)
        // No duplicate transaction in the other tables.
        #expect(try await dependencies.fuel.count(vehicleID: vehicleID) == 0)
        #expect(try await dependencies.services.count(vehicleID: vehicleID) == 0)
    }

    @Test("Confirming twice is idempotent and creates no duplicate")
    func confirmIsIdempotent() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()
        var scan = try await makeScanner(dependencies)(
            imageData: Data("receipt".utf8), vehicleID: vehicleID
        )
        scan.draft.total.isAccepted = true
        scan.draft.date.isAccepted = true
        try await dependencies.scans.upsert(scan)

        let confirmed = try #require(ConfirmedReceipt(reviewing: scan, at: clock.now))
        let confirmer = makeConfirmer(dependencies)
        let first = try await confirmer(confirmed)
        let second = try await confirmer(confirmed)

        #expect(first == second)
        #expect(try await dependencies.expenses.expenses(vehicleID: vehicleID).count == 1)
    }

    @Test("The created record carries its receipt-scan provenance")
    func recordCarriesProvenance() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()
        var scan = try await makeScanner(dependencies)(
            imageData: Data("receipt".utf8), vehicleID: vehicleID
        )
        scan.draft.total.isAccepted = true
        scan.draft.date.isAccepted = true
        try await dependencies.scans.upsert(scan)

        let confirmed = try #require(ConfirmedReceipt(reviewing: scan, at: clock.now))
        _ = try await makeConfirmer(dependencies)(confirmed)

        let expense = try #require(try await dependencies.expenses.expenses(vehicleID: vehicleID).first)
        #expect(expense.source == .receiptScan(scan.id))
    }

    @Test("The view model reaches review and refuses to confirm until reviewed")
    func viewModelGuardsConfirmation() async throws {
        let dependencies = makeDependencies(clock: clock)
        let viewModel = ReceiptScanViewModel(
            vehicleID: VehicleID(),
            scanReceipt: makeScanner(dependencies),
            confirmReceiptScan: makeConfirmer(dependencies),
            clock: clock
        )

        #expect(!viewModel.canConfirm)
        viewModel.acceptedTotal = true
        #expect(!viewModel.canConfirm)
        viewModel.acceptedDate = true
        #expect(viewModel.canConfirm)
    }
}

@Suite("Vision scan flows")
@MainActor
struct VisionScanFlowTests {
    private let clock = FixedClock()

    @Test("A dashboard scan always carries a disclaimer and writes no vehicle record")
    func dashboardScanCarriesDisclaimer() async throws {
        let dependencies = makeDependencies(clock: clock)
        let vehicleID = VehicleID()

        let scan = try await ScanDashboard(
            vision: dependencies.vision, preprocessor: dependencies.imagePreprocessor,
            files: dependencies.files, scans: dependencies.scans, clock: clock
        )(imageData: Data("dash".utf8), vehicleID: vehicleID)

        #expect(scan.disclaimer.kind == .notProfessionalDiagnostics)
        #expect(!scan.findings.isEmpty)
        #expect(try await dependencies.services.count(vehicleID: vehicleID) == 0)
        #expect(try await dependencies.expenses.expenses(vehicleID: vehicleID).isEmpty)
    }

    @Test("Driving safety defaults to unknown, never to 'safe'")
    func drivingSafetyDefaultsToUnknown() async throws {
        let dependencies = makeDependencies(clock: clock)
        let scan = try await ScanDashboard(
            vision: dependencies.vision, preprocessor: dependencies.imagePreprocessor,
            files: dependencies.files, scans: dependencies.scans, clock: clock
        )(imageData: Data("dash".utf8), vehicleID: nil)

        #expect(scan.findings.allSatisfy { $0.drivingSafety != .likelySafe })
    }

    @Test("Damage analysis returns a cost RANGE, never a guaranteed price")
    func damageAnalysisReturnsRange() async throws {
        let dependencies = makeDependencies(clock: clock)
        let analysis = try await AnalyzeDamage(
            vision: dependencies.vision, preprocessor: dependencies.imagePreprocessor,
            files: dependencies.files, scans: dependencies.scans, clock: clock
        )(imagesData: [Data("damage".utf8)], vehicleID: VehicleID())

        #expect(analysis.disclaimer.kind == .costEstimateOnly)
        let estimate = try #require(analysis.findings.first?.estimatedCost)
        #expect(estimate.low.amount < estimate.high.amount)
    }

    @Test("Vision scan state moves capture → processing → result")
    func dashboardViewModelStates() async throws {
        let dependencies = makeDependencies(clock: clock)
        let viewModel = DashboardScanViewModel(
            vehicleID: VehicleID(),
            scanDashboard: ScanDashboard(
                vision: dependencies.vision, preprocessor: dependencies.imagePreprocessor,
                files: dependencies.files, scans: dependencies.scans, clock: clock
            )
        )

        if case .idle = viewModel.state {} else { Issue.record("Expected the initial state to be idle") }

        viewModel.capture()
        // Poll briefly: the stub provider resolves asynchronously.
        for _ in 0..<50 {
            if case .success = viewModel.state { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard case .success = viewModel.state else {
            Issue.record("Expected the scan to reach a result, got \(viewModel.state)")
            return
        }
    }
}

@Suite("Optional VIN")
@MainActor
struct OptionalVINTests {
    private let clock = FixedClock()

    private func makeCreateVehicle(_ dependencies: AppDependencies) -> CreateVehicle {
        CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )
    }

    @Test("A vehicle saves with no VIN at all")
    func savesWithoutVIN() async throws {
        let dependencies = makeDependencies(clock: clock)
        let output = try await makeCreateVehicle(dependencies)(
            VehicleDraft(brand: "Audi", model: "A4", vin: nil, fuelType: .diesel),
            vehicleLimit: nil
        )

        #expect(output.vehicle.vin == nil)
        #expect(output.warnings.isEmpty)
    }

    @Test("Blank and whitespace-only input count as 'not entered'", arguments: ["", "   ", "\n\t"])
    func blankVINIsAbsent(_ raw: String) async throws {
        let dependencies = makeDependencies(clock: clock)
        let output = try await makeCreateVehicle(dependencies)(
            VehicleDraft(brand: "Audi", model: "A4", vin: raw, fuelType: .diesel),
            vehicleLimit: nil
        )

        #expect(output.vehicle.vin == nil)
        #expect(output.warnings.isEmpty)
    }

    @Test("A malformed VIN warns but still saves — an optional field must not cancel the save")
    func malformedVINWarnsAndSaves() async throws {
        let dependencies = makeDependencies(clock: clock)
        let output = try await makeCreateVehicle(dependencies)(
            VehicleDraft(brand: "Audi", model: "A4", vin: "WAUZZ", fuelType: .diesel),
            vehicleLimit: nil
        )

        #expect(output.vehicle.vin == "WAUZZ")
        #expect(output.warnings == [.malformedVIN(length: 5)])
        #expect(try await dependencies.vehicles.count() == 1)
    }

    @Test("A valid 17-character VIN is stored uppercased with no warning")
    func validVINIsNormalised() async throws {
        let dependencies = makeDependencies(clock: clock)
        let output = try await makeCreateVehicle(dependencies)(
            VehicleDraft(brand: "Audi", model: "A4", vin: " wauzzz8k9ba123456 ", fuelType: .diesel),
            vehicleLimit: nil
        )

        #expect(output.vehicle.vin == "WAUZZZ8K9BA123456")
        #expect(output.warnings.isEmpty)
    }

    @Test("The Garage chip shows an em dash when no VIN was entered", arguments: [nil, "", "   "])
    func garageChipShowsDash(_ raw: String?) {
        let summary = VehicleSummary(
            id: VehicleID(), displayName: "Audi A4", year: 2021, fuelType: .diesel,
            vin: raw, isDefault: true, currentOdometer: nil,
            fuelEntryCount: 0, serviceRecordCount: 0, documentCount: 0
        )
        let model = GarageFormatter(unitSystem: .metric).makeModel(from: [summary])
        let vinStat = model.primary?.stats.first { $0.caption == "VIN" }

        // A nil value is what the view renders as "—".
        #expect(vinStat?.value == nil)
    }

    @Test("The Garage chip truncates a full VIN to fit")
    func garageChipTruncates() {
        let summary = VehicleSummary(
            id: VehicleID(), displayName: "Audi A4", year: 2021, fuelType: .diesel,
            vin: "WAUZZZ8K9BA123456", isDefault: true, currentOdometer: nil,
            fuelEntryCount: 0, serviceRecordCount: 0, documentCount: 0
        )
        let model = GarageFormatter(unitSystem: .metric).makeModel(from: [summary])

        #expect(model.primary?.stats.first { $0.caption == "VIN" }?.value == "WAUZZ…")
    }
}

@Suite("Profile")
@MainActor
struct ProfileTests {
    private let clock = FixedClock()
    private let formatter = ProfileFormatter(languageName: "English")

    private func profile(name: String?, email: String?) -> AuthState {
        .authenticated(UserProfile(
            displayName: name, email: email, authProvider: .email, createdAt: FixedClock().now
        ))
    }

    @Test("A Settings row exists and points at the Settings route")
    func settingsRowNavigates() {
        let model = formatter.makeModel(
            authState: .anonymous, entitlement: .free, isPremium: false, statistics: .empty
        )
        let row = model.rows.first { $0.id == "settings" }

        #expect(row != nil)
        #expect(row?.destination == .settings)
        #expect(row?.trailing == .chevron)
    }

    @Test("Every navigable Profile row is reachable through the guard")
    func rowsAreReachable() {
        let model = formatter.makeModel(
            authState: .anonymous, entitlement: .free, isPremium: false, statistics: .empty
        )
        for route in model.rows.compactMap(\.destination) {
            #expect(
                RouteGuard().evaluate(.tab(.profile, path: [route]), context: .make()) == .allow,
                "\(route) should be reachable"
            )
        }
    }

    @Test("The identity card shows initials, name and email when signed in")
    func signedInIdentity() {
        let model = formatter.makeModel(
            authState: profile(name: "Alex Lindström", email: "alex@carassistant.app"),
            entitlement: .premium(now: clock.now), isPremium: true, statistics: .empty
        )

        #expect(model.identity.name == "Alex Lindström")
        #expect(model.identity.subtitle == "alex@carassistant.app")
        #expect(model.identity.initials == "AL")
        #expect(model.identity.isPremium)
        #expect(model.identity.badgeTitle == "PREMIUM")
    }

    @Test("An anonymous user gets a sign-in prompt and the free badge")
    func anonymousIdentity() {
        let model = formatter.makeModel(
            authState: .anonymous, entitlement: .free, isPremium: false, statistics: .empty
        )

        #expect(model.identity.name == "Not signed in")
        #expect(!model.identity.isPremium)
        #expect(model.identity.badgeTitle == "FREE")
    }

    @Test("Initials fall back to the email when no display name exists")
    func initialsFromEmail() {
        let model = formatter.makeModel(
            authState: profile(name: nil, email: "alex@carassistant.app"),
            entitlement: .free, isPremium: false, statistics: .empty
        )

        #expect(model.identity.name == "alex@carassistant.app")
        #expect(model.identity.initials == "A")
    }

    @Test("The stat labels are singular for one vehicle and plural otherwise", arguments: [
        (1, "Vehicle"), (0, "Vehicles"), (3, "Vehicles")
    ])
    func vehicleLabelPluralisation(_ input: (count: Int, label: String)) {
        let model = formatter.makeModel(
            authState: .anonymous, entitlement: .free, isPremium: false,
            statistics: UserStatistics(
                vehicleCount: input.count, fuelEntryCount: 0, serviceRecordCount: 0
            )
        )

        #expect(model.stats.first?.value == "\(input.count)")
        #expect(model.stats.first?.label == input.label)
    }

    @Test("The premium banner invites an upgrade for free users and confirms it for subscribers")
    func premiumBannerCopy() {
        let free = formatter.makeModel(
            authState: .anonymous, entitlement: .free, isPremium: false, statistics: .empty
        )
        let premium = formatter.makeModel(
            authState: .anonymous, entitlement: .premium(now: clock.now),
            isPremium: true, statistics: .empty
        )

        #expect(free.premium?.eyebrow == "GO PREMIUM")
        #expect(premium.premium?.eyebrow == "PREMIUM")
    }

    @Test("Statistics aggregate the per-vehicle counts")
    func statisticsAggregate() async throws {
        let dependencies = makeDependencies(clock: clock)
        let create = CreateVehicle(
            vehicles: dependencies.vehicles, odometer: dependencies.odometer,
            reminders: dependencies.reminders, clock: clock
        )
        let audi = try await create(
            VehicleDraft(brand: "Audi", model: "A4", fuelType: .diesel), vehicleLimit: nil
        )
        _ = try await create(
            VehicleDraft(brand: "VW", model: "Golf", fuelType: .petrol), vehicleLimit: nil
        )
        _ = try await AddFuelEntry(
            fuel: dependencies.fuel, odometer: dependencies.odometer, clock: clock
        )(FuelEntryDraft(
            vehicleID: audi.vehicle.id, date: clock.now, odometer: Odometer(kilometers: 100),
            volume: Volume(liters: 40), totalCost: Money(60, .eur), fuelType: .diesel
        ))

        let statistics = try await LoadUserStatistics(vehicles: dependencies.vehicles)()

        #expect(statistics.vehicleCount == 2)
        #expect(statistics.fuelEntryCount == 1)
        #expect(statistics.serviceRecordCount == 0)
    }
}

@Suite("Settings")
@MainActor
struct SettingsScreenTests {
    private let clock = FixedClock()

    private var formatter: SettingsFormatter {
        SettingsFormatter(
            locale: Locale(identifier: "en_SE"),
            timeZone: TimeZone(identifier: "Europe/Stockholm")!,
            appVersion: "1.0.0"
        )
    }

    private func model(auth: AuthState = .anonymous, units: UnitSystem = .metric) -> SettingsPresentationModel {
        formatter.makeModel(authState: auth, unitSystem: units, telemetryEnabled: false)
    }

    @Test("The four designed sections are present in order")
    func sectionOrder() {
        #expect(model().sections.map(\.title) == ["ACCOUNT", "PREFERENCES", "DATA", "ABOUT"])
    }

    @Test("Every designed row is present", arguments: [
        "email", "password", "payment", "units", "region", "timezone",
        "notifications", "icloud", "export", "telemetry", "version", "support"
    ])
    func rowsPresent(_ id: String) {
        let ids = model().sections.flatMap(\.rows).map(\.id)
        #expect(ids.contains(id))
    }

    @Test("Payment method links out to App Store billing and never shows card data")
    func paymentMethodNeverShowsCard() {
        let row = model().sections
            .flatMap(\.rows)
            .first { $0.id == "payment" }

        #expect(row?.action == .openURL(SettingsFormatter.appStoreBillingURL))
        // The design shows "Visa ·· 4832"; the app holds no card data, so the row must not
        // render a value at all.
        #expect(row?.trailing == .chevron)
    }

    @Test("The email row reflects the session")
    func emailReflectsSession() {
        #expect(
            model().sections.flatMap(\.rows).first { $0.id == "email" }?.trailing
                == .value("Not signed in")
        )

        let signedIn = model(auth: .authenticated(UserProfile(
            email: "alex@carassistant.app", authProvider: .email, createdAt: clock.now
        )))
        #expect(
            signedIn.sections.flatMap(\.rows).first { $0.id == "email" }?.trailing
                == .value("alex@…")
        )
    }

    @Test("Units reflects the stored preference", arguments: [
        (UnitSystem.metric, "Metric"), (.imperial, "Imperial")
    ])
    func unitsReflectPreference(_ input: (system: UnitSystem, label: String)) {
        let row = model(units: input.system).sections.flatMap(\.rows).first { $0.id == "units" }
        #expect(row?.trailing == .value(input.label))
    }

    @Test("Region and time zone are read from the device, not stored by the app")
    func localeValuesAreRead() {
        let rows = model().sections.flatMap(\.rows)
        #expect(rows.first { $0.id == "region" }?.trailing == .value("Sweden"))
        #expect(rows.first { $0.id == "timezone" }?.action == SettingsPresentationModel.Action.inert)
    }

    @Test("The three boolean preferences are switches", arguments: [
        ("notifications", SettingsPresentationModel.ToggleKind.notifications),
        ("icloud", .iCloudSync),
        ("telemetry", .telemetry)
    ])
    func togglesAreSwitches(_ input: (id: String, kind: SettingsPresentationModel.ToggleKind)) {
        let row = model().sections.flatMap(\.rows).first { $0.id == input.id }
        #expect(row?.trailing == .toggle(input.kind))
    }

    @Test("PDF export is its own action so it can be premium-gated before a file is produced")
    func exportIsGatedAction() {
        let row = model().sections.flatMap(\.rows).first { $0.id == "export" }
        #expect(row?.action == .exportPDF)
        #expect(FeatureGating.evaluate(
            .pdfExport, entitlement: .free, usage: .available(now: clock.now),
            vehicleCount: 1, now: clock.now
        ) == .locked(.requiresPremium))
    }

    @Test("Every pushed Settings destination is reachable through the guard")
    func pushedRowsAreReachable() {
        let routes = model().sections.flatMap(\.rows).compactMap { row -> AppRoute? in
            if case .push(let route) = row.action { return route }
            return nil
        }
        #expect(!routes.isEmpty)
        for route in routes {
            #expect(
                RouteGuard().evaluate(.tab(.profile, path: [route]), context: .make()) == .allow,
                "\(route) should be reachable"
            )
        }
    }

    @Test("The share-export sheet needs no entitlement of its own")
    func shareExportIsUngated() {
        let url = URL(fileURLWithPath: "/tmp/export.pdf")
        #expect(RouteGuard().evaluate(.modal(.shareExport(url)), context: .make()) == .allow)
    }
}

@Suite("Paywall")
@MainActor
struct PaywallTests {
    private let formatter = PaywallFormatter()

    private func products(eligible: Bool = true) -> [SubscriptionProduct] {
        [
            SubscriptionProduct(
                id: .monthly, displayName: "Premium Monthly", displayPrice: "€4.99",
                isEligibleForIntroOffer: eligible,
                introOfferDescription: eligible ? "7-day free trial" : nil
            ),
            SubscriptionProduct(
                id: .yearly, displayName: "Premium Yearly", displayPrice: "€39.00",
                isEligibleForIntroOffer: eligible,
                introOfferDescription: eligible ? "7-day free trial" : nil
            )
        ]
    }

    @Test("Both plans are offered, with the yearly one promoted")
    func plansAndPromotion() {
        let model = formatter.makeModel(products: products(), selected: .yearly)

        #expect(model.plans.map(\.id) == [.monthly, .yearly])
        #expect(model.plans.first { $0.id == .yearly }?.isPromoted == true)
        #expect(model.plans.first { $0.id == .monthly }?.isPromoted == false)
    }

    @Test("Prices come from StoreKit's localised strings, never hard-coded")
    func pricesComeFromStoreKit() {
        let model = formatter.makeModel(products: products(), selected: .yearly)

        #expect(model.plans.first { $0.id == .monthly }?.price == "€4.99")
        #expect(model.plans.first { $0.id == .yearly }?.price == "€39.00")
    }

    @Test("A trial is only promised when the account is eligible")
    func trialOnlyWhenEligible() {
        let eligible = formatter.makeModel(products: products(eligible: true), selected: .yearly)
        #expect(eligible.callToAction == "Start 7-day free trial")

        let notEligible = formatter.makeModel(products: products(eligible: false), selected: .yearly)
        #expect(notEligible.callToAction == "Subscribe")
    }

    @Test("The benefit list matches what the gating matrix actually unlocks")
    func benefitsMatchGating() {
        // iCloud sync is free in this app, so the paywall must not claim it.
        #expect(!PaywallFormatter.benefits.contains { $0.localizedCaseInsensitiveContains("icloud") })
        #expect(PaywallFormatter.benefits.contains("Unlimited vehicles"))
        #expect(PaywallFormatter.benefits.contains("PDF export of history"))
    }

    @Test("Selecting a plan changes the call to action target")
    func selectionDrivesModel() async {
        let clock = FixedClock()
        let store = EntitlementStore(
            subscriptions: StubSubscriptionProvider(clock: clock), clock: clock
        )
        let viewModel = PaywallViewModel(
            context: .settingsUpgrade, entitlements: store,
            router: makeRouter(context: .make())
        )
        await viewModel.load()

        #expect(viewModel.selectedProduct == .yearly)
        viewModel.select(.monthly)
        #expect(viewModel.selectedProduct == .monthly)
    }

    @Test("Restoring with nothing to restore reports it without an error")
    func restoreNothingIsNeutral() async {
        let clock = FixedClock()
        let store = EntitlementStore(
            subscriptions: StubSubscriptionProvider(clock: clock), clock: clock
        )
        let viewModel = PaywallViewModel(
            context: .settingsUpgrade, entitlements: store,
            router: makeRouter(context: .make())
        )

        await viewModel.restore()
        #expect(viewModel.message == "Nothing to restore")
    }

    @Test("A successful purchase dismisses the paywall and replays the blocked destination")
    func purchaseReplaysDestination() async {
        let clock = FixedClock()
        let store = EntitlementStore(
            subscriptions: StubSubscriptionProvider(clock: clock), clock: clock
        )
        // The router must read LIVE entitlement state: replaying a destination re-runs the
        // guard, so a stale snapshot would block the very screen the purchase unlocked.
        let router = AppRouter { [store] in
            .make(entitlement: store.entitlement, hasVehicle: true)
        }
        // What RouteGuard does when a free user reaches a premium screen.
        router.navigate(to: .fullScreen(.camera(.receipt)))
        #expect(router.pendingDestination != nil)

        let viewModel = PaywallViewModel(
            context: .feature(.receiptScan), entitlements: store, router: router
        )
        await viewModel.load()
        await viewModel.purchaseSelected()

        #expect(store.isPremium)
        #expect(router.pendingDestination == nil)
        #expect(router.fullScreen == .camera(.receipt))
    }
}

@Suite("AI hub")
struct AIHubTests {
    private let clock = FixedClock()
    private var formatter: AIHubFormatter {
        AIHubFormatter(now: clock.now, calendar: clock.calendar, locale: Locale(identifier: "en_US"))
    }

    private func summary(_ title: String, daysAgo: Double) -> ConversationSummary {
        ConversationSummary(
            id: ConversationID(), title: title,
            updatedAt: clock.now.addingTimeInterval(-daysAgo * 86_400), messageCount: 2
        )
    }

    @Test("Chat dates read as Today, Yesterday, a short date, then a dated year")
    func relativeDays() throws {
        let lastYear = try #require(clock.calendar.date(byAdding: .year, value: -1, to: clock.now))

        #expect(formatter.relativeDay(clock.now) == "Today")
        #expect(formatter.relativeDay(clock.now.addingTimeInterval(-86_400)) == "Yesterday")
        #expect(formatter.relativeDay(clock.now.addingTimeInterval(-10 * 86_400)) == "Sep 29")
        #expect(formatter.relativeDay(lastYear).hasSuffix(", 2024"))
    }

    @Test("Recent chats are capped, and 'See all' appears only when some are hidden")
    func recentChatsCap() {
        let four = (0..<4).map { summary("Chat \($0)", daysAgo: Double($0)) }

        let capped = formatter.makeModel(summaries: four, isLocked: { _ in false })
        guard case .loaded(let rows) = capped.recentChats else {
            Issue.record("expected loaded chats"); return
        }
        #expect(rows.map(\.title) == ["Chat 0", "Chat 1", "Chat 2"])
        #expect(capped.showsAllChatsLink)

        let fits = formatter.makeModel(summaries: Array(four.prefix(3)), isLocked: { _ in false })
        #expect(!fits.showsAllChatsLink)
    }

    @Test("No conversations is an empty state, not an empty list")
    func emptyState() {
        let model = formatter.makeModel(summaries: [], isLocked: { _ in false })
        #expect(model.recentChats == .empty)
        #expect(!model.showsAllChatsLink)
    }

    @Test("Tool lock state mirrors the free-tier gating matrix")
    func toolLocks() {
        let now = clock.now
        let model = formatter.makeModel(summaries: []) { feature in
            !FeatureGating.evaluate(
                feature, entitlement: .free, usage: .available(now: now),
                vehicleCount: 1, now: now
            ).isAllowed
        }
        let locked = Dictionary(uniqueKeysWithValues: model.tools.map { ($0.kind, $0.isLocked) })

        // Scans are premium; chat has a free quota, so it must not look locked.
        #expect(locked == [.dashboard: true, .receipt: true, .damage: true, .chat: false])
    }

    @Test("Every tool maps to the premium feature its destination is gated on")
    func toolFeatures() {
        #expect(AIHubPresentationModel.Tool.Kind.allCases.map(\.feature)
            == [.dashboardScan, .receiptScan, .damageAnalysis, .aiChat])
    }
}
