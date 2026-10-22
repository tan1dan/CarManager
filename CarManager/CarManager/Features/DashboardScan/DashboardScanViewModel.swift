import Foundation
import Observation

@MainActor
@Observable
final class DashboardScanViewModel {
    private(set) var state: ProcessingState<DashboardScan> = .idle
    private(set) var imageData: Data?
    private(set) var failure: String?

    private let vehicleID: VehicleID?
    private let scanDashboard: ScanDashboard
    private var task: Task<Void, Never>?

    init(vehicleID: VehicleID?, scanDashboard: ScanDashboard) {
        self.vehicleID = vehicleID
        self.scanDashboard = scanDashboard
    }

    func analyze(_ data: Data) {
        imageData = data
        state = .processing
        task = Task {
            do {
                state = .success(try await scanDashboard(imageData: data, vehicleID: vehicleID))
            } catch {
                failure = UserMessage.text(for: error)
                state = .failed(ErrorPresenter.present(error))
            }
        }
    }

    func reset() {
        task?.cancel()
        imageData = nil
        failure = nil
        state = .idle
    }
}
