import SwiftUI

/// Scan → Processing → Result. The result is an informational estimate by construction:
/// `DashboardScan.disclaimer` is non-optional, and `drivingSafety` defaults to `.unknown`.
struct DashboardScannerView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: DashboardScanViewModel?

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel?.state {
                case .processing:
                    DashboardScanProcessingView()
                case .success(let scan):
                    DashboardScanResultContentView(scan: scan)
                case .failed(let error):
                    VStack {
                        Text("Scan failed")
                        Text(error.messageKey)
                        Button("Retry") { viewModel?.reset() }
                    }
                default:
                    VStack(spacing: 12) {
                        Text("Scan Dashboard")
                        Text("Point at the warning light")
                        Button("Capture") { viewModel?.capture() }
                            .accessibilityIdentifier("dashboardCapture")
                    }
                }
            }
            .navigationTitle("Scan Dashboard")
            .toolbar {
                Button("Close") { model?.router.dismissFullScreen() }
                    .accessibilityIdentifier("dashboardClose")
            }
        }
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = DashboardScanViewModel(
                vehicleID: model.selectedVehicleID,
                scanDashboard: ScanDashboard(
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

struct DashboardScanProcessingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Dashboard Scan Processing")
        }
        .accessibilityIdentifier("dashboardProcessing")
    }
}

struct DashboardScanResultContentView: View {
    let scan: DashboardScan

    var body: some View {
        List {
            Text("Dashboard Scan Result")
            ForEach(Array(scan.findings.enumerated()), id: \.offset) { _, finding in
                VStack(alignment: .leading) {
                    Text(finding.warningName)
                    Text("Severity: \(finding.severity.rawValue)")
                    Text("Driving safety: \(finding.drivingSafety.rawValue)")
                }
            }
            // The disclaimer is part of the model, not just UI copy.
            Section("Disclaimer") {
                Text(scan.disclaimer.textKey).accessibilityIdentifier("dashboardDisclaimer")
            }
        }
    }
}

/// Reached from a route when the result is opened later.
struct DashboardScanResultView: View {
    let scanID: DashboardScanID
    var body: some View { Text("Dashboard Scan Result").navigationTitle("Scan result") }
}
