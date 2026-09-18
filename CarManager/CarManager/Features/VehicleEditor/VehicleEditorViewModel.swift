import Foundation
import Observation

@MainActor
@Observable
final class VehicleEditorViewModel {
    var draft = VehicleDraft()
    /// Raw text of the mileage field. Parsed on save, so typing is never fought mid-keystroke.
    var mileageText = ""
    private(set) var state: ViewState<Vehicle> = .idle
    /// `nil` until loaded, or if loading failed — the pickers then fall back to free text.
    private(set) var catalog: VehicleCatalog?

    let mode: VehicleEditorMode
    private let createVehicle: CreateVehicle
    private let updateVehicle: UpdateVehicle
    private let loadCatalog: LoadVehicleCatalog
    private let vehicles: any VehicleRepository
    private let vehicleStore: SelectedVehicleStore
    private let featureGate: FeatureGate
    private let router: AppRouter
    private let clock: any ClockProviding
    private var editing: Vehicle?

    init(
        mode: VehicleEditorMode, createVehicle: CreateVehicle, updateVehicle: UpdateVehicle,
        loadCatalog: LoadVehicleCatalog, vehicles: any VehicleRepository,
        vehicleStore: SelectedVehicleStore, featureGate: FeatureGate, router: AppRouter,
        clock: any ClockProviding
    ) {
        self.mode = mode
        self.createVehicle = createVehicle
        self.updateVehicle = updateVehicle
        self.loadCatalog = loadCatalog
        self.vehicles = vehicles
        self.vehicleStore = vehicleStore
        self.featureGate = featureGate
        self.router = router
        self.clock = clock
    }

    var isCreating: Bool { if case .create = mode { return true }; return false }

    var canSave: Bool {
        !draft.brand.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.model.trimmingCharacters(in: .whitespaces).isEmpty
            && !isSaving
    }

    var isSaving: Bool { if case .loading = state { return true }; return false }

    var isPlateScanLocked: Bool { !featureGate.canUse(.plateScan) }

    // MARK: - Catalog

    var selectedBrand: VehicleCatalog.Brand? { catalog?.brand(named: draft.brand) }
    var selectedModel: VehicleCatalog.Model? { selectedBrand?.model(named: draft.model) }

    /// A different brand invalidates the model; the same brand re-picked keeps it.
    func selectBrand(_ name: String) {
        if CatalogSearch.key(name) != CatalogSearch.key(draft.brand) {
            draft.model = ""
        }
        draft.brand = name
    }

    func selectModel(_ name: String) { draft.model = name }

    /// Every plausible model year, newest first.
    var allYears: [Int] {
        let current = clock.calendar.component(.year, from: clock.now)
        return Array((VehicleEditorFormatter.earliestYear...(current + 1)).reversed())
    }

    /// The chosen model's production years when the catalog knows them.
    var modelYears: [Int]? {
        let current = clock.calendar.component(.year, from: clock.now)
        return selectedModel?.productionYears(currentYear: current)
    }

    // MARK: - Lifecycle

    func prepare() async {
        catalog = try? await loadCatalog()

        guard case .edit(let id) = mode else { return }
        guard let vehicle = try? await vehicles.vehicle(id: id) else { return }
        editing = vehicle
        draft = VehicleDraft(
            brand: vehicle.brand, model: vehicle.model, year: vehicle.year,
            trim: vehicle.trim, color: vehicle.color, vin: vehicle.vin,
            licensePlate: vehicle.licensePlate, fuelType: vehicle.fuelType,
            engineDisplacementCC: vehicle.engineDisplacementCC,
            purchaseDate: vehicle.purchaseDate, primaryCurrency: vehicle.primaryCurrency
        )
    }

    func save() async {
        state = .loading
        do {
            switch mode {
            case .create:
                var draft = draft
                draft.initialOdometer = Odometer(
                    kilometers: VehicleEditorFormatter.kilometers(from: mileageText) ?? 0
                )
                // The limit is resolved here and passed IN, so the use case stays free of
                // StoreKit and of @MainActor state.
                let output = try await createVehicle(draft, vehicleLimit: featureGate.vehicleLimit())
                await vehicleStore.refresh()
                // The first vehicle becomes the active one.
                if output.becameDefault { await vehicleStore.select(output.vehicle.id) }
                state = .loaded(output.vehicle)

            case .edit:
                guard var vehicle = editing else { throw DomainError.validation(.vehicleNotFound) }
                vehicle.brand = draft.brand
                vehicle.model = draft.model
                vehicle.year = draft.year
                vehicle.vin = draft.vin
                vehicle.fuelType = draft.fuelType
                let saved = try await updateVehicle(vehicle)
                await vehicleStore.refresh()
                state = .loaded(saved)
            }
            router.dismissModal()
        } catch let error as DomainError {
            // A vehicle-limit refusal routes to the paywall; it is not an error alert.
            if case .subscription(.vehicleLimitReached) = error {
                router.present(.paywall(.vehicleLimit))
            }
            state = .failed(ErrorPresenter.present(error))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}

/// Pure parsing and display helpers for the editor.
enum VehicleEditorFormatter {
    /// Older cars exist, but a year picker that starts in 1885 is a scroll nobody finishes.
    static let earliestYear = 1950

    /// "82,540", "82 540" and "82.540" all mean 82 540 km — people type the separator their
    /// locale shows. Decimals are not meaningful for an odometer.
    static func kilometers(from text: String) -> Double? {
        let digits = text.filter(\.isWholeNumber)
        return digits.isEmpty ? nil : Double(digits)
    }

    static func productionRange(_ model: VehicleCatalog.Model) -> String? {
        switch (model.from, model.to) {
        case let (from?, to?): from == to ? "\(from)" : "\(from)–\(to)"
        case let (from?, nil): "\(from)–present"
        default: nil
        }
    }
}
