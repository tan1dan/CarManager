import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    private(set) var state: ViewState<HomeDashboard> = .idle
    /// Display-ready values. Built once per load so the view never formats anything.
    private(set) var presentation: HomePresentationModel = .placeholder

    private let loadDashboard: LoadHomeDashboard
    private let formatter: HomeFormatter

    init(loadDashboard: LoadHomeDashboard, formatter: HomeFormatter) {
        self.loadDashboard = loadDashboard
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
            let dashboard = try await loadDashboard(vehicleID: vehicleID)
            presentation = formatter.makeModel(from: dashboard, userName: userName)
            state = .loaded(dashboard)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
