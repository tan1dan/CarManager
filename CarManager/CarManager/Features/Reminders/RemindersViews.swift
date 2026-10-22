import SwiftUI

/// Reminders, built from Figma 15 (and 26 when empty).
struct RemindersView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: RemindersViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "Reminders", onBack: { model?.router.pop() }) {
                    CircleIconButton(symbol: "plus", filled: true, accessibilityLabel: "Add reminder") { add() }
                        .accessibilityIdentifier("reminderAdd")
                }
                content.padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .task { await load() }
        .onChange(of: model?.router.activeModal) { _, modal in if modal == nil { Task { await load() } } }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let p):
            if let next = p.nextUp { nextUpCard(next) }
            VStack(spacing: 8) {
                Eyebrow(text: "All reminders")
                RowGroup(items: p.rows) { row in
                    reminderRow(row)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await viewModel?.delete(row.id, vehicleID: vehicleID) }
                            }
                        }
                }
            }
        case .empty:
            EmptyStateView(symbol: "bell", title: "Nothing scheduled",
                           message: "Add a reminder by date or by mileage and we'll warn you in time.",
                           actionTitle: "Add reminder", action: add)
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load reminders",
                           message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }

    private func nextUpCard(_ next: RemindersPresentation.NextUp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Next up").padding(.bottom, 6)
            Text(next.title)
                .font(DS.Text.headline).tracking(DS.Text.headlineTracking)
                .foregroundStyle(.white)
            Text(next.subtitle)
                .font(DS.Text.subheadlineRegular)
                .foregroundStyle(next.tone == .danger ? DS.Colors.danger : DS.Colors.textSecondary)
                .padding(.top, 2)
            if let fraction = next.fraction {
                ProgressBar(fraction: fraction, color: next.tone == .accent ? DS.Colors.accent : next.tone.color, height: 6)
                    .padding(.top, 18)
                    .accessibilityIdentifier("reminderProgress")
                HStack {
                    if let start = next.startLabel { Text(start) }
                    Spacer()
                    if let end = next.endLabel { Text(end) }
                }
                .font(DS.Text.statCaption)
                .foregroundStyle(DS.Colors.textSecondary)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .dsSurface()
    }

    private func reminderRow(_ row: RemindersPresentation.Row) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(row.tone == .danger ? DS.Colors.danger : .white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(row.tone == .danger ? DS.Colors.danger.opacity(0.16) : Color.white.opacity(0.051)))
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title).font(DS.Text.rowTitle).foregroundStyle(DS.Colors.textPrimary).lineLimit(1)
                Text(row.subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            ProgressRing(fraction: row.fraction, color: row.tone == .neutral ? DS.Colors.textSecondary : row.tone.color, lineWidth: 3)
                .frame(width: 22, height: 22)
        }
        .padding(14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private func add() { model?.router.present(.reminderEditor(.create(vehicleID))) }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            let d = model.dependencies
            viewModel = RemindersViewModel(
                evaluate: EvaluateReminderTriggers(reminders: d.reminders, odometer: d.odometer, clock: d.clock),
                deleteReminder: DeleteReminder(reminders: d.reminders, notifications: d.notifications),
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                clock: d.clock
            )
        }
        await viewModel?.load(vehicleID: vehicleID)
    }
}

struct ReminderDetailsView: View {
    let reminderID: ReminderID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: "Reminder", onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}

/// Add Reminder, built from Figma 30.
struct AddReminderView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddReminderViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel { AddReminderContentView(viewModel: viewModel) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            let created = AddReminderViewModel(
                vehicleID: mode.vehicleID,
                createReminder: CreateReminder(reminders: d.reminders, notifications: d.notifications, clock: d.clock),
                vehicles: d.vehicles, odometer: d.odometer, router: model.router,
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                now: d.clock.now
            )
            viewModel = created
            await created.prepare()
        }
    }
}

private struct AddReminderContentView: View {
    @Bindable var viewModel: AddReminderViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorTopBar(title: "Add Reminder", trailingEnabled: viewModel.canSave,
                             onLeading: viewModel.cancel, onTrailing: save)
                VStack(spacing: 16) {
                    SegmentedPill(options: [(.date, "By date"), (.mileage, "By mileage")], selection: $viewModel.triggerKind)
                        .accessibilityIdentifier("reminderTriggerPicker")
                    FormSurface {
                        FormTextRow(label: "Title", text: $viewModel.title, placeholder: viewModel.titlePlaceholder, isFirst: true)
                            .accessibilityIdentifier("reminderTitleField")
                        FormMenuRow(label: "Type", options: viewModel.kindOptions, selection: $viewModel.kind)
                        switch viewModel.triggerKind {
                        case .date:
                            FormDateRow(label: "Due date", date: $viewModel.dueDate, range: viewModel.now...Date.distantFuture)
                            FormMenuRow(label: "Repeat", options: viewModel.repeatOptions, selection: $viewModel.repeatRule)
                            FormMenuRow(label: "Notify", options: viewModel.leadDayOptions, selection: $viewModel.leadDays)
                        case .mileage:
                            FormTextRow(label: "Every", text: $viewModel.intervalText, placeholder: "15000",
                                        unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            FormTextRow(label: "Last done at", text: $viewModel.lastDoneText,
                                        placeholder: viewModel.currentOdometer.map { viewModel.format.integer($0) } ?? "0",
                                        unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                            FormToggleRow(label: "Repeat", isOn: $viewModel.repeatsByDistance)
                            FormMenuRow(label: "Notify", options: viewModel.leadDistanceOptions, selection: $viewModel.leadDistance)
                        }
                        if !viewModel.vehicleName.isEmpty {
                            FormValueRow(label: "Vehicle", value: viewModel.vehicleName)
                        }
                    }
                    InfoBanner(symbol: "bell", text: viewModel.explanation, tone: .accent)
                    if let error = viewModel.errorMessage {
                        Text(error).font(DS.Text.subheadline).foregroundStyle(DS.Colors.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SaveButton(title: "Save reminder", isBusy: viewModel.isSaving, isEnabled: viewModel.canSave, action: save)
                        .accessibilityIdentifier("reminderSave")
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() { Task { await viewModel.save() } }
}
