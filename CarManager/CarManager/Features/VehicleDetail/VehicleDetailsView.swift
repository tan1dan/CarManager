import SwiftUI

/// Vehicle Detail, built from Figma 07 (and 40 for the delete confirmation).
struct VehicleDetailsView: View {
    let vehicleID: VehicleID
    @Environment(\.appModel) private var model
    @State private var viewModel: VehicleDetailsViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "", onBack: { model?.router.pop() }) {
                    Button("Edit") { model?.router.present(.vehicleEditor(.edit(vehicleID))) }
                        .font(DS.Text.button)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(Capsule().fill(Color.white.opacity(0.051)))
                        .accessibilityIdentifier("vehicleEdit")
                }
                content
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .confirmDialog(
            isPresented: Binding(get: { viewModel?.isConfirmingDelete ?? false }, set: { viewModel?.isConfirmingDelete = $0 }),
            title: presentation.map { String(localized: "Delete \($0.name)?") } ?? String(localized: "Delete vehicle?"),
            message: String(localized: "Its fuel, service, expenses and documents are deleted from iCloud too. This cannot be undone."),
            confirmTitle: String(localized: "Delete vehicle")
        ) {
            Task { await viewModel?.delete(vehicleID: vehicleID) }
        }
        .task { await load() }
        .onChange(of: model?.vehicles.revision) { Task { await load() } }
        .onChange(of: model?.router.activeModal) { _, modal in
            if modal == nil { Task { await load() } }
        }
    }

    private var presentation: VehicleDetailPresentation? {
        if case .loaded(let p) = viewModel?.state { return p }
        return nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let p):
            hero(p)
            details(p)
            if let cost = p.monthlyCost { costCard(cost) }
            Button("Delete vehicle") { viewModel?.isConfirmingDelete = true }
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .dsSurface()
                .padding(.horizontal, DS.Layout.gutter)
                .accessibilityIdentifier("vehicleDelete")
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't load this vehicle"), message: error.messageKey)
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }

    private func hero(_ p: VehicleDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !p.eyebrow.isEmpty {
                Text(p.eyebrow).font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.onCardSecondary)
            }
            Text(p.name)
                .font(DS.Text.title).tracking(DS.Text.titleTracking)
                .foregroundStyle(.white)
                .padding(.bottom, 20)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(p.stats) { stat in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stat.caption)
                            .font(DS.Text.statLabel).tracking(DS.Text.statLabelTracking)
                            .foregroundStyle(DS.Colors.onCardTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(stat.value).font(DS.Text.statValue).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                            if let unit = stat.unit { Text(unit).font(DS.Text.statUnit).foregroundStyle(DS.Colors.onCardTertiary) }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .dsGlass(radius: 20)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DS.Layout.cardRadius).fill(DS.Gradients.vehicleCard))
        .padding(.horizontal, DS.Layout.gutter)
    }

    private func details(_ p: VehicleDetailPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Details")
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.textPrimary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(p.tiles) { tile in
                    Button { model?.router.push(tile.route) } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top) {
                                Image(systemName: tile.symbol)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(DS.Colors.accent)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(DS.Colors.accent.opacity(0.149)))
                                Spacer()
                                SettingsRowChevron()
                            }
                            .padding(.bottom, 16)
                            Text(tile.title).font(DS.Text.button).foregroundStyle(.white)
                            Text(tile.subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).lineLimit(1)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .dsSurface()
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("vehicleTile_\(tile.title)")
                }
            }
        }
        .padding(.horizontal, DS.Layout.gutter)
    }

    private func costCard(_ cost: (value: String, bars: [Double?], labels: [String])) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: String(localized: "Cost per month"))
                Text(cost.value).font(DS.Text.headline).tracking(DS.Text.headlineTracking).foregroundStyle(.white)
                Text("avg. last 6 months").font(DS.Text.statCaption).foregroundStyle(DS.Colors.textSecondary)
            }
            .fixedSize()
            BarSeriesChart(values: cost.bars, spacing: 6, cornerRadius: 5)
                .frame(height: 58)
        }
        .padding(20)
        .dsSurface()
        .padding(.horizontal, DS.Layout.gutter)
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            let d = model.dependencies
            viewModel = VehicleDetailsViewModel(
                loadDetail: LoadVehicleDetail(vehicles: d.vehicles, odometer: d.odometer, fuel: d.fuel, services: d.services, documents: d.documents),
                loadAnalytics: LoadVehicleAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services, expenses: d.expenses, odometer: d.odometer, clock: d.clock),
                deleteVehicle: DeleteVehicle(vehicles: d.vehicles, files: d.files),
                vehicleStore: model.vehicles,
                router: model.router,
                format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem)
            )
        }
        await viewModel?.load(vehicleID: vehicleID)
    }
}
