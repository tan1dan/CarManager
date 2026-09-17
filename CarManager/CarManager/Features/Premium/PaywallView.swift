import SwiftUI

/// The paywall, built from Figma node 3:5399.
///
/// The design's vertical rhythm is uneven — its sections butt together with a 0pt gap while
/// their inner elements use 8/10/12, and the two plan cards use 17pt and 18pt padding with
/// their labels 1pt apart. This screen normalises all of that onto the app's own scale:
/// `DS.Layout.sectionSpacing` between blocks, one padding value per card kind, whole-number
/// heights. Colours, type and radii are taken from the design unchanged.
///
/// No View in this file imports StoreKit — it reads `EntitlementStore` through the view model.
struct PaywallView: View {
    let context: PaywallContext
    @Environment(\.appModel) private var model
    @State private var viewModel: PaywallViewModel?

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: DS.Layout.sectionSpacing) {
                    closeRow
                    hero
                    benefits
                    plans
                    callToAction
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .task { await load() }
    }

    // MARK: - Background

    private var background: some View {
        DS.Gradients.vehicleCard
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color(hex: 0x7A66EF).opacity(0.502))
                    .frame(width: 288, height: 288)
                    .blur(radius: 100)
                    .offset(x: 80, y: -120)
            }
            .overlay(alignment: .bottomLeading) {
                Circle()
                    .fill(Color(hex: 0x3782FA).opacity(0.4))
                    .frame(width: 256, height: 256)
                    .blur(radius: 100)
                    .offset(x: -88, y: 80)
            }
            .ignoresSafeArea()
    }

    // MARK: - Sections

    private var closeRow: some View {
        HStack {
            Spacer()
            Button {
                model?.router.clearPendingDestination()
                model?.router.dismissModal()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .dsGlass(radius: 20)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("paywallClose")
            .accessibilityLabel("Close")
        }
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .circular)
                        .fill(DS.Gradients.aiCard)
                )

            Text(presentation.title)
                .font(DS.Text.hero)
                .tracking(DS.Text.heroTracking)
                .foregroundStyle(.white)

            Text(presentation.subtitle)
                .font(DS.Text.subheadlineRegular)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(Color.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var benefits: some View {
        VStack(spacing: Metrics.benefitSpacing) {
            ForEach(presentation.benefits, id: \.self) { benefit in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(DS.Gradients.accentButton))

                    Text(benefit)
                        .font(DS.Text.benefit)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Metrics.cardPaddingH)
                .padding(.vertical, Metrics.benefitPaddingV)
                .dsGlass(radius: DS.Layout.surfaceRadius)
            }
        }
    }

    private var plans: some View {
        HStack(spacing: Metrics.planSpacing) {
            ForEach(presentation.plans) { plan in
                PlanCard(plan: plan, isSelected: plan.id == viewModel?.selectedProduct) {
                    viewModel?.select(plan.id)
                }
            }
        }
        // Room for the "BEST" flag, which overlaps the card's top edge.
        .padding(.top, Metrics.flagOverhang)
    }

    private var callToAction: some View {
        VStack(spacing: Metrics.footerSpacing) {
            Button {
                Task { await viewModel?.purchaseSelected() }
            } label: {
                Group {
                    if viewModel?.isPurchasing == true {
                        ProgressView().tint(.black)
                    } else {
                        Text(presentation.callToAction)
                            .font(DS.Text.rowTitle)
                            .tracking(DS.Text.defaultTracking)
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.ctaHeight)
                .background(Capsule().fill(Color.white))
            }
            .buttonStyle(.plain)
            .disabled(viewModel?.isPurchasing == true)
            .accessibilityIdentifier("paywallSubscribe")

            HStack(spacing: 4) {
                Text(presentation.footerPrefix)
                    .foregroundStyle(Color.white.opacity(0.4))
                Button(presentation.restoreTitle) {
                    Task { await viewModel?.restore() }
                }
                .foregroundStyle(Color.white.opacity(0.7))
                .accessibilityIdentifier("paywallRestore")
            }
            .font(DS.Text.statUnit)
            .tracking(DS.Text.defaultTracking)

            HStack(spacing: 16) {
                Button("Terms of Use") { model?.router.present(.legal(.termsOfUse)) }
                    .accessibilityIdentifier("paywallTerms")
                Button("Privacy Policy") { model?.router.present(.legal(.privacyPolicy)) }
                    .accessibilityIdentifier("paywallPrivacy")
            }
            .font(DS.Text.statUnit)
            .foregroundStyle(Color.white.opacity(0.4))

            if let message = viewModel?.message {
                Text(message)
                    .font(DS.Text.statUnit)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .accessibilityIdentifier("paywallMessage")
            }
        }
    }

    // MARK: - Wiring

    private var presentation: PaywallPresentationModel {
        viewModel?.presentation ?? .placeholder
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            viewModel = PaywallViewModel(
                context: context,
                entitlements: model.entitlements,
                router: model.router
            )
        }
        await viewModel?.load()
    }
}

// MARK: - Plan card

private struct PlanCard: View {
    let plan: PaywallPresentationModel.Plan
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(plan.name)
                    .font(DS.Text.planName)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.8 : 0.6))
                Text(plan.price)
                    .font(DS.Text.price)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(.white)
                Text(plan.caption)
                    .font(DS.Text.statUnit)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(Color.white.opacity(isSelected ? 0.698 : 0.4))
            }
            // One padding value for both cards — the design used 17 on one and 18 on the other.
            .padding(.horizontal, Metrics.cardPaddingH)
            .padding(.vertical, Metrics.planPaddingV)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.planHeight)
            .background(planBackground)
            .overlay(alignment: .top) {
                if plan.isPromoted {
                    Text(plan.flag)
                        .font(DS.Text.flag)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(.black))
                        .offset(y: -Metrics.flagOverhang)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywallPlan_\(plan.id.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder
    private var planBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius, style: .circular)
                .fill(DS.Gradients.accentButton)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius, style: .circular)
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 2)
                )
        } else {
            RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius, style: .circular)
                .fill(DS.Gradients.glass)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius, style: .circular)
                        .strokeBorder(DS.Colors.hairlineStrong, lineWidth: DS.Layout.hairlineWidth)
                )
        }
    }
}

// MARK: - Metrics
//
// Normalised from the design. Where Figma had two values for the same thing, one is used.

private enum Metrics {
    /// The design insets content by 24 — the app's header gutter.
    static let gutter: CGFloat = DS.Layout.headerGutter
    static let cardPaddingH: CGFloat = 16
    static let benefitPaddingV: CGFloat = 12
    static let benefitSpacing: CGFloat = 10
    static let planSpacing: CGFloat = 12
    static let planPaddingV: CGFloat = 16
    /// 101.5 in the design.
    static let planHeight: CGFloat = 102
    /// 54.5 in the design.
    static let ctaHeight: CGFloat = 56
    static let flagOverhang: CGFloat = 9
    static let footerSpacing: CGFloat = 12
}
