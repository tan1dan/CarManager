import Foundation
import Observation

@MainActor
@Observable
final class DashboardScanViewModel {
    private(set) var state: ProcessingState<DashboardScan> = .idle

    private let vehicleID: VehicleID?
    private let scanDashboard: ScanDashboard
    private var task: Task<Void, Never>?

    init(vehicleID: VehicleID?, scanDashboard: ScanDashboard) {
        self.vehicleID = vehicleID
        self.scanDashboard = scanDashboard
    }

    func capture() {
        state = .processing
        task = Task {
            do {
                let scan = try await scanDashboard(
                    imageData: Data("placeholder-dashboard".utf8), vehicleID: vehicleID
                )
                state = .success(scan)
            } catch {
                state = .failed(ErrorPresenter.present(error))
            }
        }
    }

    func reset() {
        task?.cancel()
        state = .idle
    }
}
