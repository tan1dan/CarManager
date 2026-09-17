import Foundation
import Observation

@MainActor
@Observable
final class GarageViewModel {
    private(set) var state: ViewState<[VehicleSummary]> = .idle
    /// Display-ready values, rebuilt once per load so the view never formats anything.
    private(set) var presentation: GaragePresentationModel = .empty

    private let loadGarage: LoadGarage
    private let formatter: GarageFormatter

    init(loadGarage: LoadGarage, formatter: GarageFormatter) {
        self.loadGarage = loadGarage
        self.formatter = formatter
    }

    func load() async {
        state = .loading
        do {
            let summaries = try await loadGarage()
            presentation = formatter.makeModel(from: summaries)
            state = summaries.isEmpty ? .empty : .loaded(summaries)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
