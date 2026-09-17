import SwiftUI

struct RemindersView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: RemindersViewModel?

    var body: some View {
        List {
            Text("Reminders")

            if let next = viewModel?.nextUp {
                Section("Next up") {
                    Text(next.reminder.title)
                    Text("Status: \(String(describing: next.status))")
                    if let progress = next.progress {
                        // Progress needs a BASELINE odometer, not just a due value —
                        // that is why MileageTrigger carries one.
                        ProgressView(value: progress.fraction)
                            .accessibilityIdentifier("reminderProgress")
                    }
                }
            }

            Section("All reminders") {
                switch viewModel?.state {
                case .loading: ProgressView()
                case .loaded(let evaluations):
                    ForEach(evaluations) { evaluation in
                        Button(evaluation.reminder.title) {
                            model?.router.push(.reminderDetail(evaluation.reminder.id))
                        }
                    }
                case .empty: Text("No reminders")
                case .failed(let error): Text(error.messageKey)
                default: Text("Idle")
                }
            }
        }
        .navigationTitle("Reminders")
        .toolbar {
            Button("Add") { model?.router.present(.reminderEditor(.create(vehicleID))) }
                .accessibilityIdentifier("reminderAdd")
        }
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = RemindersViewModel(
                    evaluate: EvaluateReminderTriggers(
                        reminders: model.dependencies.reminders,
                        odometer: model.dependencies.odometer,
                        clock: model.dependencies.clock
                    )
                )
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }
}

struct ReminderDetailsView: View {
    let reminderID: ReminderID
    var body: some View { Text("Reminder Details").navigationTitle("Reminder") }
}

struct AddReminderView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddReminderViewModel?

    var body: some View {
        Group {
            if let viewModel { AddReminderContentView(viewModel: viewModel) } else { ProgressView() }
        }
        .navigationTitle("Add reminder")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = AddReminderViewModel(
                vehicleID: mode.vehicleID,
                createReminder: CreateReminder(
                    reminders: model.dependencies.reminders,
                    notifications: model.dependencies.notifications,
                    clock: model.dependencies.clock
                ),
                router: model.router,
                now: model.dependencies.clock.now
            )
        }
    }
}

private struct AddReminderContentView: View {
    @Bindable var viewModel: AddReminderViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Add Reminder")
            TextField("Title", text: $viewModel.title)
                .accessibilityIdentifier("reminderTitleField")

            Picker("Trigger", selection: $viewModel.triggerKind) {
                Text("Date").tag(AddReminderViewModel.TriggerKind.date)
                Text("Mileage").tag(AddReminderViewModel.TriggerKind.mileage)
                Text("Whichever first").tag(AddReminderViewModel.TriggerKind.whicheverFirst)
            }
            .accessibilityIdentifier("reminderTriggerPicker")

            Button("Save") { Task { await viewModel.save() } }
                .accessibilityIdentifier("reminderSave")
            Button("Cancel") { model?.router.dismissModal() }

            if let warning = viewModel.warnings.first {
                Text(verbatim: "Warning: \(warning)")
            }
            if let error = viewModel.state.error { Text(error.messageKey) }
        }
    }
}
