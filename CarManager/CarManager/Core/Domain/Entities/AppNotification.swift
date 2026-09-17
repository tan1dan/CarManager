import Foundation

public enum NotificationKind: String, Codable, Sendable {
    case documentExpiring, reminderDue, aiInsight, fuelLogged, syncIssue, subscriptionLapsed
}

/// The in-app inbox item (screen "Alerts"). Distinct from an OS-scheduled UNNotificationRequest:
/// different lifetime, different storage, different purpose.
public struct AppNotification: Identifiable, Hashable, Sendable {
    public let id: NotificationID
    public let vehicleID: VehicleID?
    public var kind: NotificationKind
    /// Stored as a key + arguments, localised at render — otherwise switching language
    /// leaves a stale inbox.
    public var titleKey: String
    public var bodyKey: String
    public var arguments: [String]
    public var createdAt: Date
    public var readAt: Date?

    public init(
        id: NotificationID = NotificationID(), vehicleID: VehicleID? = nil, kind: NotificationKind,
        titleKey: String, bodyKey: String, arguments: [String] = [],
        createdAt: Date, readAt: Date? = nil
    ) {
        self.id = id; self.vehicleID = vehicleID; self.kind = kind
        self.titleKey = titleKey; self.bodyKey = bodyKey; self.arguments = arguments
        self.createdAt = createdAt; self.readAt = readAt
    }

    public var isRead: Bool { readAt != nil }
}
