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

struct PlaceholderCameraView: View {
    let title: String
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(title)
                Text("Camera placeholder")
            }
            .navigationTitle(title)
            .toolbar {
                Button("Close") { model?.router.dismissFullScreen() }
                    .accessibilityIdentifier("cameraClose")
            }
        }
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
