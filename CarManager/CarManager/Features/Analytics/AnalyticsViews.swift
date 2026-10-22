import SwiftUI

/// Analytics, built from Figma 38.
struct AnalyticsView: View {
    let vehicleID: VehicleID?
    let period: AnalyticsPeriod
    @Environment(\.appModel) private var model
    @State private var viewModel: AnalyticsViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PushedHeader(title: "Analytics", onBack: { model?.router.pop() })
                VStack(spacing: 16) {
                    if let viewModel {
                        SegmentedPill(options: [(.sixMonths, "6 months"), (.year, "Year"), (.allTime, "All time")],
                                      selection: Binding(get: { viewModel.period }, set: select))
                            .accessibilityIdentifier("analyticsPeriodPicker")
                    }
                    content
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .task {
            guard let model else { return }
            if viewModel == nil {
                let d = model.dependencies
                viewModel = AnalyticsViewModel(
                    loadAnalytics: LoadPeriodAnalytics(vehicles: d.vehicles, fuel: d.fuel, services: d.services,
                                                       expenses: d.expenses, odometer: d.odometer, clock: d.clock),
                    format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                    period: period == .year ? .year : .sixMonths
                )
            }
            await viewModel?.load(vehicleID: vehicleID)
        }
    }

    /// Free tier keeps every record; only the all-time window is a Premium view.
    private func select(_ period: AnalyticsViewModel.Period) {
        if period == .allTime, let model, model.featureGate.clampedPeriod(.allTime) != .allTime {
            model.router.present(.paywall(.feature(.advancedAnalytics)))
            return
        }
        Task { await viewModel?.select(period, vehicleID: vehicleID) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let p):
            spendCard(p.spend)
            if let consumption = p.consumption { consumptionCard(consumption) }
            if !p.slices.isEmpty { donutCard(p) }
            if let perDistance = p.costPerDistance { costCard(perDistance) }
        case .empty:
            EmptyStateView(symbol: "chart.bar", title: "Nothing to analyse yet",
                           message: "Log fuel, service or expenses and the charts fill in by themselves.")
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load analytics",
                           message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }

    private func cardHeader(_ title: String, value: String, unit: String? = nil, chip: String?, tone: Tone) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: title)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value).font(DS.Text.headline).tracking(DS.Text.headlineTracking).foregroundStyle(.white).monospacedDigit()
                    if let unit { Text(unit).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary) }
                }
            }
            Spacer()
            if let chip { Chip(text: chip, tone: tone) }
        }
    }

    private func spendCard(_ spend: AnalyticsPresentation.Spend) -> some View {
        VStack(spacing: 20) {
            cardHeader("Spend per month", value: spend.total, chip: spend.change, tone: spend.changeTone)
            BarSeriesChart(values: spend.bars, labels: spend.labels, spacing: spend.bars.count > 6 ? 6 : 12,
                           cornerRadius: spend.bars.count > 6 ? 5 : 8, highlightTag: spend.tag)
                .frame(height: 170)
        }
        .padding(20)
        .dsSurface()
    }

    private func consumptionCard(_ c: AnalyticsPresentation.Consumption) -> some View {
        VStack(spacing: 16) {
            cardHeader("Consumption", value: c.value, unit: c.unit, chip: c.best, tone: .success)
            TrendLineChart(values: c.points, color: DS.Colors.series[2], showsAxisLabels: false)
                .frame(height: 80)
        }
        .padding(20)
        .dsSurface()
    }

    private func donutCard(_ p: AnalyticsPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Where it goes")
            HStack(spacing: 24) {
                DonutChart(segments: p.slices.map { .init(id: $0.name, value: $0.value, color: color($0.colorIndex)) },
                           center: p.donutCenter)
                    .frame(width: 120, height: 120)
                VStack(spacing: 10) {
                    ForEach(p.slices) { slice in
                        HStack(alignment: .top, spacing: 10) {
                            Circle().fill(color(slice.colorIndex)).frame(width: 9, height: 9).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(slice.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                Text(slice.share).font(DS.Text.statCaption).foregroundStyle(DS.Colors.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Text(slice.amount).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(20)
        .dsSurface()
    }

    private func costCard(_ c: AnalyticsPresentation.CostPerDistance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(text: c.title)
            Text(c.value).font(.system(size: 28, weight: .bold)).tracking(-0.7).foregroundStyle(.white).monospacedDigit()
            if let change = c.change {
                Label(change, systemImage: c.changeTone == .success ? "arrow.down.right" : "arrow.up.right")
                    .font(DS.Text.caption)
                    .foregroundStyle(c.changeTone.color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .dsSurface()
    }

    private func color(_ index: Int) -> Color { DS.Colors.series[index % DS.Colors.series.count] }
}

struct AnalyticsSectionView: View {
    let section: AnalyticsSection
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: section.rawValue.capitalized, onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}
