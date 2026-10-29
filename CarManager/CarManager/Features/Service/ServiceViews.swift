import SwiftUI

/// Service history, built from Figma 39.
struct ServiceHistoryView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: ServiceHistoryViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: String(localized: "Service history"), onBack: { model?.router.pop() }) {
                    CircleIconButton(symbol: "plus", accessibilityLabel: String(localized: "Add service")) { add() }
                        .accessibilityIdentifier("serviceAdd")
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
            hero(p.hero)
            VStack(spacing: 12) {
                ForEach(p.rows) { row in
                    recordCard(row)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Task { await viewModel?.delete(row.id, vehicleID: vehicleID) }
                            }
                        }
                }
            }
        case .empty:
            EmptyStateView(symbol: "wrench.adjustable", title: String(localized: "No service records"),
                           message: String(localized: "Log a visit to the workshop and matching reminders reset themselves."),
                           actionTitle: String(localized: "Add service"), action: add)
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't load service history"),
                           message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }

    private func hero(_ hero: ServiceHistoryPresentation.Hero) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !hero.eyebrow.isEmpty {
                Text(hero.eyebrow).font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.onCardSecondary)
            }
            Text(hero.title)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(hero.tone == .danger ? DS.Colors.danger : .white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(DS.Gradients.vehicleCard))
        .overlay(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).strokeBorder(DS.Colors.hairline))
    }

    private func recordCard(_ row: ServiceHistoryPresentation.Row) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.date)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(row.isRepair ? DS.Colors.warning : DS.Colors.accent)
                Text(row.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !row.meta.isEmpty {
                    Text(row.meta).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(row.cost)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(16)
        .dsSurface()
        .accessibilityElement(children: .combine)
    }

    private func add() { model?.router.present(.serviceEditor(.create(vehicleID))) }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            let d = model.dependencies
            viewModel = ServiceHistoryViewModel(
                query: QueryServiceHistory(services: d.services),
                evaluateReminders: EvaluateReminderTriggers(reminders: d.reminders, odometer: d.odometer, clock: d.clock),
                deleteRecord: DeleteServiceRecord(services: d.services, odometer: d.odometer),
                vehicles: d.vehicles, odometer: d.odometer,
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                clock: d.clock
            )
        }
        await viewModel?.load(vehicleID: vehicleID)
    }
}

struct ServiceDetailsView: View {
    let recordID: ServiceRecordID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: String(localized: "Service record"), onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}

/// Add Service, built from Figma 11.
struct AddServiceView: View {
    let mode: RecordEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: AddServiceViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel { AddServiceContentView(viewModel: viewModel) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            let created = AddServiceViewModel(
                vehicleID: mode.vehicleID,
                addServiceRecord: AddServiceRecord(services: d.services, odometer: d.odometer, reminders: d.reminders, clock: d.clock),
                vehicles: d.vehicles, odometer: d.odometer, router: model.router,
                currency: d.preferences.defaultCurrency,
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                now: d.clock.now
            )
            viewModel = created
            await created.prepare()
        }
    }
}

private struct AddServiceContentView: View {
    @Bindable var viewModel: AddServiceViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                EditorTopBar(title: String(localized: "Add Service"), trailingEnabled: viewModel.canSave,
                             onLeading: viewModel.cancel, onTrailing: save)
                VStack(spacing: 16) {
                    FormSurface {
                        FormMenuRow(label: String(localized: "Type"), options: ServiceType.allCases.map { ($0, $0.displayName) },
                                    selection: $viewModel.type, isFirst: true)
                            .accessibilityIdentifier("serviceTypeMenu")
                        FormDateRow(label: String(localized: "Date"), date: $viewModel.date, range: Date.distantPast...viewModel.now)
                        FormTextRow(label: String(localized: "Odometer"), text: $viewModel.odometerText, placeholder: viewModel.odometerHint ?? String(localized: "Optional"),
                                    unit: viewModel.format.distanceUnit, keyboard: .numberPad)
                        FormTextRow(label: String(localized: "Cost"), text: $viewModel.costText, placeholder: "0",
                                    unit: viewModel.format.currencySymbol(viewModel.currency), keyboard: .decimalPad)
                            .accessibilityIdentifier("serviceCostField")
                        FormTextRow(label: String(localized: "Workshop"), text: $viewModel.workshop, placeholder: String(localized: "Optional"))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: String(localized: "Also done"))
                        FlowLayout(spacing: 8) {
                            ForEach(viewModel.extraOptions) { extra in
                                SelectableChip(title: extra.displayName, isSelected: viewModel.extras.contains(extra)) {
                                    viewModel.toggle(extra)
                                }
                                .accessibilityIdentifier("serviceType_\(extra.rawValue)")
                            }
                        }
                    }

                    InfoBanner(symbol: "bell.badge",
                               text: String(localized: "Matching reminders (oil, filters, brakes, tyres…) are marked done and restart from this visit."),
                               tone: .neutral)

                    if let error = viewModel.errorMessage {
                        Text(error).font(DS.Text.subheadline).foregroundStyle(DS.Colors.danger).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    SaveButton(title: String(localized: "Save service"), isBusy: viewModel.isSaving, isEnabled: viewModel.canSave, action: save)
                        .accessibilityIdentifier("serviceSave")
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func save() { Task { await viewModel.save() } }
}
