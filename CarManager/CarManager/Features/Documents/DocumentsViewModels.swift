import Foundation
import Observation

@MainActor
@Observable
final class DocumentsViewModel {
    var searchText = ""
    private(set) var state: ViewState<[EvaluateDocumentExpiries.Item]> = .idle

    private let query: QueryDocuments
    private let evaluateExpiries: EvaluateDocumentExpiries

    init(query: QueryDocuments, evaluateExpiries: EvaluateDocumentExpiries) {
        self.query = query
        self.evaluateExpiries = evaluateExpiries
    }

    func load(vehicleID: VehicleID?) async {
        state = .loading
        do {
            let items = try await evaluateExpiries(vehicleID: vehicleID)
            let filtered = searchText.isEmpty
                ? items
                : items.filter { $0.document.name.localizedCaseInsensitiveContains(searchText) }
            state = filtered.isEmpty ? .empty : .loaded(filtered)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}

@MainActor
@Observable
final class AddDocumentViewModel {
    var name = ""
    var type: DocumentType = .other
    private(set) var state: ViewState<DocumentMetadata> = .idle

    private let vehicleID: VehicleID?
    private let addDocument: AddDocument
    private let router: AppRouter

    init(vehicleID: VehicleID?, addDocument: AddDocument, router: AppRouter) {
        self.vehicleID = vehicleID
        self.addDocument = addDocument
        self.router = router
    }

    func save() async {
        state = .loading
        do {
            // Placeholder payload — the real file picker arrives with the UI stage.
            let document = try await addDocument(
                vehicleID: vehicleID, name: name, type: type,
                fileData: Data("placeholder".utf8)
            )
            state = .loaded(document)
            router.dismissModal()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
