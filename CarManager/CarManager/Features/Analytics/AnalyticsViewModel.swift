import Foundation
import Observation

/// Display values for Analytics (Figma 38).
struct AnalyticsPresentation: Equatable, Sendable {
    struct Spend: Equatable, Sendable {
        var total: String
        var change: String?
        var changeTone: Tone
        var bars: [Double?]
        var labels: [String]
        var tag: String?
    }
    struct Consumption: Equatable, Sendable {
        var value: String
        var unit: String
        var best: String?
        var points: [Double?]
    }
    struct Slice: Equatable, Sendable, Identifiable {
        var id: String { name }
        var name: String
        var share: String
        var amount: String
        var value: Double
        var colorIndex: Int
    }
    struct CostPerDistance: Equatable, Sendable {
        var title: String
        var value: String
        var change: String?
        var changeTone: Tone
    }
    var spend: Spend
    var consumption: Consumption?
    var slices: [Slice]
    var donutCenter: String
    var costPerDistance: CostPerDistance?
}

@MainActor
@Observable
final class AnalyticsViewModel {
    enum Period: Hashable { case sixMonths, year, allTime }

    private(set) var state: ViewState<AnalyticsPresentation> = .idle
    private(set) var period: Period

    private let loadAnalytics: LoadPeriodAnalytics
    private let format: DisplayFormat

    init(loadAnalytics: LoadPeriodAnalytics, format: DisplayFormat, period: Period) {
        self.loadAnalytics = loadAnalytics
        self.format = format
        self.period = period
    }

    func select(_ period: Period, vehicleID: VehicleID?) async {
        self.period = period
        await load(vehicleID: vehicleID)
    }

    func load(vehicleID: VehicleID?) async {
        if case .loaded = state {} else { state = .loading }
        let months: Int? = switch period {
        case .sixMonths: 6
        case .year: 12
        case .allTime: nil
        }
        do {
            let analytics = try await loadAnalytics(vehicleID: vehicleID, months: months)
            state = analytics.total == 0 && analytics.averageConsumption == nil ? .empty : .loaded(present(analytics))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func present(_ a: PeriodAnalytics) -> AnalyticsPresentation {
        // Long periods are shown per year; a 40-bar chart says nothing.
        let byYear = a.monthlySpend.count > 12
        let buckets: [(label: String, value: Decimal)]
        if byYear {
            var years: [(Int, Decimal)] = []
            for month in a.monthlySpend {
                let year = format.calendar.component(.year, from: month.monthStart)
                if let last = years.last, last.0 == year { years[years.count - 1].1 += month.value } else { years.append((year, month.value)) }
            }
            buckets = years.map { (String($0.0), $0.1) }
        } else {
            let narrow = a.monthlySpend.count > 6
            buckets = a.monthlySpend.map { (format.month($0.monthStart, narrow: narrow), $0.value) }
        }
        let previousLabel = a.monthlySpend.dropLast().last.map { format.month($0.monthStart) }
        let spendChange = byYear ? nil : a.lastMonthChange
        let spend = AnalyticsPresentation.Spend(
            total: format.money(a.total, a.currency, fractionDigits: 0),
            change: spendChange.flatMap { change in previousLabel.map { String(localized: "\(format.percentChange(change)) vs \($0)") } },
            changeTone: (spendChange ?? 0) > 0.005 ? .danger : (spendChange ?? 0) < -0.005 ? .success : .neutral,
            bars: buckets.map { $0.value.doubleValue },
            labels: buckets.map(\.label),
            tag: buckets.last.map { format.money($0.value, a.currency, fractionDigits: 0) }
        )

        let consumption = a.averageConsumption.map { average in
            AnalyticsPresentation.Consumption(
                value: format.consumption(average), unit: format.consumptionUnit,
                best: a.bestConsumption.map { String(localized: "Best \(format.consumption($0.value)) · \(format.month($0.monthStart))") },
                points: a.monthlyConsumption.map(\.value)
            )
        }

        let total = a.total.doubleValue
        var slices: [AnalyticsPresentation.Slice] = []
        if total > 0 {
            let named = a.categories.count > 4 ? Array(a.categories.prefix(3)) : a.categories
            let rest = a.categories.dropFirst(named.count).reduce(Decimal(0)) { $0 + $1.amount }
            var parts = named.map { ($0.category.displayName, $0.amount) }
            if rest > 0 { parts.append((String(localized: "Other"), rest)) }
            slices = parts.enumerated().map { index, part in
                .init(name: part.0, share: "\(Int((part.1.doubleValue / total * 100).rounded()))%",
                      amount: format.money(part.1, a.currency, fractionDigits: 0),
                      value: part.1.doubleValue, colorIndex: index)
            }
        }

        let perDistance = a.costPerKilometer.map { perKm -> AnalyticsPresentation.CostPerDistance in
            let metric = format.unitSystem == .metric
            let value = metric ? perKm : perKm * Decimal(1.609344)
            let change = a.costPerKilometerChange
            let changeText = change.flatMap { c -> String? in
                let percent = Int((abs(c) * 100).rounded())
                guard percent > 0 else { return nil }
                return c < 0 ? String(localized: "\(percent)% cheaper than the period before")
                         : String(localized: "\(percent)% dearer than the period before")
            }
            return .init(title: metric ? String(localized: "Cost per kilometre") : String(localized: "Cost per mile"),
                         value: format.money(value, a.currency, fractionDigits: 2),
                         change: changeText, changeTone: (change ?? 0) < 0 ? .success : .warning)
        }

        return AnalyticsPresentation(
            spend: spend, consumption: consumption, slices: slices,
            donutCenter: format.money(a.total, a.currency, fractionDigits: 0), costPerDistance: perDistance
        )
    }
}
