import SwiftUI

/// Camera flows are isolated from the normal navigation stacks in a full-screen cover.
/// The real capture implementation arrives with the UI stage; the FLOW is real now.
struct CameraFlowView: View {
    let purpose: CameraPurpose
    @Environment(\.appModel) private var model

    var body: some View {
        switch purpose {
        case .receipt: ReceiptScanFlowView()
        case .dashboard: DashboardScannerView()
        case .damage: DamageAnalysisView()
        case .plate: PlaceholderCameraView(title: "Scan License Plate")
        case .vehiclePhoto: PlaceholderCameraView(title: "Vehicle Photo")
        }
    }
}

/// Plate and vehicle-photo capture have no processing step yet; the screen says so rather
/// than pretending to read anything.
struct PlaceholderCameraView: View {
    let title: String
    @Environment(\.appModel) private var model

    var body: some View {
        ScanMessageView(symbol: "camera", title: title, message: "This scan arrives in a later update.",
                        primaryTitle: "Close") { model?.router.dismissFullScreen() }
            .background(DS.Colors.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
    }
}

struct DisclaimerAcknowledgementView: View {
    let kind: DisclaimerKind
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("AI Disclaimer")
                Text(kind == .notProfessionalDiagnostics
                     ? "AI analysis does not replace professional diagnostics."
                     : "Repair costs are estimates, not guaranteed prices.")

                Button("I understand") {
                    model?.acknowledgeDisclaimer(kind)
                    model?.router.dismissModal()
                    // Replay whatever the guard intercepted.
                    model?.router.replayPendingDestination()
                }
                .accessibilityIdentifier("disclaimerAccept")

                Button("Cancel") {
                    model?.router.clearPendingDestination()
                    model?.router.dismissModal()
                }
            }
            .navigationTitle("Before you continue")
        }
    }
}
