import Foundation
import Observation

@MainActor
@Observable
final class VehicleDetailsViewModel {
    private(set) var state: ViewState<LoadVehicleDetail.Output> = .idle

    private let loadDetail: LoadVehicleDetail

    init(loadDetail: LoadVehicleDetail) { self.loadDetail = loadDetail }

    func load(vehicleID: VehicleID) async {
        state = .loading
        do {
            state = .loaded(try await loadDetail(id: vehicleID))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
