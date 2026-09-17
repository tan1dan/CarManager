import SwiftUI

struct DamageAnalysisView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: DamageAnalysisViewModel?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel?.state {
                case .processing:
                    DamageProcessingView()
                case .success(let analysis):
                    DamageResultContentView(analysis: analysis)
                case .failed(let error):
                    VStack {
                        Text("Analysis failed")
                        Text(error.messageKey)
                        Button("Retry") { viewModel?.reset() }
                    }
                default:
                    VStack(spacing: 12) {
                        Text("Damage Analysis")
                        Button("Select or capture photo") { viewModel?.analyze() }
                            .accessibilityIdentifier("damageCapture")
                    }
                }
            }
            .navigationTitle("Analyze Damage")
            .toolbar {
                Button("Close") { model?.router.dismissFullScreen() }
                    .accessibilityIdentifier("damageClose")
            }
        }
        .task {
            guard viewModel == nil, let model, let vehicleID = model.selectedVehicleID else { return }
            viewModel = DamageAnalysisViewModel(
                vehicleID: vehicleID,
                analyzeDamage: AnalyzeDamage(
                    vision: model.dependencies.vision,
                    preprocessor: model.dependencies.imagePreprocessor,
                    files: model.dependencies.files,
                    scans: model.dependencies.scans,
                    clock: model.dependencies.clock
                )
            )
        }
    }
}

struct DamageProcessingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Damage Processing")
        }
        .accessibilityIdentifier("damageProcessing")
    }
}

struct DamageResultContentView: View {
    let analysis: DamageAnalysis

    var body: some View {
        List {
            Text("Damage Result")
            ForEach(Array(analysis.findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading) {
                    Text(finding.damageType)
                    Text("Severity: \(finding.severity.rawValue)")
                    // Always a RANGE — there is no scalar price field in the model.
                    if let cost = finding.estimatedCost {
                        Text(verbatim: "Estimate: \(cost.low.amount) – \(cost.high.amount) \(cost.high.currency.iso4217)")
                    }
                }
            }
            Section("Disclaimer") {
                Text(analysis.disclaimer.textKey).accessibilityIdentifier("damageDisclaimer")
            }
        }
    }
}

struct DamageResultView: View {
    let analysisID: DamageAnalysisID
    var body: some View { Text("Damage Result").navigationTitle("Damage analysis") }
}
