import Foundation

public enum DocumentType: String, CaseIterable, Codable, Sendable, Identifiable {
    case insurance, registration, technicalInspection, warranty, driverLicense,
         serviceDocument, purchaseInvoice, manual, other
    public var id: String { rawValue }
}

/// Metadata only. Bytes live in FileStorage behind a FileRef.
public struct DocumentMetadata: Identifiable, Hashable, Sendable {
    public let id: DocumentID
    public let vehicleID: VehicleID?
    public var name: String
    public var type: DocumentType
    public var startDate: Date?
    public var expirationDate: Date?
    public var note: String?
    public var fileRef: FileRef
    public var fileSize: Int64
    public var mimeType: String
    public var pageCount: Int?
    public var thumbnailRef: FileRef?
    public var reminderID: ReminderID?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: DocumentID = DocumentID(), vehicleID: VehicleID?, name: String, type: DocumentType,
        startDate: Date? = nil, expirationDate: Date? = nil, note: String? = nil,
        fileRef: FileRef, fileSize: Int64 = 0, mimeType: String = "application/pdf",
        pageCount: Int? = nil, thumbnailRef: FileRef? = nil, reminderID: ReminderID? = nil,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.name = name; self.type = type
        self.startDate = startDate; self.expirationDate = expirationDate; self.note = note
        self.fileRef = fileRef; self.fileSize = fileSize; self.mimeType = mimeType
        self.pageCount = pageCount; self.thumbnailRef = thumbnailRef; self.reminderID = reminderID
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public enum DocumentExpiryStatus: Hashable, Sendable {
    case noExpiry
    case valid
    case expiringSoon(daysRemaining: Int)
    case expired(daysAgo: Int)
}

public struct DocumentQuery: Hashable, Sendable {
    public var vehicleID: VehicleID?
    public var types: Set<DocumentType>?
    public var searchText: String?
    public init(vehicleID: VehicleID? = nil, types: Set<DocumentType>? = nil, searchText: String? = nil) {
        self.vehicleID = vehicleID; self.types = types; self.searchText = searchText
    }
}
