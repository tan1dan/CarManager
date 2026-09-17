import SwiftUI

struct AnalyticsView: View {
    let vehicleID: VehicleID?
    let period: AnalyticsPeriod
    @Environment(\.appModel) private var model
    @State private var selectedPeriod: AnalyticsPeriod

    init(vehicleID: VehicleID?, period: AnalyticsPeriod) {
        self.vehicleID = vehicleID
        self.period = period
        _selectedPeriod = State(initialValue: period)
    }

    var body: some View {
        List {
            Text("Analytics")

            // The period selector is feature-local state, not global.
            Picker("Period", selection: $selectedPeriod) {
                ForEach(AnalyticsPeriod.allCases, id: \.self) { period in
                    Text(period.titleKey).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analyticsPeriodPicker")

            Section("Sections") {
                Button("Consumption") { push(.consumption) }
                    .accessibilityIdentifier("analyticsConsumption")
                Button("Costs") { push(.costs) }
                Button("Categories") { push(.categories) }
                Button("Cost of Ownership") { push(.ownership) }
            }

            // Free tier keeps all raw records; only the analytics window is clamped.
            if let model, model.featureGate.clampedPeriod(selectedPeriod) != selectedPeriod {
                Section {
                    Button("Unlock full history") {
                        model.router.present(.paywall(.feature(.advancedAnalytics)))
                    }
                    .accessibilityIdentifier("analyticsUpgrade")
                }
            }
        }
        .navigationTitle("Analytics")
    }

    private func push(_ section: AnalyticsSection) {
        model?.router.push(.analyticsSection(section))
    }
}

struct AnalyticsSectionView: View {
    let section: AnalyticsSection
    var body: some View {
        Text("Analytics · \(section.rawValue)")
            .navigationTitle(section.rawValue.capitalized)
    }
}
