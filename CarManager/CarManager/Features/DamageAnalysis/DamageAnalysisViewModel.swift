import Foundation
import Observation

@MainActor
@Observable
final class DamageAnalysisViewModel {
    private(set) var state: ProcessingState<DamageAnalysis> = .idle
    private(set) var imageData: Data?
    private(set) var failure: String?

    private let vehicleID: VehicleID
    private let analyzeDamage: AnalyzeDamage
    private var task: Task<Void, Never>?

    init(vehicleID: VehicleID, analyzeDamage: AnalyzeDamage) {
        self.vehicleID = vehicleID
        self.analyzeDamage = analyzeDamage
    }

    func analyze(_ data: Data) {
        imageData = data
        state = .processing
        task = Task {
            do {
                state = .success(try await analyzeDamage(imagesData: [data], vehicleID: vehicleID))
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
