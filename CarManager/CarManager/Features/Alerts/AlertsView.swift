import SwiftUI

/// The in-app notification inbox — a persisted, user-clearable feed. Distinct from the
/// OS notification queue, which holds only future fires. Built from Figma 05 (28 when empty).
struct AlertsView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: AlertsViewModel?
    @State private var confirmingClear = false

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: String(localized: "Alerts"), onBack: { model?.router.pop() }) {
                    if case .loaded = viewModel?.state {
                        Button("Clear") { confirmingClear = true }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .accessibilityIdentifier("alertsClear")
                    }
                }
                content.padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .confirmDialog(isPresented: $confirmingClear, symbol: "bell.slash", title: String(localized: "Clear all alerts?"),
                       message: String(localized: "Reminders themselves stay. Only this list is emptied."), confirmTitle: String(localized: "Clear")) {
            Task { await viewModel?.clear() }
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                let d = model.dependencies
                viewModel = AlertsViewModel(
                    load: LoadNotificationInbox(inbox: d.inbox),
                    clear: ClearNotifications(inbox: d.inbox),
                    markRead: MarkNotificationRead(inbox: d.inbox, clock: d.clock),
                    clock: d.clock
                )
            }
            await viewModel?.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let p):
            ForEach(p.groups) { group in
                VStack(spacing: 8) {
                    Eyebrow(text: group.title)
                    RowGroup(items: group.rows) { row in
                        Button { if let destination = row.destination { model?.router.push(destination) } } label: {
                            AlertRow(row: row)
                        }
                        .buttonStyle(.plain)
                        .disabled(row.destination == nil)
                    }
                }
            }
        case .empty:
            EmptyStateView(symbol: "checkmark", title: String(localized: "You're all caught up"),
                           message: String(localized: "Reminders and AI findings show up here when something needs your attention."))
                .padding(.top, 60)
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't load alerts"),
                           message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }
}

private struct AlertRow: View {
    let row: AlertsPresentation.Row

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(foreground)
                .frame(width: 44, height: 44)
                .background(Circle().fill(background))
                .overlay(alignment: .topTrailing) {
                    if row.isUnread {
                        Circle().fill(DS.Colors.accent).frame(width: 9, height: 9)
                            .overlay(Circle().strokeBorder(DS.Colors.surface, lineWidth: 2))
                            .accessibilityLabel("Unread")
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title).font(DS.Text.rowTitle).foregroundStyle(DS.Colors.textPrimary).lineLimit(1)
                Text(row.subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            if row.destination != nil { SettingsRowChevron() }
        }
        .padding(14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var foreground: Color {
        switch row.style {
        case .neutral, .ai: .white
        case .accent: DS.Colors.accent
        case .danger: DS.Colors.danger
        }
    }

    private var background: AnyShapeStyle {
        switch row.style {
        case .neutral: AnyShapeStyle(Color.white.opacity(0.051))
        case .accent: AnyShapeStyle(DS.Colors.accent.opacity(0.149))
        case .danger: AnyShapeStyle(DS.Colors.danger.opacity(0.16))
        case .ai: AnyShapeStyle(DS.Gradients.aiCard)
        }
    }
}

struct NotificationDetailsView: View {
    let notificationID: NotificationID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: String(localized: "Alert"), onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}
