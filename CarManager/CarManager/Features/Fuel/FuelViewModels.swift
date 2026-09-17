import Foundation
import Observation

@MainActor
@Observable
final class FuelHistoryViewModel {
    private(set) var state: ViewState<[FuelEntry]> = .idle

    private let loadHistory: LoadFuelHistory
    init(loadHistory: LoadFuelHistory) { self.loadHistory = loadHistory }

    func load(vehicleID: VehicleID) async {
        state = .loading
        do {
            let entries = try await loadHistory(vehicleID: vehicleID)
            state = entries.isEmpty ? .empty : .loaded(entries)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}

@MainActor
@Observable
final class AddFuelViewModel {
    var volumeText = ""
    var totalCostText = ""
    var odometerText = ""
    var isFullTank = true
    private(set) var state: ViewState<FuelEntry> = .idle
    private(set) var warnings: [DomainWarning] = []

    private let vehicleID: VehicleID
    private let addFuelEntry: AddFuelEntry
    private let router: AppRouter
    private let currency: CurrencyCode
    private let now: Date

    init(
        vehicleID: VehicleID, addFuelEntry: AddFuelEntry, router: AppRouter,
        currency: CurrencyCode, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addFuelEntry = addFuelEntry
        self.router = router
        self.currency = currency
        self.now = now
    }

    func save() async {
        state = .loading
        let draft = FuelEntryDraft(
            vehicleID: vehicleID, date: now,
            odometer: Odometer(kilometers: Double(odometerText) ?? 0),
            volume: Volume(liters: Double(volumeText) ?? 0),
            totalCost: Money(Decimal(Double(totalCostText) ?? 0), currency),
            fuelType: .petrol, isFullTank: isFullTank
        )
        do {
            let output = try await addFuelEntry(draft)
            warnings = output.warnings
            state = .loaded(output.entry)
            router.dismissModal()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
