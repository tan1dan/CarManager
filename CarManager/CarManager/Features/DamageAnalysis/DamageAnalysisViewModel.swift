import Foundation
import Observation

@MainActor
@Observable
final class DamageAnalysisViewModel {
    private(set) var state: ProcessingState<DamageAnalysis> = .idle

    private let vehicleID: VehicleID
    private let analyzeDamage: AnalyzeDamage
    private var task: Task<Void, Never>?

    init(vehicleID: VehicleID, analyzeDamage: AnalyzeDamage) {
        self.vehicleID = vehicleID
        self.analyzeDamage = analyzeDamage
    }

    func analyze() {
        state = .processing
        task = Task {
            do {
                let analysis = try await analyzeDamage(
                    imagesData: [Data("placeholder-damage".utf8)], vehicleID: vehicleID
                )
                state = .success(analysis)
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
