import Foundation

/// URL → AppDestination. Pure, so every link is round-trip testable.
/// Notification payloads carry a Codable AppDestination and take the SAME path through the
/// router — one routing implementation, not two.
public enum DeepLinkParser {
    public static let scheme = "carmanager"

    public static func destination(from url: URL) -> AppDestination? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        switch host {
        case "vehicle":
            guard let raw = segments.first, let id = VehicleID(uuidString: raw) else { return nil }
            if segments.count >= 3, segments[1] == "fuel", segments[2] == "add" {
                return AppDestination(tab: .home, modal: .fuelEditor(.create(id)))
            }
            if segments.count >= 2 {
                switch segments[1] {
                case "fuel": return .tab(.garage, path: [.vehicleDetail(id), .fuelHistory(id)])
                case "service": return .tab(.garage, path: [.vehicleDetail(id), .serviceHistory(id)])
                case "expenses": return .tab(.garage, path: [.vehicleDetail(id), .expenses(id)])
                case "documents": return .tab(.garage, path: [.vehicleDetail(id), .documents(id)])
                case "reminders": return .tab(.garage, path: [.vehicleDetail(id), .reminders(id)])
                default: break
                }
            }
            return .tab(.garage, path: [.vehicleDetail(id)])

        case "service":
            guard let raw = segments.first, let id = ServiceRecordID(uuidString: raw) else { return nil }
            return .tab(.garage, path: [.serviceDetail(id)])

        case "expense":
            guard let raw = segments.first, let id = ExpenseID(uuidString: raw) else { return nil }
            return .tab(.garage, path: [.expenseDetail(id)])

        case "reminder":
            guard let raw = segments.first, let id = ReminderID(uuidString: raw) else { return nil }
            return .tab(.home, path: [.reminderDetail(id)])

        case "document":
            guard let raw = segments.first, let id = DocumentID(uuidString: raw) else { return nil }
            return .tab(.garage, path: [.documentDetail(id)])

        case "ai":
            if segments.first == "chat" {
                let conversation = query.first { $0.name == "conversation" }?.value
                    .flatMap { ConversationID(uuidString: $0) }
                return .tab(.ai, path: [.aiChat(conversation)])
            }
            return .tab(.ai)

        case "alerts":
            return .tab(.home, path: [.alerts])

        case "premium":
            return .modal(.paywall(.settingsUpgrade))

        case "settings":
            if let raw = segments.first, let section = SettingsSection(rawValue: raw) {
                return .tab(.profile, path: [.settings, .settingsSection(section)])
            }
            return .tab(.profile, path: [.settings])

        default:
            return nil
        }
    }

    /// Notification userInfo carries the destination directly.
    public static func destination(fromNotificationPayload payload: [AnyHashable: Any]) -> AppDestination? {
        guard let data = payload["destination"] as? Data else { return nil }
        return try? JSONDecoder().decode(AppDestination.self, from: data)
    }
}
