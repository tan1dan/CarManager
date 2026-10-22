import SwiftUI

/// Scan → Processing → Result (Figma 17 → 46). The result is an informational estimate by
/// construction: `DashboardScan.disclaimer` is non-optional, and `drivingSafety` defaults to `.unknown`.
struct DashboardScannerView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: DashboardScanViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel {
                switch viewModel.state {
                case .processing:
                    ScanProcessingView(imageData: viewModel.imageData, title: "Looking at the lights…")
                        .accessibilityIdentifier("dashboardProcessing")
                case .success(let scan):
                    DashboardScanResultContentView(scan: scan, imageData: viewModel.imageData, onClose: close, onAsk: ask)
                case .failed:
                    ScanMessageView(symbol: "exclamationmark.triangle", title: "Couldn't analyse the photo",
                                    message: viewModel.failure ?? "", primaryTitle: "Try again", primary: viewModel.reset,
                                    secondaryTitle: "Close", secondary: close)
                case .idle:
                    CaptureScreen(title: "Scan dashboard", symbol: "gauge.with.dots.needle.33percent",
                                  hint: "Point at the warning light",
                                  subhint: "AI will identify the symbol and explain it",
                                  onClose: close, onImage: viewModel.analyze)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let d = model.dependencies
            viewModel = DashboardScanViewModel(
                vehicleID: model.selectedVehicleID,
                scanDashboard: ScanDashboard(vision: d.vision, preprocessor: d.imagePreprocessor,
                                             files: d.files, scans: d.scans, clock: d.clock)
            )
        }
    }

    private func close() { model?.router.dismissFullScreen() }

    private func ask() {
        model?.router.dismissFullScreen()
        model?.router.select(tab: .ai)
        model?.router.push(.aiChat(nil), in: .ai)
    }
}

/// Dashboard scan result, built from Figma 46.
struct DashboardScanResultContentView: View {
    let scan: DashboardScan
    let imageData: Data?
    let onClose: () -> Void
    let onAsk: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PushedHeader(title: "Dashboard scan", onBack: onClose)
                VStack(spacing: 12) {
                    ScanHeroImage(imageData: imageData, symbol: "gauge.with.dots.needle.33percent",
                                  badge: scan.findings.isEmpty ? "NO LIGHTS FOUND"
                                         : "\(scan.findings.count) LIGHT\(scan.findings.count == 1 ? "" : "S") FOUND")
                    ForEach(Array(scan.findings.enumerated()), id: \.offset) { _, finding in
                        FindingCard(symbol: symbol(finding.severity), tone: tone(finding.severity),
                                    title: finding.warningName, subtitle: finding.recommendedAction)
                    }
                    // The disclaimer is part of the model, not just UI copy.
                    InfoBanner(symbol: "info.circle", text: "Not professional diagnostics. When in doubt, see a mechanic.", tone: .neutral)
                        .accessibilityIdentifier("dashboardDisclaimer")
                    SaveButton(title: "Ask AI about these", symbol: "sparkles", action: onAsk)
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
    }

    private func tone(_ severity: FindingSeverity) -> Tone {
        switch severity {
        case .informational: .success
        case .soon: .warning
        case .urgent, .stopDriving: .danger
        }
    }

    private func symbol(_ severity: FindingSeverity) -> String {
        switch severity {
        case .informational: "info.circle"
        case .soon: "exclamationmark.triangle"
        case .urgent, .stopDriving: "exclamationmark.octagon"
        }
    }
}

/// The photo card at the top of a scan result, with a small status badge.
struct ScanHeroImage: View {
    let imageData: Data?
    let symbol: String
    let badge: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(DS.Colors.surface)
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius))
            } else {
                Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Color.white.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(badge)
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).frame(height: 22)
                .background(Capsule().fill(DS.Colors.accent))
                .padding(14)
        }
        .frame(height: 160)
        .overlay(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).strokeBorder(DS.Colors.hairline))
    }
}

/// One AI finding: tinted icon, title, one line of advice.
struct FindingCard: View {
    let symbol: String
    let tone: Tone
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tone.color.opacity(0.16)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(DS.Text.rowTitle).foregroundStyle(.white)
                Text(subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .dsSurface(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

/// Reached from a route when the result is opened later. Scans are kept only for the session.
struct DashboardScanResultView: View {
    let scanID: DashboardScanID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: "Dashboard scan", onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}
