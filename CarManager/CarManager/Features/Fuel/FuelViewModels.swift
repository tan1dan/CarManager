import Foundation
import Observation

/// Display values for Fuel History (Figma 12).
struct FuelHistoryPresentation: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var id: FuelEntryID
        var title: String
        var subtitle: String
        var amount: String
    }
    struct Chart: Equatable, Sendable {
        var value: String
        var unit: String
        var change: String?
        var changeTone: Tone
        var points: [Double?]
        var labels: [String]
    }
    var chart: Chart?
    var rows: [Row]
}

extension Tone: Equatable {}

@MainActor
@Observable
final class FuelHistoryViewModel {
    private(set) var state: ViewState<FuelHistoryPresentation> = .idle

    private let loadAnalytics: LoadVehicleAnalytics
    private let deleteEntry: DeleteFuelEntry
    private let format: DisplayFormat
    private let clock: any ClockProviding

    init(loadAnalytics: LoadVehicleAnalytics, deleteEntry: DeleteFuelEntry, format: DisplayFormat, clock: any ClockProviding) {
        self.loadAnalytics = loadAnalytics
        self.deleteEntry = deleteEntry
        self.format = format
        self.clock = clock
    }

    func load(vehicleID: VehicleID) async {
        if case .loaded = state {} else { state = .loading }
        do {
            let analytics = try await loadAnalytics(vehicleID: vehicleID)
            guard !analytics.fuelEntries.isEmpty else { state = .empty; return }
            state = .loaded(present(analytics))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func delete(_ id: FuelEntryID, vehicleID: VehicleID) async {
        try? await deleteEntry(id: id)
        await load(vehicleID: vehicleID)
    }

    func present(_ analytics: VehicleAnalytics) -> FuelHistoryPresentation {
        let rows = analytics.fuelEntries.map { entry in
            FuelHistoryPresentation.Row(
                id: entry.id,
                title: entry.station ?? (entry.isFullTank ? "Full tank" : "Top-up"),
                subtitle: format.shortDate(entry.date, relativeTo: clock.now) + " · " + format.volume(entry.volume),
                amount: format.money(entry.totalCost)
            )
        }
        // The trend covers the last 8 months; months without a closed segment are gaps.
        let recent = Array(analytics.monthlyConsumption.suffix(8))
        let chart: FuelHistoryPresentation.Chart? = analytics.averageConsumption.map { average in
            let change = analytics.consumptionChange
            return .init(
                value: format.consumption(average),
                unit: format.consumptionUnit,
                change: change.map { format.percentChange($0) + " vs last month" },
                // More fuel per 100 km is worse; for mpg the sign flips, but the change is
                // computed on L/100 km either way.
                changeTone: (change ?? 0) > 0.005 ? .warning : (change ?? 0) < -0.005 ? .success : .neutral,
                points: recent.map(\.value),
                labels: recent.map { format.month($0.monthStart) }
            )
        }
        return FuelHistoryPresentation(chart: chart, rows: rows)
    }
}

@MainActor
@Observable
final class AddFuelViewModel {
    var totalCostText = ""
    var volumeText = ""
    var odometerText = ""
    var station = ""
    var date: Date
    var isFullTank = true
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var odometerHint: String?
    private(set) var fuelType: FuelType = .petrol
    private(set) var currency: CurrencyCode

    private let vehicleID: VehicleID
    private let addFuelEntry: AddFuelEntry
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let router: AppRouter
    let format: DisplayFormat
    let now: Date

    init(
        vehicleID: VehicleID, addFuelEntry: AddFuelEntry, vehicles: any VehicleRepository,
        odometer: any OdometerRepository, router: AppRouter, currency: CurrencyCode, format: DisplayFormat, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addFuelEntry = addFuelEntry
        self.vehicles = vehicles
        self.odometer = odometer
        self.router = router
        self.currency = currency
        self.format = format
        self.now = now
        self.date = now
    }

    func prepare() async {
        if let vehicle = try? await vehicles.vehicle(id: vehicleID) {
            fuelType = vehicle.fuelType
            currency = vehicle.primaryCurrency
        }
        if let current = try? await odometer.current(vehicleID: vehicleID) {
            odometerHint = format.integer(current.value.kilometers)
        }
    }

    var canSave: Bool {
        (NumberInput.decimal(totalCostText) ?? 0) > 0 && (NumberInput.double(volumeText) ?? 0) > 0
            && (NumberInput.double(odometerText) ?? 0) > 0 && !isSaving
    }

    /// "48 L · €1.75 / L" under the amount, once both numbers are in.
    var meta: String? {
        guard let total = NumberInput.decimal(totalCostText), let liters = NumberInput.double(volumeText), liters > 0, total > 0 else { return nil }
        let perLiter = total / Decimal(liters)
        return format.volume(Volume(liters: liters)) + " · " + format.money(perLiter, currency, fractionDigits: 2) + " / L"
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let draft = FuelEntryDraft(
            vehicleID: vehicleID, date: date,
            odometer: Odometer(kilometers: NumberInput.double(odometerText) ?? 0),
            volume: Volume(liters: NumberInput.double(volumeText) ?? 0),
            totalCost: Money(NumberInput.decimal(totalCostText) ?? 0, currency),
            fuelType: fuelType,
            station: station.trimmingCharacters(in: .whitespaces).isEmpty ? nil : station,
            isFullTank: isFullTank
        )
        do {
            _ = try await addFuelEntry(draft)
            router.dismissModal()
        } catch {
            errorMessage = UserMessage.text(for: error)
        }
    }

    func cancel() { router.dismissModal() }
}
