import SwiftUI

/// Home, built from Figma node 3:3977 ("04 · Home · Dashboard").
///
/// The view renders `HomePresentationModel` only — no arithmetic, no formatting, no domain
/// enums beyond picking an icon. Values the app cannot compute yet render as an em dash
/// rather than a fabricated zero.
struct HomeView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: HomeViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Layout.sectionSpacing) {
                    header

                    switch viewModel?.state {
                    case .loading, .idle, .none:
                        ProgressView().tint(DS.Colors.textSecondary).padding(.top, 40)
                    case .empty:
                        emptyGarage
                    case .failed(let error):
                        failure(error)
                    case .loaded(let dashboard):
                        content(for: dashboard)
                    }
                }
                .padding(.bottom, DS.Layout.tabBarReservedHeight)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: model?.vehicles.selected?.id) { Task { await load() } }
        // Stopgap until the repository change feed lands (architecture Phase 4): reload when
        // an editor sheet closes, since a new record may have been written.
        .onChange(of: model?.router.activeModal) { _, modal in
            if modal == nil { Task { await load() } }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text(presentation.greeting)
                    .font(DS.Text.subheadline)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(DS.Colors.textSecondary)
                Text(presentation.title)
                    .font(DS.Text.title)
                    .tracking(DS.Text.titleTracking)
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            Spacer(minLength: 12)
            notificationButton
        }
        .padding(.horizontal, DS.Layout.headerGutter)
        .padding(.top, 16)
    }

    private var notificationButton: some View {
        Button {
            model?.router.push(.alerts, in: .home)
        } label: {
            Image(systemName: "bell")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(DS.Colors.textPrimary)
                .frame(width: 44, height: 44)
                .dsGlass(radius: 22)
                .overlay(alignment: .topTrailing) {
                    // The design keeps this dot empty; it appears only when there is
                    // something unread.
                    if presentation.unreadCount > 0 {
                        Circle()
                            .fill(DS.Colors.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: 1, y: -1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeAlerts")
        .accessibilityLabel("Alerts")
    }

    @ViewBuilder
    private func content(for dashboard: HomeDashboard) -> some View {
        VehicleSummaryCard(card: presentation.vehicle) {
            model?.router.push(.vehicleDetail(dashboard.vehicle.id), in: .home)
        }
        .padding(.horizontal, DS.Layout.gutter)
        .accessibilityIdentifier("homeVehicleCard")

        if let insight = presentation.insight {
            AIRecommendationCard(card: insight)
                .padding(.horizontal, DS.Layout.gutter)
        }

        if !presentation.upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Upcoming")
                    .font(DS.Text.section)
                    .tracking(DS.Text.sectionTracking)
                    .foregroundStyle(DS.Colors.onCardPrimary)

                VStack(spacing: 10) {
                    ForEach(presentation.upcoming) { row in
                        UpcomingRowView(row: row) {
                            if let destination = row.destination {
                                model?.router.push(destination, in: .home)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Layout.gutter)
        }

        HStack(spacing: 12) {
            ForEach(presentation.tiles) { tile in
                StatTileView(tile: tile)
            }
        }
        .padding(.horizontal, DS.Layout.gutter)
    }

    private var emptyGarage: some View {
        VStack(spacing: 12) {
            Text("No vehicle yet")
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.textPrimary)
            Text("Add your first vehicle to see it here.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Colors.textSecondary)
            Button("Add vehicle") { model?.router.present(.vehicleEditor(.create)) }
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.accent)
                .accessibilityIdentifier("homeAddVehicle")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, DS.Layout.gutter)
    }

    private func failure(_ error: ErrorPresentation) -> some View {
        VStack(spacing: 8) {
            Text(error.titleKey)
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.textPrimary)
            Button("Retry") { Task { await load() } }
                .font(DS.Text.caption)
                .foregroundStyle(DS.Colors.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - Wiring

    private var presentation: HomePresentationModel {
        viewModel?.presentation ?? .placeholder
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            viewModel = HomeViewModel(
                loadDashboard: LoadHomeDashboard(
                    vehicles: model.dependencies.vehicles,
                    odometer: model.dependencies.odometer,
                    fuel: model.dependencies.fuel,
                    evaluateReminders: EvaluateReminderTriggers(
                        reminders: model.dependencies.reminders,
                        odometer: model.dependencies.odometer,
                        clock: model.dependencies.clock
                    ),
                    evaluateDocuments: EvaluateDocumentExpiries(
                        documents: model.dependencies.documents,
                        clock: model.dependencies.clock
                    ),
                    insights: model.dependencies.insights,
                    inbox: model.dependencies.inbox
                ),
                formatter: HomeFormatter(
                    clock: model.dependencies.clock,
                    unitSystem: model.dependencies.preferences.unitSystem
                )
            )
        }
        await viewModel?.load(
            vehicleID: model.selectedVehicleID,
            userName: model.auth.state.profile?.displayName
        )
    }
}

// MARK: - Vehicle card

private struct VehicleSummaryCard: View {
    let card: HomePresentationModel.VehicleCard
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("My vehicle")
                            .font(DS.Text.subheadline)
                            .tracking(DS.Text.defaultTracking)
                            .foregroundStyle(DS.Colors.onCardSecondary)
                        Text(card.name)
                            .font(DS.Text.headline)
                            .tracking(DS.Text.headlineTracking)
                            .foregroundStyle(DS.Colors.onCardPrimary)
                        Text(card.subtitle)
                            .font(DS.Text.subheadlineRegular)
                            .tracking(DS.Text.defaultTracking)
                            .foregroundStyle(DS.Colors.onCardTertiary)
                    }
                    Spacer(minLength: 8)
                    if let chip = card.statusChip {
                        Text(chip)
                            .font(DS.Text.chip)
                            .tracking(DS.Text.defaultTracking)
                            .foregroundStyle(DS.Colors.onCardPrimary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5)
                            .dsGlass(radius: DS.Layout.chipRadius)
                    }
                }

                HStack(spacing: 8) {
                    ForEach(card.stats) { stat in
                        CompactStatView(stat: stat)
                    }
                }
                .padding(.top, 20)
            }
            .padding(21)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .circular)
                    .fill(DS.Gradients.vehicleCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Layout.cardRadius, style: .circular)
                            .strokeBorder(Color.white.opacity(0.051), lineWidth: DS.Layout.hairlineWidth)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct CompactStatView: View {
    let stat: HomePresentationModel.CompactStat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stat.caption)
                .font(DS.Text.statLabel)
                .tracking(DS.Text.statLabelTracking)
                .foregroundStyle(DS.Colors.onCardTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(stat.value ?? "—")
                    .font(DS.Text.statValue)
                    .tracking(DS.Text.statValueTracking)
                    .foregroundStyle(DS.Colors.onCardPrimary)
                if stat.value != nil, let unit = stat.unit {
                    Text(unit)
                        .font(DS.Text.statUnit)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.onCardTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Layout.surfaceRadius)
    }
}

// MARK: - AI recommendation

private struct AIRecommendationCard: View {
    let card: HomePresentationModel.InsightCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white.opacity(0.149)))
                Text(card.eyebrow)
                    .font(DS.Text.eyebrow)
                    .tracking(DS.Text.eyebrowTracking)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
            Text(card.body)
                .font(DS.Text.body)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius, style: .circular)
                .fill(DS.Gradients.aiCard)
        )
    }
}

// MARK: - Upcoming row

private struct UpcomingRowView: View {
    let row: HomePresentationModel.UpcomingRow
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: row.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(row.tone == .danger ? DS.Colors.danger : DS.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(
                            row.tone == .danger
                                ? DS.Colors.danger.opacity(0.149)
                                : Color.clear
                        )
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title)
                        .font(DS.Text.rowTitle)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.textPrimary)
                    Text(row.subtitle)
                        .font(DS.Text.caption)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .padding(14)
            .dsSurface()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("homeUpcoming_\(row.id)")
    }
}

// MARK: - Stat tile

private struct StatTileView: View {
    let tile: HomePresentationModel.StatTile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tile.label)
                .font(DS.Text.caption)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(DS.Colors.textSecondary)
            Text(tile.value ?? "—")
                .font(DS.Text.headline)
                .tracking(DS.Text.headlineTracking)
                .foregroundStyle(DS.Colors.onCardPrimary)
            if let delta = tile.delta {
                Text(delta)
                    .font(DS.Text.badge)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(tile.deltaTone == .danger ? DS.Colors.danger : DS.Colors.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(
                            tile.deltaTone == .danger ? DS.Colors.danger.opacity(0.149) : Color.clear
                        )
                    )
            } else {
                Color.clear.frame(height: 19)
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface()
    }
}
