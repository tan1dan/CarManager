import SwiftUI

/// Capture → Processing → Result (Figma 34).
struct DamageAnalysisView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: DamageAnalysisViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            if let viewModel {
                switch viewModel.state {
                case .processing:
                    ScanProcessingView(imageData: viewModel.imageData, title: "Looking at the damage…")
                        .accessibilityIdentifier("damageProcessing")
                case .success(let analysis):
                    DamageResultContentView(analysis: analysis, imageData: viewModel.imageData, onClose: close)
                case .failed:
                    ScanMessageView(symbol: "exclamationmark.triangle", title: "Couldn't analyse the photo",
                                    message: viewModel.failure ?? "", primaryTitle: "Try again", primary: viewModel.reset,
                                    secondaryTitle: "Close", secondary: close)
                case .idle:
                    CaptureScreen(title: "Analyse damage", symbol: "car.side",
                                  hint: "Photograph the damaged area",
                                  subhint: "Step back so the whole panel is in frame",
                                  onClose: close, onImage: viewModel.analyze)
                }
            } else if model?.selectedVehicleID == nil {
                ScanMessageView(symbol: "car", title: "Add a vehicle first",
                                message: "Damage is analysed for one of your vehicles.", primaryTitle: "Close", primary: close)
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model, let vehicleID = model.selectedVehicleID else { return }
            let d = model.dependencies
            viewModel = DamageAnalysisViewModel(
                vehicleID: vehicleID,
                analyzeDamage: AnalyzeDamage(vision: d.vision, preprocessor: d.imagePreprocessor,
                                             files: d.files, scans: d.scans, clock: d.clock)
            )
        }
    }

    private func close() { model?.router.dismissFullScreen() }
}

/// Damage analysis result, built from Figma 34.
struct DamageResultContentView: View {
    let analysis: DamageAnalysis
    let imageData: Data?
    let onClose: () -> Void

    private var worst: DamageSeverity {
        let order: [DamageSeverity] = [.structural, .moderate, .cosmetic]
        return order.first { s in analysis.findings.contains { $0.severity == s } } ?? .unknown
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PushedHeader(title: "Damage analysis", onBack: onClose)
                VStack(spacing: 12) {
                    ScanHeroImage(imageData: imageData, symbol: "camera", badge: "ANALYSED")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        Text("\(analysis.findings.count) finding\(analysis.findings.count == 1 ? "" : "s") from this photo")
                            .font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        Eyebrow(text: "What the AI sees")
                        ForEach(Array(analysis.findings.enumerated()), id: \.offset) { _, finding in
                            FindingCard(symbol: finding.severity == .structural ? "exclamationmark.octagon" : "wrench.adjustable",
                                        tone: tone(finding.severity), title: finding.damageType,
                                        subtitle: subtitle(finding))
                        }
                    }
                    InfoBanner(symbol: "info.circle",
                               text: "An estimate from one photo, not a professional assessment or a repair quote.", tone: .neutral)
                        .accessibilityIdentifier("damageDisclaimer")
                    SaveButton(title: "Done", action: onClose)
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
    }

    private var headline: String {
        switch worst {
        case .cosmetic: "Cosmetic damage"
        case .moderate: "Moderate damage"
        case .structural: "Possible structural damage"
        case .unknown: "Damage found"
        }
    }

    private func tone(_ severity: DamageSeverity) -> Tone {
        switch severity {
        case .cosmetic: .success
        case .moderate: .warning
        case .structural: .danger
        case .unknown: .neutral
        }
    }

    /// The suggested repair, plus a cost RANGE when there is one — never a single price.
    private func subtitle(_ finding: DamageFinding) -> String {
        guard let cost = finding.estimatedCost else { return finding.suggestedRepair }
        let format = DisplayFormat()
        return finding.suggestedRepair + " · " + format.money(cost.low, fractionDigits: 0) + "–" + format.money(cost.high, fractionDigits: 0)
    }
}

struct DamageResultView: View {
    let analysisID: DamageAnalysisID
    @Environment(\.appModel) private var model
    var body: some View {
        VStack { PushedHeader(title: "Damage analysis", onBack: { model?.router.pop() }); Spacer() }.dsScreen()
    }
}
