import Foundation
import Observation

@MainActor
@Observable
final class AlertsViewModel {
    private(set) var state: ViewState<[AppNotification]> = .idle

    private let loadInbox: LoadNotificationInbox
    private let clearAll: ClearNotifications

    init(load: LoadNotificationInbox, clear: ClearNotifications) {
        self.loadInbox = load
        self.clearAll = clear
    }

    func load() async {
        state = .loading
        do {
            let notifications = try await loadInbox()
            state = notifications.isEmpty ? .empty : .loaded(notifications)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func clear() async {
        try? await clearAll()
        await load()
    }
}
