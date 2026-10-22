import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var state: ViewState<HomeDashboard> = .idle
    /// Display-ready values. Built once per load so the view never formats anything.
    private(set) var presentation: HomePresentationModel = .placeholder

    private let loadDashboard: LoadHomeDashboard
    private let loadAnalytics: LoadVehicleAnalytics
    private let formatter: HomeFormatter

    init(loadAnalytics: LoadVehicleAnalytics, loadDashboard: LoadHomeDashboard, formatter: HomeFormatter) {
        self.loadDashboard = loadDashboard
        self.loadAnalytics = loadAnalytics
        self.formatter = formatter
    }

    func load(vehicleID: VehicleID?, userName: String?) async {
        guard let vehicleID else {
            presentation = .placeholder
            presentation.greeting = formatter.greeting(for: userName)
            state = .empty
            return
        }
        state = .loading
        do {
            async let dashboardTask = loadDashboard(vehicleID: vehicleID)
            // Analytics failing must not take the dashboard down with it: the tiles just
            // fall back to "—".
            async let analyticsTask = try? loadAnalytics(vehicleID: vehicleID)
            let dashboard = try await dashboardTask
            presentation = formatter.makeModel(from: dashboard, analytics: await analyticsTask, userName: userName)
            state = .loaded(dashboard)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
