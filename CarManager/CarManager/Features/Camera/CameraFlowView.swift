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
        case .plate: PlaceholderCameraView(title: String(localized: "Scan License Plate"))
        case .vehiclePhoto: PlaceholderCameraView(title: String(localized: "Vehicle Photo"))
        }
    }
}

/// Plate and vehicle-photo capture have no processing step yet; the screen says so rather
/// than pretending to read anything.
struct PlaceholderCameraView: View {
    let title: String
    @Environment(\.appModel) private var model

    var body: some View {
        ScanMessageView(symbol: "camera", title: title, message: String(localized: "This scan arrives in a later update."),
                        primaryTitle: String(localized: "Close")) { model?.router.dismissFullScreen() }
            .background(DS.Colors.background.ignoresSafeArea())
            .environment(\.colorScheme, .dark)
    }
}

/// Shown once before the first dashboard scan or damage analysis.
struct DisclaimerAcknowledgementView: View {
    let kind: DisclaimerKind
    @Environment(\.appModel) private var model

    private var title: String {
        kind == .notProfessionalDiagnostics ? String(localized: "AI reads the lights, not the car") : String(localized: "Estimates, not quotes")
    }

    private var points: [(String, String)] {
        switch kind {
        case .notProfessionalDiagnostics: [
            ("eye", String(localized: "It sees only what is in the photo — it cannot read fault codes or hear the engine.")),
            ("exclamationmark.triangle", String(localized: "A red or flashing light can mean stop now. When in doubt, stop safely and call a mechanic.")),
            ("lock.shield", String(localized: "The photo is sent to OpenAI for analysis, without location data."))
        ]
        case .costEstimateOnly: [
            ("camera.viewfinder", String(localized: "It judges only what is visible. Hidden or structural damage may be missed.")),
            ("eurosign.circle", String(localized: "Costs are rough ranges for an independent workshop, never a quote.")),
            ("lock.shield", String(localized: "Photos are sent to OpenAI for analysis, without location data."))
        ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(DS.Gradients.aiCard))
                .padding(.top, 32)
            Text(title).font(DS.Text.title).tracking(DS.Text.titleTracking).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(points, id: \.1) { symbol, text in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Colors.accent).frame(width: 24)
                        Text(text).font(DS.Text.body).foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Button("How your photos are handled") { model?.router.present(.legal(.privacyPolicy)) }
                .font(DS.Text.caption.weight(.semibold))
                .foregroundStyle(DS.Colors.accent)
            Spacer()
            SaveButton(title: String(localized: "I understand")) {
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
            .font(DS.Text.button).foregroundStyle(DS.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, DS.Layout.gutter)
        .background(DS.Colors.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
    }
}
