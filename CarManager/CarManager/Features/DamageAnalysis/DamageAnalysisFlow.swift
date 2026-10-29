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
                    ScanProcessingView(imageData: viewModel.imageData, title: String(localized: "Looking at the damage…"))
                        .accessibilityIdentifier("damageProcessing")
                case .success(let analysis):
                    DamageResultContentView(analysis: analysis, imageData: viewModel.imageData, onClose: close)
                case .failed:
                    ScanMessageView(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't analyse the photo"),
                                    message: viewModel.failure ?? "", primaryTitle: String(localized: "Try again"), primary: viewModel.reset,
                                    secondaryTitle: String(localized: "Close"), secondary: close)
                case .idle:
                    CaptureScreen(title: String(localized: "Analyse damage"), symbol: "car.side",
                                  hint: String(localized: "Photograph the damaged area"),
                                  subhint: String(localized: "Step back so the whole panel is in frame"),
                                  onClose: close, onImage: viewModel.analyze)
                }
            } else if model?.selectedVehicleID == nil {
                ScanMessageView(symbol: "car", title: String(localized: "Add a vehicle first"),
                                message: String(localized: "Damage is analysed for one of your vehicles."), primaryTitle: String(localized: "Close"), primary: close)
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
                PushedHeader(title: String(localized: "Damage analysis"), onBack: onClose)
                VStack(spacing: 12) {
                    ScanHeroImage(imageData: imageData, symbol: "camera", badge: String(localized: "ANALYSED"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                        Text(analysis.summary.flatMap { $0.isEmpty ? nil : $0 }
                             ?? String(localized: "\(analysis.findings.count) findings from this photo"))
                            .font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        Eyebrow(text: String(localized: "What the AI sees"))
                        ForEach(Array(analysis.findings.enumerated()), id: \.offset) { _, finding in
                            FindingCard(symbol: finding.severity == .structural ? "exclamationmark.octagon" : "wrench.adjustable",
                                        tone: tone(finding.severity), title: finding.damageType,
                                        subtitle: subtitle(finding),
                                        detail: finding.cosmeticRepairPossible == true ? String(localized: "A cosmetic repair is likely enough") : nil)
                        }
                    }
                    InfoBanner(symbol: "info.circle",
                               text: String(localized: "An estimate from one photo, not a professional assessment or a repair quote."), tone: .neutral)
                        .accessibilityIdentifier("damageDisclaimer")
                    SaveButton(title: String(localized: "Done"), action: onClose)
                }
                .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 24)
        }
    }

    private var headline: String {
        if analysis.findings.isEmpty { return String(localized: "No damage found") }
        return switch worst {
        case .cosmetic: String(localized: "Cosmetic damage")
        case .moderate: String(localized: "Moderate damage")
        case .structural: String(localized: "Possible structural damage")
        case .unknown: String(localized: "Damage found")
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

/// A saved damage analysis, opened from history.
struct DamageResultView: View {
    let analysisID: DamageAnalysisID
    @Environment(\.appModel) private var model
    @State private var loaded: (DamageAnalysis, Data?)?
    @State private var missing = false

    var body: some View {
        Group {
            if let (analysis, image) = loaded {
                DamageResultContentView(analysis: analysis, imageData: image) { model?.router.pop() }
            } else if missing {
                VStack {
                    PushedHeader(title: String(localized: "Damage analysis"), onBack: { model?.router.pop() })
                    EmptyStateView(symbol: "trash", title: String(localized: "Analysis not found"), message: String(localized: "It may have been deleted on another device."))
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
            guard let analysis = try? await d.scans.damageAnalysis(id: analysisID) else { missing = true; return }
            let image: Data? = if let ref = analysis.imageRefs.first { try? await d.files.read(ref) } else { nil }
            loaded = (analysis, image)
        }
    }
}
