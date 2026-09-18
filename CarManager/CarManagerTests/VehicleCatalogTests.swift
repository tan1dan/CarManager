import Testing
import Foundation
@testable import CarManager

@Suite("Vehicle catalog")
struct VehicleCatalogTests {
    private let brands = [
        VehicleCatalog.Brand(name: "Škoda", popular: true, aliases: ["Шкода"], models: [
            .init(name: "Octavia", from: 1996), .init(name: "Octavia RS", from: 2001),
            .init(name: "Superb", from: 2001), .init(name: "Fabia", from: 1999, to: 2025)
        ]),
        VehicleCatalog.Brand(name: "Volkswagen", popular: true, aliases: ["VW"], models: [
            .init(name: "ID.3", from: 2019), .init(name: "Golf", from: 1974)
        ]),
        VehicleCatalog.Brand(name: "Ford", models: [.init(name: "Focus", from: 1998)]),
        VehicleCatalog.Brand(name: "Mercedes-Benz", models: [.init(name: "C-Class", from: 1982)])
    ]

    @Test("Search ignores case, accents and punctuation", arguments: [
        ("skoda", "Škoda"), ("ŠKODA", "Škoda"), ("vw", "Volkswagen"), ("Шкода", "Škoda"),
        ("Форд", "Ford"), ("mercedes benz", "Mercedes-Benz")
    ])
    func brandSearch(query: String, expected: String) {
        let result = CatalogSearch.filter(brands, query: query, names: \.searchNames)
        #expect(result.first?.name == expected)
    }

    @Test("Model search tolerates missing punctuation and ranks prefixes first")
    func modelSearch() {
        let skoda = brands[0].models
        #expect(CatalogSearch.filter(brands[1].models, query: "id3", name: \.name).map(\.name) == ["ID.3"])
        #expect(CatalogSearch.filter(brands[3].models, query: "c class", name: \.name).map(\.name) == ["C-Class"])
        // "rs" is inside "Octavia RS" but starts nothing, so it is found — just ranked after prefixes.
        #expect(CatalogSearch.filter(skoda, query: "octavia", name: \.name).map(\.name) == ["Octavia", "Octavia RS"])
        #expect(CatalogSearch.filter(skoda, query: "rs", name: \.name).map(\.name) == ["Octavia RS"])
    }

    @Test("A name the catalog lacks is offered as a custom entry; a known one is not")
    func customEntry() {
        let names = brands.flatMap(\.searchNames)
        #expect(CatalogSearch.isNew("Syrena", among: names))
        #expect(!CatalogSearch.isNew("skoda", among: names))
        #expect(!CatalogSearch.isNew("VW", among: names))
        #expect(!CatalogSearch.isNew("   ", among: names))
    }

    @Test("Production years are newest first and never run past next year")
    func productionYears() {
        let fabia = VehicleCatalog.Model(name: "Fabia", from: 2020, to: 2022)
        #expect(fabia.productionYears(currentYear: 2026) == [2022, 2021, 2020])

        let current = VehicleCatalog.Model(name: "Octavia", from: 2024)
        #expect(current.productionYears(currentYear: 2026) == [2027, 2026, 2025, 2024])

        #expect(VehicleCatalog.Model(name: "Unknown").productionYears(currentYear: 2026) == nil)
    }

    @Test("Mileage accepts whatever separator the user's locale shows", arguments: [
        ("82,540", 82_540.0), ("82 540", 82_540.0), ("82.540", 82_540.0), ("82540", 82_540.0)
    ])
    func mileageParsing(text: String, expected: Double) {
        #expect(VehicleEditorFormatter.kilometers(from: text) == expected)
    }

    @Test("Blank mileage is 'not entered', not zero")
    func blankMileage() {
        #expect(VehicleEditorFormatter.kilometers(from: "") == nil)
    }

    @Test("The bundled catalog loads and has the brands the pickers pin")
    func bundledCatalog() async throws {
        let catalog = try await BundledVehicleCatalog().catalog()

        #expect(catalog.brands.count > 100)
        #expect(catalog.source.license == "ODbL-1.0")
        #expect(catalog.brands.filter(\.popular).count == 12)
        let skoda = try #require(catalog.brand(named: "skoda"))
        // The build script strips the source's "Skoda " prefix from model names.
        #expect(skoda.model(named: "Octavia") != nil)
        #expect(!skoda.models.contains { $0.name.hasPrefix("Skoda") })
    }

    @Test("A missing catalog file fails loudly rather than returning an empty list")
    func missingCatalog() async {
        await #expect(throws: DomainError.self) {
            try await BundledVehicleCatalog(resource: "DoesNotExist").catalog()
        }
    }
}

@Suite("Vehicle editor")
@MainActor
struct VehicleEditorTests {
    private let clock = FixedClock()

    private func makeViewModel() async -> (VehicleEditorViewModel, AppDependencies) {
        var dependencies = makeDependencies(clock: clock)
        dependencies.vehicleCatalog = StaticVehicleCatalog(value: VehicleCatalog(
            source: .init(name: "test", url: "https://example.com", upstream: "test", license: "ODbL-1.0"),
            brands: [
                .init(name: "Audi", models: [.init(name: "A4", from: 1994, to: 2025)]),
                .init(name: "BMW", models: [.init(name: "3 Series", from: 1975)])
            ]
        ))
        let app = AppModel(dependencies: dependencies)
        let viewModel = VehicleEditorViewModel(
            mode: .create,
            createVehicle: CreateVehicle(
                vehicles: dependencies.vehicles, odometer: dependencies.odometer,
                reminders: dependencies.reminders, clock: clock
            ),
            updateVehicle: UpdateVehicle(vehicles: dependencies.vehicles, clock: clock),
            loadCatalog: LoadVehicleCatalog(catalog: dependencies.vehicleCatalog),
            vehicles: dependencies.vehicles,
            vehicleStore: app.vehicles,
            featureGate: app.featureGate,
            router: app.router,
            clock: clock
        )
        await viewModel.prepare()
        return (viewModel, dependencies)
    }

    @Test("Choosing a different brand clears the model; re-choosing the same keeps it")
    func brandChangeClearsModel() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.selectBrand("Audi")
        viewModel.selectModel("A4")

        viewModel.selectBrand("audi")
        #expect(viewModel.draft.model == "A4")

        viewModel.selectBrand("BMW")
        #expect(viewModel.draft.model.isEmpty)
    }

    @Test("Years are narrowed to the chosen model's production run")
    func modelYears() async {
        let (viewModel, _) = await makeViewModel()
        viewModel.selectBrand("Audi")
        viewModel.selectModel("A4")

        #expect(viewModel.modelYears?.first == 2025)
        #expect(viewModel.modelYears?.last == 1994)
        #expect(viewModel.allYears.first == 2026)   // FixedClock is in 2025
        #expect(viewModel.allYears.last == VehicleEditorFormatter.earliestYear)
    }

    @Test("Saving is only possible once brand and model are set")
    func canSave() async {
        let (viewModel, _) = await makeViewModel()
        #expect(!viewModel.canSave)
        viewModel.selectBrand("Audi")
        #expect(!viewModel.canSave)
        viewModel.selectModel("A4")
        #expect(viewModel.canSave)
    }

    @Test("A custom brand and model outside the catalog still save, with the typed mileage")
    func customVehicleSaves() async throws {
        let (viewModel, dependencies) = await makeViewModel()
        viewModel.selectBrand("FSO")
        viewModel.selectModel("Polonez")
        viewModel.mileageText = "123 456"

        await viewModel.save()

        let vehicle = try #require(try await dependencies.vehicles.defaultVehicle())
        #expect(vehicle.brand == "FSO")
        #expect(vehicle.model == "Polonez")
        let reading = try await dependencies.odometer.current(vehicleID: vehicle.id)
        #expect(reading?.value.kilometers == 123_456)
    }
}
