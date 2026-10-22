import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// Documents, built from Figma 14 (and 25 when empty).
struct DocumentsView: View {
    let vehicleID: VehicleID?
    @Environment(\.appModel) private var model
    @State private var viewModel: DocumentsViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "Documents", onBack: { model?.router.pop() }) {
                    CircleIconButton(symbol: "plus", filled: true, accessibilityLabel: "Upload document") { add() }
                        .accessibilityIdentifier("documentAdd")
                }
                if let viewModel { DocumentsContentView(viewModel: viewModel, vehicleID: vehicleID, add: add) }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .dsScreen()
        .task { await load() }
        .onChange(of: model?.router.activeModal) { _, modal in if modal == nil { Task { await load() } } }
    }

    private func add() { model?.router.present(.documentEditor(vehicleID)) }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            let d = model.dependencies
            viewModel = DocumentsViewModel(
                evaluateExpiries: EvaluateDocumentExpiries(documents: d.documents, clock: d.clock),
                deleteDocument: DeleteDocument(documents: d.documents, files: d.files),
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem)
            )
        }
        await viewModel?.load(vehicleID: vehicleID)
    }
}

private struct DocumentsContentView: View {
    @Bindable var viewModel: DocumentsViewModel
    let vehicleID: VehicleID?
    let add: () -> Void
    @Environment(\.appModel) private var model

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .loaded:
                searchField
                if viewModel.isFilteredEmpty {
                    Text("Nothing matches “\(viewModel.searchText)”.")
                        .font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.textSecondary)
                        .padding(.top, 24)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(viewModel.filtered) { tile in
                            Button { model?.router.presentFullScreen(.documentViewer(tile.id)) } label: { DocumentTileView(tile: tile) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        Task { await viewModel.delete(tile.id, vehicleID: vehicleID) }
                                    }
                                }
                        }
                    }
                }
            case .empty:
                EmptyStateView(symbol: "doc.text", title: "No documents",
                               message: "Keep insurance, registration and receipts here. Expiry dates become reminders.",
                               actionTitle: "Upload document", action: add)
            case .failed(let error):
                EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load documents",
                               message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
            default:
                ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
            }
        }
        .padding(.horizontal, DS.Layout.gutter)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(DS.Colors.textSecondary)
            TextField("", text: $viewModel.searchText, prompt: Text("Search documents").foregroundStyle(DS.Colors.textSecondary))
                .font(DS.Text.subheadlineRegular)
                .foregroundStyle(.white)
                .tint(DS.Colors.accent)
                .submitLabel(.search)
                .accessibilityIdentifier("documentsSearch")
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .dsGlass(radius: 22)
    }
}

private struct DocumentTileView: View {
    let tile: DocumentTile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: tile.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tile.tone == .neutral ? .white : tile.tone.color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(tile.tone == .neutral ? Color.white.opacity(0.06) : tile.tone.color.opacity(0.16)))
                .padding(.bottom, 16)
            Text(tile.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(tile.subtitle)
                .font(DS.Text.statCaption)
                .foregroundStyle(tile.tone == .danger ? DS.Colors.danger : DS.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .dsSurface(radius: 20)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// A document pushed from Home's "Upcoming" list: the same viewer, closed with the back button.
struct DocumentDetailsView: View {
    let documentID: DocumentID
    @Environment(\.appModel) private var model

    var body: some View {
        DocumentViewerContent(documentID: documentID) { model?.router.pop() }
    }
}

/// Document viewer, built from Figma 48.
struct DocumentPreviewView: View {
    let documentID: DocumentID
    @Environment(\.appModel) private var model

    var body: some View {
        DocumentViewerContent(documentID: documentID) { model?.router.dismissFullScreen() }
    }
}

private struct DocumentViewerContent: View {
    let documentID: DocumentID
    let onClose: () -> Void
    @Environment(\.appModel) private var model
    @State private var viewModel: DocumentViewerViewModel?

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel?.state {
            case .loaded(let doc):
                PushedHeader(title: doc.title, subtitle: doc.meta, onBack: onClose) {
                    ShareLink(item: doc.fileURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color.white.opacity(0.051)))
                    }
                    .accessibilityLabel("Share")
                }
                QuickLookPreview(url: doc.fileURL)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .padding(.horizontal, DS.Layout.gutter)
                if let banner = doc.banner {
                    InfoBanner(symbol: "bell", text: banner, tone: doc.bannerTone)
                        .padding(.horizontal, DS.Layout.gutter)
                }
            case .failed:
                PushedHeader(title: "Document", onBack: onClose)
                EmptyStateView(symbol: "icloud.slash", title: "File isn't available",
                               message: "It may still be downloading, or it was removed from this device.")
                Spacer()
            default:
                PushedHeader(title: "Document", onBack: onClose)
                ProgressView().tint(DS.Colors.textSecondary).frame(maxHeight: .infinity)
            }
        }
        .padding(.bottom, 16)
        .dsScreen()
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            let created = DocumentViewerViewModel(
                loadFile: LoadDocumentFile(documents: d.documents, files: d.files),
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                clock: d.clock
            )
            viewModel = created
            await created.load(id: documentID)
        }
    }
}

/// QuickLook renders PDFs and photos, with paging, zoom and Markup for free.
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}

/// Upload Document, built from Figma 31.
struct AddDocumentView: View {
    let vehicleID: VehicleID?
    @Environment(\.appModel) private var model
    @State private var viewModel: AddDocumentViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel { AddDocumentContentView(viewModel: viewModel) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            let created = AddDocumentViewModel(
                vehicleID: vehicleID,
                addDocument: AddDocument(documents: d.documents, files: d.files, clock: d.clock),
                createReminder: CreateReminder(reminders: d.reminders, notifications: d.notifications, clock: d.clock),
                vehicles: d.vehicles, router: model.router,
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                now: d.clock.now
            )
            viewModel = created
            await created.prepare()
        }
    }
}

private struct AddDocumentContentView: View {
    @Bindable var viewModel: AddDocumentViewModel
    @State private var choosingSource = false
    @State private var importingFile = false
    @State private var pickingPhoto = false
    @State private var photo: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorTopBar(title: "Upload Document", trailing: "Upload", trailingEnabled: viewModel.canSave,
                             onLeading: viewModel.cancel, onTrailing: save)
                VStack(spacing: 16) {
                    dropZone
                    FormSurface {
                        FormTextRow(label: "Title", text: $viewModel.name, placeholder: viewModel.type.displayName, isFirst: true)
                            .accessibilityIdentifier("documentNameField")
                        FormMenuRow(label: "Type", options: DocumentType.allCases.map { ($0, $0.displayName) }, selection: $viewModel.type)
                        FormToggleRow(label: "Has expiry date", isOn: $viewModel.hasExpiry)
                        if viewModel.hasExpiry {
                            FormDateRow(label: "Expiry date", date: $viewModel.expirationDate)
                        }
                        if !viewModel.vehicleName.isEmpty {
                            FormValueRow(label: "Vehicle", value: viewModel.vehicleName)
                        }
                    }
                    Text(viewModel.hasExpiry
                         ? "Files are kept on this iPhone. The expiry date becomes a reminder 7 days ahead."
                         : "Files are kept on this iPhone.")
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let error = viewModel.errorMessage {
                        Text(error).font(DS.Text.subheadline).foregroundStyle(DS.Colors.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SaveButton(title: "Upload document", symbol: "doc.badge.arrow.up", isBusy: viewModel.isSaving,
                               isEnabled: viewModel.canSave, action: save)
                        .accessibilityIdentifier("documentSave")
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Add a file", isPresented: $choosingSource) {
            Button("Choose a file") { importingFile = true }
            Button("Photo library") { pickingPhoto = true }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.pdf, .image]) { result in
            switch result {
            case .success(let url): readFile(url)
            case .failure(let error): viewModel.fail(error)
            }
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let type = item.supportedContentTypes.first(where: { $0.conforms(to: .image) }) ?? .jpeg
                viewModel.attach(data: data, mimeType: type.preferredMIMEType ?? "image/jpeg", suggestedName: viewModel.type.displayName)
            }
        }
    }

    private var dropZone: some View {
        Button { choosingSource = true } label: {
            VStack(spacing: 6) {
                Image(systemName: viewModel.fileSummary == nil ? "doc.badge.arrow.up" : "checkmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(DS.Colors.accent.opacity(0.15)))
                    .padding(.bottom, 8)
                Text(viewModel.fileSummary == nil ? "Choose a PDF or photo" : "File attached")
                    .font(DS.Text.rowTitle).foregroundStyle(.white)
                Text(viewModel.fileSummary ?? "Insurance, registration, receipts")
                    .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius)
                    .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                    .background(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(Color.white.opacity(0.02)))
            )
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("documentPickFile")
    }

    private func readFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            viewModel.attach(data: data, mimeType: type.preferredMIMEType ?? "application/octet-stream",
                             suggestedName: url.deletingPathExtension().lastPathComponent)
        } catch {
            viewModel.fail(error)
        }
    }

    private func save() { Task { await viewModel.save() } }
}
