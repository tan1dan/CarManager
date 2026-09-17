import SwiftUI

/// The in-app notification inbox — a persisted, user-clearable feed. Distinct from the
/// OS notification queue, which holds only future fires.
struct AlertsView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: AlertsViewModel?

    var body: some View {
        List {
            Text("Alerts")
            switch viewModel?.state {
            case .loading: ProgressView()
            case .loaded(let notifications):
                ForEach(notifications) { notification in
                    Button(notification.titleKey) {
                        model?.router.push(.notificationDetail(notification.id))
                    }
                }
            case .empty: Text("No alerts")
            case .failed(let error): Text(error.messageKey)
            default: Text("Idle")
            }
        }
        .navigationTitle("Alerts")
        .toolbar {
            Button("Clear") { Task { await viewModel?.clear() } }
                .accessibilityIdentifier("alertsClear")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = AlertsViewModel(
                    load: LoadNotificationInbox(inbox: model.dependencies.inbox),
                    clear: ClearNotifications(inbox: model.dependencies.inbox)
                )
            }
            await viewModel?.load()
        }
    }
}

struct NotificationDetailsView: View {
    let notificationID: NotificationID
    var body: some View {
        Text("Notification Details").navigationTitle("Alert")
    }
}
