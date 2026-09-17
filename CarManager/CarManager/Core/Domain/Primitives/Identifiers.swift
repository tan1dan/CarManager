import Foundation

/// Typed identifiers. The Domain never exposes SwiftData's PersistentIdentifier.
public protocol EntityIdentifier: Hashable, Codable, Sendable, CustomStringConvertible {
    var raw: UUID { get }
    init(raw: UUID)
}

public extension EntityIdentifier {
    init() { self.init(raw: UUID()) }
    var description: String { raw.uuidString }
    init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(raw: uuid)
    }
}

public struct VehicleID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct FuelEntryID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct ServiceRecordID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct ExpenseID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct ReminderID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct DocumentID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct OdometerReadingID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct ConversationID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct MessageID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct InsightID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct NotificationID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct ReceiptScanID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct DashboardScanID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct DamageAnalysisID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
public struct UserID: EntityIdentifier { public let raw: UUID; public init(raw: UUID) { self.raw = raw } }
