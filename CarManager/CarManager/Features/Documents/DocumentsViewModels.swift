import Foundation
import Observation
import UniformTypeIdentifiers

/// Display values for Documents (Figma 14, empty 25).
struct DocumentTile: Equatable, Sendable, Identifiable {
    var id: DocumentID
    var symbol: String
    var title: String
    var subtitle: String
    var tone: Tone
}

@MainActor
@Observable
final class DocumentsViewModel {
    var searchText = ""
    private(set) var state: ViewState<[DocumentTile]> = .idle

    private let evaluateExpiries: EvaluateDocumentExpiries
    private let deleteDocument: DeleteDocument
    private let format: DisplayFormat
    private var all: [DocumentTile] = []

    init(evaluateExpiries: EvaluateDocumentExpiries, deleteDocument: DeleteDocument, format: DisplayFormat) {
        self.evaluateExpiries = evaluateExpiries
        self.deleteDocument = deleteDocument
        self.format = format
    }

    /// `true` when the vehicle has documents but the search hides them all.
    var isFilteredEmpty: Bool { !all.isEmpty && filtered.isEmpty }
    var filtered: [DocumentTile] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func load(vehicleID: VehicleID?) async {
        if case .loaded = state {} else { state = .loading }
        do {
            all = try await evaluateExpiries(vehicleID: vehicleID)
                .sorted { $0.document.createdAt > $1.document.createdAt }
                .map(tile)
            state = all.isEmpty ? .empty : .loaded(all)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func delete(_ id: DocumentID, vehicleID: VehicleID?) async {
        try? await deleteDocument(id: id)
        await load(vehicleID: vehicleID)
    }

    func tile(_ item: EvaluateDocumentExpiries.Item) -> DocumentTile {
        let document = item.document
        let subtitle: String, tone: Tone
        switch item.status {
        case .expired(let days):
            subtitle = days == 0 ? String(localized: "Expired today") : String(localized: "Expired \(days) days ago"); tone = .danger
        case .expiringSoon(let days):
            subtitle = days == 0 ? String(localized: "Expires today") : String(localized: "Expires in \(days) days"); tone = .warning
        case .valid:
            subtitle = String(localized: "Valid to \(document.expirationDate.map(format.longDate) ?? "")"); tone = .accent
        case .noExpiry:
            subtitle = format.fileSummary(mimeType: document.mimeType, bytes: document.fileSize); tone = .neutral
        }
        return DocumentTile(id: document.id, symbol: document.type.symbolName, title: document.name, subtitle: subtitle, tone: tone)
    }
}

/// Upload Document (Figma 31).
@MainActor
@Observable
final class AddDocumentViewModel {
    struct PickedFile: Equatable {
        var data: Data
        var mimeType: String
        var name: String
    }

    var name = ""
    var type: DocumentType = .insurance
    var hasExpiry = true
    var expirationDate: Date
    private(set) var file: PickedFile?
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var vehicleName = ""

    private let vehicleID: VehicleID?
    private let addDocument: AddDocument
    private let createReminder: CreateReminder
    private let vehicles: any VehicleRepository
    private let router: AppRouter
    let format: DisplayFormat
    let now: Date

    init(
        vehicleID: VehicleID?, addDocument: AddDocument, createReminder: CreateReminder,
        vehicles: any VehicleRepository, router: AppRouter, format: DisplayFormat, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addDocument = addDocument
        self.createReminder = createReminder
        self.vehicles = vehicles
        self.router = router
        self.format = format
        self.now = now
        self.expirationDate = format.calendar.date(byAdding: .year, value: 1, to: now) ?? now
    }

    func prepare() async {
        if let vehicleID, let vehicle = try? await vehicles.vehicle(id: vehicleID) { vehicleName = vehicle.displayName }
    }

    var fileSummary: String? {
        file.map { format.fileSummary(mimeType: $0.mimeType, bytes: Int64($0.data.count)) }
    }

    var canSave: Bool { file != nil && !isSaving }

    func attach(data: Data, mimeType: String, suggestedName: String) {
        errorMessage = nil
        guard Int64(data.count) <= AddDocument.maxFileSize else {
            errorMessage = UserMessage.text(for: DomainError.document(.fileTooLarge(maxBytes: AddDocument.maxFileSize)))
            return
        }
        file = PickedFile(data: data, mimeType: mimeType, name: suggestedName)
        if name.trimmingCharacters(in: .whitespaces).isEmpty { name = suggestedName }
    }

    func fail(_ error: Error) { errorMessage = UserMessage.text(for: error) }

    func save() async {
        guard let file, canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? type.displayName : name
        do {
            let document = try await addDocument(
                vehicleID: vehicleID, name: title, type: type,
                expirationDate: hasExpiry ? expirationDate : nil,
                fileData: file.data, mimeType: file.mimeType
            )
            // The promise on the upload screen: an expiry date becomes a reminder.
            if let vehicleID, let expiry = document.expirationDate, expiry > now {
                _ = try? await createReminder(
                    vehicleID: vehicleID, title: String(localized: "\(title) expires"), kind: type.reminderKind,
                    trigger: .date(DateTrigger(dueDate: expiry)), recurrence: .none,
                    leadTime: ReminderLeadTime(days: 7, distance: nil)
                )
            }
            router.dismissModal()
        } catch {
            errorMessage = UserMessage.text(for: error)
        }
    }

    func cancel() { router.dismissModal() }
}

/// Document viewer (Figma 48): loads the bytes once and hands QuickLook a temporary file.
@MainActor
@Observable
final class DocumentViewerViewModel {
    struct Loaded: Equatable {
        var title: String
        var meta: String
        var fileURL: URL
        var banner: String?
        var bannerTone: Tone
    }
    private(set) var state: ViewState<Loaded> = .idle

    private let loadFile: LoadDocumentFile
    private let format: DisplayFormat
    private let clock: any ClockProviding

    init(loadFile: LoadDocumentFile, format: DisplayFormat, clock: any ClockProviding) {
        self.loadFile = loadFile
        self.format = format
        self.clock = clock
    }

    func load(id: DocumentID) async {
        state = .loading
        do {
            let (document, data) = try await loadFile(id: id)
            let ext = UTType(mimeType: document.mimeType)?.preferredFilenameExtension ?? "dat"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(String(localized: "Preview"), isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = document.name.replacingOccurrences(of: "/", with: "-")
            let url = directory.appendingPathComponent("\(safeName).\(ext)")
            try data.write(to: url, options: .completeFileProtection)

            var meta = format.fileSummary(mimeType: document.mimeType, bytes: document.fileSize)
            var banner: String?, tone = Tone.accent
            if let expiry = document.expirationDate {
                meta += " · " + String(localized: "expires \(format.longDate(expiry))")
                switch DocumentExpiryEvaluator.status(for: document, now: clock.now, calendar: clock.calendar) {
                case .expired: banner = String(localized: "This document has expired. Upload the renewed one to keep reminders right."); tone = .danger
                case .expiringSoon(let days): banner = String(localized: "Expires in \(days) days."); tone = .warning
                default: break
                }
            }
            state = .loaded(Loaded(title: document.name, meta: meta, fileURL: url, banner: banner, bannerTone: tone))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
