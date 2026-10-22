import Foundation
import Observation

/// Display values for Vehicle Detail (Figma 07). The view does no formatting.
struct VehicleDetailPresentation: Equatable, Sendable {
    struct Stat: Equatable, Sendable, Identifiable {
        var id: String { caption }
        var caption: String
        var value: String
        var unit: String?
    }
    struct Tile: Equatable, Sendable, Identifiable {
        var id: String { title }
        var symbol: String
        var title: String
        var subtitle: String
        var route: AppRoute
    }

    var eyebrow: String
    var name: String
    var stats: [Stat]
    var tiles: [Tile]
    /// nil when there is no spending yet — the card is hidden instead of showing €0.
    var monthlyCost: (value: String, bars: [Double?], labels: [String])?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.eyebrow == rhs.eyebrow && lhs.name == rhs.name && lhs.stats == rhs.stats && lhs.tiles == rhs.tiles
            && lhs.monthlyCost?.value == rhs.monthlyCost?.value
    }
}

@MainActor
@Observable
final class VehicleDetailsViewModel {
    private(set) var state: ViewState<VehicleDetailPresentation> = .idle
    var isConfirmingDelete = false

    private let loadDetail: LoadVehicleDetail
    private let loadAnalytics: LoadVehicleAnalytics
    private let deleteVehicle: DeleteVehicle
    private let vehicleStore: SelectedVehicleStore
    private let router: AppRouter
    private let format: DisplayFormat

    init(
        loadDetail: LoadVehicleDetail, loadAnalytics: LoadVehicleAnalytics, deleteVehicle: DeleteVehicle,
        vehicleStore: SelectedVehicleStore, router: AppRouter, format: DisplayFormat
    ) {
        self.loadDetail = loadDetail
        self.loadAnalytics = loadAnalytics
        self.deleteVehicle = deleteVehicle
        self.vehicleStore = vehicleStore
        self.router = router
        self.format = format
    }

    func load(vehicleID: VehicleID) async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let detail = loadDetail(id: vehicleID)
            async let analytics = loadAnalytics(vehicleID: vehicleID)
            state = .loaded(present(try await detail, try await analytics, vehicleID: vehicleID))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func delete(vehicleID: VehicleID) async {
        do {
            try await deleteVehicle(id: vehicleID)
            await vehicleStore.refresh()
            router.pop()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func present(_ detail: LoadVehicleDetail.Output, _ analytics: VehicleAnalytics, vehicleID: VehicleID) -> VehicleDetailPresentation {
        let vehicle = detail.vehicle
        let eyebrow = [vehicle.year.map(String.init), vehicle.trim].compactMap { $0 }.joined(separator: " · ")
        var stats: [VehicleDetailPresentation.Stat] = [
            .init(caption: "MILEAGE",
                  value: detail.currentOdometer.map { format.integer(format.unitSystem == .metric ? $0.kilometers : $0.value.miles) } ?? "—",
                  unit: detail.currentOdometer == nil ? nil : format.distanceUnit),
            .init(caption: format.unitSystem == .metric ? "AVG L/100" : "AVG MPG",
                  value: analytics.averageConsumption.map(format.consumption) ?? "—")
        ]
        let registered = [vehicle.registrationCountry, vehicle.licensePlate].compactMap { $0 }.joined(separator: " · ")
        stats.append(.init(caption: "REGISTERED", value: registered.isEmpty ? "—" : registered))
        stats.append(.init(caption: "FUEL", value: vehicle.fuelType.displayName))

        let tiles: [VehicleDetailPresentation.Tile] = [
            .init(symbol: "wrench.adjustable", title: "Service", subtitle: count(detail.serviceRecordCount, "record"), route: .serviceHistory(vehicleID)),
            .init(symbol: "fuelpump", title: "Fuel", subtitle: count(detail.fuelEntryCount, "fill-up"), route: .fuelHistory(vehicleID)),
            .init(symbol: "creditcard", title: "Expenses", subtitle: analytics.hasAnyCost ? format.money(analytics.yearSpend, analytics.currency) + " this year" : "Nothing yet", route: .expenses(vehicleID)),
            .init(symbol: "bell", title: "Reminders", subtitle: "Due dates", route: .reminders(vehicleID)),
            .init(symbol: "doc.text", title: "Documents", subtitle: count(detail.documentCount, "document"), route: .documents(vehicleID)),
            .init(symbol: "chart.bar", title: "Statistics", subtitle: "This year", route: .analytics(vehicleID, .year))
        ]

        let last6 = Array(analytics.monthlySpend.suffix(6))
        let total6 = last6.reduce(Decimal(0)) { $0 + $1.value }
        let monthlyCost: (String, [Double?], [String])? = total6 > 0
            ? (format.money(total6 / 6, analytics.currency, fractionDigits: 0),
               last6.map { $0.value.doubleValue },
               last6.map { format.month($0.monthStart) })
            : nil

        return VehicleDetailPresentation(
            eyebrow: eyebrow, name: vehicle.displayName, stats: stats, tiles: tiles,
            monthlyCost: monthlyCost.map { (value: $0.0, bars: $0.1, labels: $0.2) }
        )
    }

    private func count(_ n: Int, _ noun: String) -> String {
        n == 0 ? "None yet" : "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
