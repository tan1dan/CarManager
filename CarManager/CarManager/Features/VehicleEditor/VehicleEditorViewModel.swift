import Foundation
import Observation

@MainActor
@Observable
final class VehicleEditorViewModel {
    var draft = VehicleDraft()
    private(set) var state: ViewState<Vehicle> = .idle

    private let mode: VehicleEditorMode
    private let createVehicle: CreateVehicle
    private let updateVehicle: UpdateVehicle
    private let vehicles: any VehicleRepository
    private let vehicleStore: SelectedVehicleStore
    private let featureGate: FeatureGate
    private let router: AppRouter
    private var editing: Vehicle?

    init(
        mode: VehicleEditorMode, createVehicle: CreateVehicle, updateVehicle: UpdateVehicle,
        vehicles: any VehicleRepository, vehicleStore: SelectedVehicleStore,
        featureGate: FeatureGate, router: AppRouter
    ) {
        self.mode = mode
        self.createVehicle = createVehicle
        self.updateVehicle = updateVehicle
        self.vehicles = vehicles
        self.vehicleStore = vehicleStore
        self.featureGate = featureGate
        self.router = router
    }

    func prepare() async {
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
