import SwiftUI

/// The tab bar from the Figma design (node 3:4060 "Row"), with the design's 6×6 dots
/// replaced by SF Symbols.
///
/// SCOPE: this file is the ONLY styled component in the project so far. Its tokens are
/// deliberately private — when the full UI stage lands they should be promoted into
/// `Core/DesignKit` rather than copied from here.
///
/// Figma measurements (388pt-wide frame):
///   Row    388×59, horizontal padding 16
///   Card   356×59, radius 26, padding 10/12, vertical glass gradient + 1px hairline
///   Column 69.5×37, vertical, gap 4, padding 6/0
///   Center 52×52, radius 26, diagonal blue gradient + coloured drop shadow
struct CarManagerTabBar: View {
    let selectedTab: AppTab
    let onSelect: (AppTab) -> Void
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.garage)
            addButton
            item(.ai)
            item(.profile)
        }
        .padding(.horizontal, Metrics.cardPaddingH)
        .padding(.vertical, Metrics.cardPaddingV)
        .frame(height: Metrics.barHeight)
        .background(cardBackground)
        .padding(.horizontal, Metrics.rowPaddingH)
    }

    // MARK: - Tab item

    private func item(_ tab: AppTab) -> some View {
        let isSelected = tab == selectedTab
        return Button {
            onSelect(tab)
        } label: {
            VStack(spacing: Metrics.itemSpacing) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: Metrics.iconSize, weight: .semibold))
                    .frame(height: Metrics.iconSize)
                    .foregroundStyle(isSelected ? DS.Colors.accent : DS.Colors.textSecondary)

                Text(tab.label)
                    .font(.system(size: Metrics.labelSize, weight: .semibold))
                    .tracking(Metrics.labelTracking)
                    .lineSpacing(0)
                    .foregroundStyle(isSelected ? DS.Colors.accent : DS.Colors.textSecondary)
            }
            .padding(.vertical, Metrics.itemPaddingV)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tabBar_\(tab.rawValue)")
        .accessibilityLabel(tab.label)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Centre add action

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                // The design's vector is a 14×14 plus with a 2.5pt round-capped stroke.
                .font(.system(size: Metrics.plusGlyphSize, weight: .semibold))
                .foregroundStyle(DS.Colors.textPrimary)
                .frame(width: Metrics.addSize, height: Metrics.addSize)
                // 52×52 at radius 26 — a true circle in the design.
                .background(Circle().fill(DS.Gradients.accentButton))
                .shadow(
                    color: DS.Colors.accent.opacity(0.702),
                    radius: Metrics.addShadowRadius,
                    x: 0,
                    y: Metrics.addShadowY
                )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("tabBarAddButton")
        .accessibilityLabel("Add")
    }

    // MARK: - Glass pill

    private var cardBackground: some View {
        // In Figma the pill is a translucent glass layer over the #090E12 screen. The rest of
        // the app is still unstyled, so the composite is rendered here instead of depending on
        // whatever sits behind it. On the dark screen this is pixel-identical to the design.
        RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .circular)
            .fill(DS.Colors.background)
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .circular)
                    .fill(DS.Gradients.glass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .circular)
                    .strokeBorder(DS.Colors.hairlineStrong, lineWidth: Metrics.cardStrokeWidth)
            )
    }
}

// MARK: - Symbols

private extension AppTab {
    /// The design uses 6×6 dots here; these are the standard Apple symbols that replace them.
    var symbolName: String {
        switch self {
        case .home: "house.fill"
        case .garage: "car.2.fill"
        case .ai: "sparkles"
        case .profile: "person.crop.circle.fill"
        }
    }

    var label: String {
        switch self {
        case .home: "Home"
        case .garage: "Garage"
        case .ai: "AI"
        case .profile: "Profile"
        }
    }
}

// MARK: - Metrics (from Figma node 3:4060). Colours live in DS.

private enum Metrics {
    static let barHeight: CGFloat = 59
    static let rowPaddingH: CGFloat = 16
    static let cardPaddingH: CGFloat = 12
    static let cardPaddingV: CGFloat = 10
    static let cardRadius: CGFloat = 26
    static let cardStrokeWidth: CGFloat = 1

    static let itemSpacing: CGFloat = 4
    static let itemPaddingV: CGFloat = 6
    /// The design's dot is 6×6; an SF Symbol needs more room to read at the same rhythm.
    static let iconSize: CGFloat = 17
    static let labelSize: CGFloat = 10
    static let labelTracking: CGFloat = -0.16

    static let addSize: CGFloat = 52
    static let plusGlyphSize: CGFloat = 19
    static let addShadowRadius: CGFloat = 20
    static let addShadowY: CGFloat = 11
}

