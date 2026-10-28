import SwiftUI

/// Garage, built from Figma node 3:4196.
///
/// The primary vehicle is an expanded card; every other vehicle is a dimmed collapsed row,
/// matching the design's 70% opacity treatment.
struct GarageView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: GarageViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    switch viewModel?.state {
                    case .loading, .idle, .none:
                        ProgressView().tint(DS.Colors.textSecondary).padding(.top, 40)
                    case .failed(let error):
                        failure(error)
                    case .empty:
                        emptyState
                        addAnotherButton
                    case .loaded:
                        content
                        addAnotherButton
                    }
                }
                .padding(.bottom, DS.Layout.tabBarReservedHeight)
                // The new primary card slides up to the top.
                .animation(.snappy, value: presentation.cards.map(\.id))
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: model?.vehicles.revision) { Task { await load() } }
        // Stopgap until the repository change feed lands (architecture Phase 4).
        .onChange(of: model?.router.activeModal) { _, modal in
            if modal == nil { Task { await load() } }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .bottom) {
            Text(presentation.title)
                .font(DS.Text.title)
                .tracking(DS.Text.titleTracking)
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer(minLength: 12)
            addButton
        }
        .padding(.horizontal, DS.Layout.headerGutter)
        .padding(.top, 16)
    }

    private var addButton: some View {
        Button {
            model?.router.present(.vehicleEditor(.create))
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(DS.Gradients.accentButton))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("garageAddToolbar")
        .accessibilityLabel("Add vehicle")
    }

    @ViewBuilder
    private var content: some View {
        ForEach(presentation.cards) { card in
            VehicleCardView(card: card, onTap: {
                model?.router.push(.vehicleDetail(card.id), in: .garage)
            }, onMakePrimary: { makePrimary(card.id) })
            .contextMenu {
                if !card.isPrimary {
                    Button("Make primary", systemImage: "star") { makePrimary(card.id) }
                }
                Button("Open", systemImage: "car") { model?.router.push(.vehicleDetail(card.id), in: .garage) }
            }
            .padding(.horizontal, DS.Layout.gutter)
            .accessibilityIdentifier("garageVehicle_\(card.id.raw.uuidString)")
        }
        if presentation.cards.count > 1 {
            Text("The primary car is the one Home, AI chat and quick add use. Tap “Make primary” on any car to switch.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Layout.gutter)
        }
    }

    /// The new primary card slides to the top; Home and every other screen follow.
    private func makePrimary(_ id: VehicleID) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await model?.vehicles.select(id)
            await load()
        }
    }

    private var addAnotherButton: some View {
        Button {
            model?.router.present(.vehicleEditor(.create))
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add another vehicle")
                    .font(DS.Text.button)
                    .tracking(DS.Text.defaultTracking)
            }
            .foregroundStyle(DS.Colors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 63)
            .dsSurface()
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Layout.gutter)
        .accessibilityIdentifier("garageAddVehicle")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No vehicles yet")
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.textPrimary)
            Text("Add your first vehicle to start tracking it.")
                .font(DS.Text.caption)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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

    private var presentation: GaragePresentationModel {
        viewModel?.presentation ?? .empty
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            viewModel = GarageViewModel(
                loadGarage: LoadGarage(vehicles: model.dependencies.vehicles),
                formatter: GarageFormatter(unitSystem: model.dependencies.preferences.unitSystem)
            )
        }
        await viewModel?.load()
    }
}

// MARK: - Vehicle card

/// Every car looks the same. The primary one carries a filled "Primary" badge; the others show
/// a "Make primary" button in the same place, so switching is one obvious tap.
private struct VehicleCardView: View {
    let card: GaragePresentationModel.VehicleCard
    let onTap: () -> Void
    let onMakePrimary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.subtitle)
                        .font(DS.Text.subheadline)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.onCardSecondary)
                    Text(card.name)
                        .font(DS.Text.headline)
                        .tracking(DS.Text.headlineTracking)
                        .foregroundStyle(DS.Colors.onCardPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                badge
            }

            HStack(spacing: 8) {
                ForEach(card.stats) { stat in
                    GarageStatChip(stat: stat)
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
                        .strokeBorder(card.isPrimary ? DS.Colors.accent.opacity(0.55) : Color.white.opacity(0.051),
                                      lineWidth: card.isPrimary ? 1.5 : DS.Layout.hairlineWidth)
                )
        )
        .contentShape(.rect)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(card.name), \(card.subtitle)\(card.isPrimary ? ", primary" : "")")
        .accessibilityAction(named: "Open", onTap)
    }

    @ViewBuilder
    private var badge: some View {
        if card.isPrimary {
            Label("Primary", systemImage: "star.fill")
                .font(DS.Text.chip)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(DS.Gradients.accentButton))
                .accessibilityLabel("Primary vehicle")
        } else {
            Button(action: onMakePrimary) {
                Label("Make primary", systemImage: "star")
                    .font(DS.Text.chip)
                    .foregroundStyle(DS.Colors.onCardPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .dsGlass(radius: 14)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("garageMakePrimary")
        }
    }
}

private struct GarageStatChip: View {
    let stat: GaragePresentationModel.Stat

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
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsGlass(radius: DS.Layout.surfaceRadius)
    }
}
