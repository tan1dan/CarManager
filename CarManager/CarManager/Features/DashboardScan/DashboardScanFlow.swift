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
                    ScanProcessingView(imageData: viewModel.imageData, title: String(localized: "Looking at the lights…"))
                        .accessibilityIdentifier("dashboardProcessing")
                case .success(let scan):
                    DashboardScanResultContentView(scan: scan, imageData: viewModel.imageData, onClose: close) { ask(scan) }
                case .failed:
                    ScanMessageView(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't analyse the photo"),
                                    message: viewModel.failure ?? "", primaryTitle: String(localized: "Try again"), primary: viewModel.reset,
                                    secondaryTitle: String(localized: "Close"), secondary: close)
                case .idle:
                    CaptureScreen(title: String(localized: "Scan dashboard"), symbol: "gauge.with.dots.needle.33percent",
                                  hint: String(localized: "Point at the warning light"),
                                  subhint: String(localized: "AI will identify the symbol and explain it"),
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

    /// The question a new chat starts with: the lights already written in, ready to send.
    static func question(for scan: DashboardScan) -> String {
        let lights = scan.findings.map { finding in
            finding.recommendedAction.isEmpty ? finding.warningName : "\(finding.warningName) (\(finding.recommendedAction))"
        }
        return lights.isEmpty
            ? String(localized: "A warning light is on on my dashboard. How can I tell what it means?")
            : String(localized: "These warning lights are on: \(lights.joined(separator: "; ")). What should I check, and is it safe to keep driving?")
    }

    private func ask(_ scan: DashboardScan) {
        model?.pendingAIQuestion = Self.question(for: scan)
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
                PushedHeader(title: String(localized: "Dashboard scan"), onBack: onClose)
                VStack(spacing: 12) {
                    ScanHeroImage(imageData: imageData, symbol: "gauge.with.dots.needle.33percent",
                                  badge: scan.findings.isEmpty ? String(localized: "NO LIGHTS FOUND")
                                         : String(localized: "\(scan.findings.count) LIGHTS FOUND"))
                    if let summary = scan.summary, !summary.isEmpty {
                        Text(summary).font(DS.Text.subheadlineRegular).foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(scan.findings.enumerated()), id: \.offset) { _, finding in
                        FindingCard(symbol: symbol(finding.severity), tone: tone(finding.severity),
                                    title: finding.warningName, subtitle: finding.recommendedAction,
                                    detail: finding.likelyCauses.isEmpty ? nil : String(localized: "Likely: \(finding.likelyCauses.prefix(3).joined(separator: ", "))"),
                                    badge: badge(finding.drivingSafety))
                    }
                    // The disclaimer is part of the model, not just UI copy.
                    InfoBanner(symbol: "info.circle", text: String(localized: "Not professional diagnostics. When in doubt, see a mechanic."), tone: .neutral)
                        .accessibilityIdentifier("dashboardDisclaimer")
                    SaveButton(title: scan.findings.isEmpty ? String(localized: "Ask AI") : String(localized: "Ask AI about these"), symbol: "sparkles", action: onAsk)
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
    }

    /// Only the two answers a driver must not miss get a badge.
    private func badge(_ safety: DrivingSafetyAssessment) -> (String, Tone)? {
        switch safety {
        case .doNotDrive: (String(localized: "Don't drive"), .danger)
        case .cautionAdvised: (String(localized: "Drive with care"), .warning)
        case .likelySafe, .unknown: nil
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
                    // A filled photo overflows its frame; clipping hides that but does not stop the
                    // overflow catching taps (it sat over the Back button).
                    .allowsHitTesting(false)
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
        .clipShape(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius))
        .contentShape(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius))
        .overlay(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).strokeBorder(DS.Colors.hairline))
    }
}

/// One AI finding: tinted icon, title, one line of advice.
struct FindingCard: View {
    let symbol: String
    let tone: Tone
    let title: String
    let subtitle: String
    var detail: String?
    var badge: (String, Tone)?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(tone.color.opacity(0.16)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(DS.Text.rowTitle).foregroundStyle(.white)
                if !subtitle.isEmpty {
                    Text(subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail {
                    Text(detail).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let badge { Chip(text: badge.0, tone: badge.1).padding(.top, 2) }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .dsSurface(radius: 20)
        .accessibilityElement(children: .combine)
    }
}

/// A saved dashboard scan, opened from history.
struct DashboardScanResultView: View {
    let scanID: DashboardScanID
    @Environment(\.appModel) private var model
    @State private var loaded: (DashboardScan, Data?)?
    @State private var missing = false

    var body: some View {
        Group {
            if let (scan, image) = loaded {
                DashboardScanResultContentView(scan: scan, imageData: image, onClose: { model?.router.pop() }) {
                    model?.pendingAIQuestion = DashboardScannerView.question(for: scan)
                    model?.router.push(.aiChat(nil))
                }
            } else if missing {
                VStack {
                    PushedHeader(title: String(localized: "Dashboard scan"), onBack: { model?.router.pop() })
                    EmptyStateView(symbol: "trash", title: String(localized: "Scan not found"), message: String(localized: "It may have been deleted on another device."))
                    Spacer()
                }
            } else {
                ProgressView().tint(DS.Colors.textSecondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dsScreen()
        .task {
            guard loaded == nil, let model else { return }
            let d = model.dependencies
            guard let scan = try? await d.scans.dashboardScan(id: scanID) else { missing = true; return }
            // The photo lives on the device that took it; on another device the result shows without it.
            loaded = (scan, try? await d.files.read(scan.imageRef))
        }
    }
}
