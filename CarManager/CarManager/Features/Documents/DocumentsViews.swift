import SwiftUI

struct DocumentsView: View {
    let vehicleID: VehicleID?
    @Environment(\.appModel) private var model
    @State private var viewModel: DocumentsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                DocumentsContentView(viewModel: viewModel, vehicleID: vehicleID)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Documents")
        .toolbar {
            Button("Add") { model?.router.present(.documentEditor(vehicleID)) }
                .accessibilityIdentifier("documentAdd")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = DocumentsViewModel(
                    query: QueryDocuments(documents: model.dependencies.documents),
                    evaluateExpiries: EvaluateDocumentExpiries(
                        documents: model.dependencies.documents,
                        clock: model.dependencies.clock
                    )
                )
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }
}

private struct DocumentsContentView: View {
    @Bindable var viewModel: DocumentsViewModel
    let vehicleID: VehicleID?
    @Environment(\.appModel) private var model

    var body: some View {
        List {
            Text("Documents")
            TextField("Search documents", text: $viewModel.searchText)
                .accessibilityIdentifier("documentsSearch")
                .onChange(of: viewModel.searchText) {
                    Task { await viewModel.load(vehicleID: vehicleID) }
                }

            switch viewModel.state {
            case .loading: ProgressView()
            case .loaded(let items):
                ForEach(items) { item in
                    Button("\(item.document.name) · \(String(describing: item.status))") {
                        model?.router.push(.documentDetail(item.document.id))
                    }
                }
            case .empty: Text("No documents")
            case .failed(let error): Text(error.messageKey)
            default: Text("Idle")
            }
        }
    }
}

struct DocumentDetailsView: View {
    let documentID: DocumentID
    @Environment(\.appModel) private var model

    var body: some View {
        List {
            Text("Document Details")
            Button("Preview") { model?.router.presentFullScreen(.documentViewer(documentID)) }
                .accessibilityIdentifier("documentPreview")
        }
        .navigationTitle("Document")
    }
}

/// Placeholder for the QuickLook viewer. A file not yet downloaded from iCloud will show
/// FileAvailability.downloading here rather than a broken viewer.
struct DocumentPreviewView: View {
    let documentID: DocumentID
    @Environment(\.appModel) private var model

    var body: some View {
        VStack(spacing: 12) {
            Text("Document Preview")
            Button("Close") { model?.router.dismissFullScreen() }
        }
    }
}

struct AddDocumentView: View {
    let vehicleID: VehicleID?
    @Environment(\.appModel) private var model
    @State private var viewModel: AddDocumentViewModel?

    var body: some View {
        Group {
            if let viewModel { AddDocumentContentView(viewModel: viewModel) } else { ProgressView() }
        }
        .navigationTitle("Add document")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = AddDocumentViewModel(
                vehicleID: vehicleID,
                addDocument: AddDocument(
                    documents: model.dependencies.documents,
                    files: model.dependencies.files,
                    clock: model.dependencies.clock
                ),
                router: model.router
            )
        }
    }
}

private struct AddDocumentContentView: View {
    @Bindable var viewModel: AddDocumentViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Add Document")
            TextField("Name", text: $viewModel.name)
                .accessibilityIdentifier("documentNameField")
            Picker("Type", selection: $viewModel.type) {
                ForEach(DocumentType.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Save") { Task { await viewModel.save() } }
                .accessibilityIdentifier("documentSave")
            Button("Cancel") { model?.router.dismissModal() }
            if let error = viewModel.state.error { Text(error.messageKey) }
        }
    }
}
