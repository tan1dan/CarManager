import Foundation
import Observation

/// Display values for Alerts (Figma 05, empty 28).
struct AlertsPresentation: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        var id: NotificationID
        var symbol: String
        var style: Style
        var title: String
        var subtitle: String
        var isUnread: Bool
        var destination: AppRoute?
    }
    enum Style: Equatable, Sendable { case neutral, accent, danger, ai }
    struct Group: Equatable, Sendable, Identifiable {
        var id: String { title }
        var title: String
        var rows: [Row]
    }
    var groups: [Group]
}

@MainActor
@Observable
final class AlertsViewModel {
    private(set) var state: ViewState<AlertsPresentation> = .idle

    private let loadInbox: LoadNotificationInbox
    private let clearAll: ClearNotifications
    private let markRead: MarkNotificationRead
    private let calendar: Calendar
    private let clock: any ClockProviding

    init(load: LoadNotificationInbox, clear: ClearNotifications, markRead: MarkNotificationRead, clock: any ClockProviding) {
        self.loadInbox = load
        self.clearAll = clear
        self.markRead = markRead
        self.calendar = clock.calendar
        self.clock = clock
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let notifications = try await loadInbox()
            state = notifications.isEmpty ? .empty : .loaded(present(notifications))
            // Opening the inbox reads it; the dots stay for this visit so the user sees what was new.
            let unread = notifications.filter { !$0.isRead }.map(\.id)
            if !unread.isEmpty { try? await markRead(ids: unread) }
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func clear() async {
        try? await clearAll()
        await load()
    }

    func present(_ notifications: [AppNotification]) -> AlertsPresentation {
        let now = clock.now
        let startOfToday = calendar.startOfDay(for: now)
        let startOfWeek = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        var today: [AlertsPresentation.Row] = [], week: [AlertsPresentation.Row] = [], earlier: [AlertsPresentation.Row] = []
        for notification in notifications.sorted(by: { $0.createdAt > $1.createdAt }) {
            let row = row(notification)
            if notification.createdAt >= startOfToday { today.append(row) }
            else if notification.createdAt >= startOfWeek { week.append(row) }
            else { earlier.append(row) }
        }
        let groups = [(String(localized: "Today"), today), (String(localized: "This week"), week), (String(localized: "Earlier"), earlier)]
            .filter { !$0.1.isEmpty }
            .map { AlertsPresentation.Group(title: $0.0, rows: $0.1) }
        return AlertsPresentation(groups: groups)
    }

    private func row(_ n: AppNotification) -> AlertsPresentation.Row {
        let (symbol, style): (String, AlertsPresentation.Style) = switch n.kind {
        case .documentExpiring: ("checkmark.shield", .danger)
        case .reminderDue: ("bell", .neutral)
        case .aiInsight: ("sparkles", .ai)
        case .fuelLogged: ("fuelpump", .accent)
        case .syncIssue: ("exclamationmark.icloud", .danger)
        case .subscriptionLapsed: ("crown", .neutral)
        }
        let destination: AppRoute? = n.vehicleID.flatMap { id in
            switch n.kind {
            case .documentExpiring: .documents(id)
            case .reminderDue: .reminders(id)
            case .fuelLogged: .fuelHistory(id)
            case .aiInsight: .analytics(id, .sixMonths)
            case .syncIssue, .subscriptionLapsed: nil
            }
        }
        return .init(
            id: n.id, symbol: symbol, style: style,
            // Keys are looked up in the string catalog; seeded and older entries are plain text.
            title: Self.text(n.titleKey, n.arguments),
            subtitle: Self.text(n.bodyKey, n.arguments),
            isUnread: !n.isRead,
            destination: destination
        )
    }

    /// Localises a stored key. Formatting only runs with arguments, so a literal "9%" survives.
    private static func text(_ key: String, _ arguments: [String]) -> String {
        let template = String(localized: String.LocalizationValue(key))
        return arguments.isEmpty ? template : String(format: template, arguments: arguments.map { $0 as CVarArg })
    }
}
