import Foundation
import UserNotifications

/// The ONLY file in the app importing UserNotifications. The domain hands over plain
/// `ScheduledNotification` values and never sees a UN type.
public struct UNNotificationScheduler: NotificationScheduling {
    public init() {}

    public func authorizationStatus() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        default: .notDetermined
        }
    }

    public func requestAuthorization() async throws -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            throw DomainError.permission(.notificationsDenied)
        }
    }

    public func schedule(_ requests: [ScheduledNotification]) async throws {
        let center = UNUserNotificationCenter.current()
        for request in requests {
            let content = UNMutableNotificationContent()
            // Localised at delivery time, not at schedule time.
            content.title = NSString.localizedUserNotificationString(
                forKey: request.titleKey, arguments: request.arguments
            )
            content.body = NSString.localizedUserNotificationString(
                forKey: request.bodyKey, arguments: request.arguments
            )
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: request.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(
                identifier: request.identifier, content: content, trigger: trigger
            ))
        }
    }

    public func cancel(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    public func cancelAll(matching prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let matching = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: matching)
    }
}

/// Records what was scheduled — scheduling IS the side effect, so this is the one place
/// where call verification is the right tool.
public actor SpyNotificationScheduler: NotificationScheduling {
    public private(set) var scheduled: [ScheduledNotification] = []
    public private(set) var cancelledIdentifiers: [String] = []
    private var status: NotificationAuthorization

    public init(status: NotificationAuthorization = .authorized) { self.status = status }

    public func authorizationStatus() async -> NotificationAuthorization { status }
    public func requestAuthorization() async throws -> Bool { status == .authorized }
    public func schedule(_ requests: [ScheduledNotification]) async throws {
        scheduled.append(contentsOf: requests)
    }
    public func cancel(identifiers: [String]) async {
        cancelledIdentifiers.append(contentsOf: identifiers)
    }
    public func cancelAll(matching prefix: String) async {
        scheduled.removeAll { $0.identifier.hasPrefix(prefix) }
    }
}
