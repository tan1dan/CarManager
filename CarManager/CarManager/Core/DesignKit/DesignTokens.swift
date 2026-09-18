import SwiftUI

/// Design tokens extracted from the Figma file (page "AI Car Assistant").
///
/// These were private to `CarManagerTabBar` while it was the only styled component. Two
/// screens now share them, so they live here. Presentation layer only — nothing in Domain,
/// Application or Data may import this.
enum DS {}

// MARK: - Colour

extension DS {
    enum Colors {
        /// #090E12 — the app background every screen is designed on.
        static let background = Color(hex: 0x090E12)
        /// #151A20 — raised surfaces (list rows, stat tiles).
        static let surface = Color(hex: 0x151A20)
        /// #3881F9 — primary accent.
        static let accent = Color(hex: 0x3881F9)
        /// #F94144 — destructive / attention.
        static let danger = Color(hex: 0xF94144)

        /// #FAFAFA — primary text.
        static let textPrimary = Color(hex: 0xFAFAFA)
        /// #989FA8 — secondary text and inactive glyphs.
        static let textSecondary = Color(hex: 0x989FA8)
        /// Text on the vehicle card, which sits on its own blue gradient.
        static let onCardPrimary = Color.white
        static let onCardSecondary = Color.white.opacity(0.6)
        static let onCardTertiary = Color.white.opacity(0.502)

        /// Hairline used on glass surfaces.
        static let hairline = Color.white.opacity(0.059)
        /// Slightly brighter hairline used on the small glass chips.
        static let hairlineStrong = Color.white.opacity(0.078)
    }
}

// MARK: - Gradients

extension DS {
    enum Gradients {
        /// Glass fill for chips and the notification button: white 5.9% → 2.0%, vertical.
        static let glass = LinearGradient(
            colors: [Color.white.opacity(0.059), Color.white.opacity(0.020)],
            startPoint: .top, endPoint: .bottom
        )

        /// Vehicle card: #023481 → #08173F (45%) → #0A121F.
        /// Figma's gradientTransform inverts to (0.28, −0.10) → (0.72, 1.10): almost vertical
        /// with a slight left-to-right lean, so the bright blue spans the full card width at
        /// the top rather than hugging one corner.
        static let vehicleCard = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x023481), location: 0),
                .init(color: Color(hex: 0x08173F), location: 0.45),
                .init(color: Color(hex: 0x0A121F), location: 1)
            ],
            startPoint: UnitPoint(x: 0.28, y: -0.10),
            endPoint: UnitPoint(x: 0.72, y: 1.10)
        )

        /// AI recommendation: #6C50E9 → #0081F1 (60%) → #00BDBF, diagonal.
        static let aiCard = LinearGradient(
            stops: [
                .init(color: Color(hex: 0x6C50E9), location: 0),
                .init(color: Color(hex: 0x0081F1), location: 0.6),
                .init(color: Color(hex: 0x00BDBF), location: 1)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        /// Centre add button: #3881F9 → #58A1FF, diagonal.
        static let accentButton = LinearGradient(
            colors: [Color(hex: 0x3881F9), Color(hex: 0x58A1FF)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }
}

// MARK: - Typography
//
// The design uses Inter. It is not bundled, so each token maps to the system font at the
// same size, weight and tracking. Swapping in Inter later is a change to this enum only.

extension DS {
    enum Text {
        /// Inter Bold 32 / 40, tracking −0.8 — paywall hero title.
        static let hero = Font.system(size: 32, weight: .bold)
        static let heroTracking: CGFloat = -0.8
        /// Inter Bold 20 / 30 — plan price.
        static let price = Font.system(size: 20, weight: .bold)
        /// Inter Regular 11 / 16.5 — plan name.
        static let planName = Font.system(size: 11)
        /// Inter Medium 13 / 19.5 — benefit row.
        static let benefit = Font.system(size: 13, weight: .medium)
        /// Inter Bold 9 / 13.5 — "BEST" flag.
        static let flag = Font.system(size: 9, weight: .bold)

        /// Inter Bold 28 / 35, tracking −0.7 — AI tab hero title.
        static let aiHero = Font.system(size: 28, weight: .bold)
        static let aiHeroTracking: CGFloat = -0.7

        /// Inter Bold 30 / 37.5, tracking −0.75 — screen title.
        static let title = Font.system(size: 30, weight: .bold)
        static let titleTracking: CGFloat = -0.75

        /// Inter Bold 24 / 32, tracking −0.6 — vehicle name, stat values.
        static let headline = Font.system(size: 24, weight: .bold)
        static let headlineTracking: CGFloat = -0.6

        /// Inter Bold 18 / 27, tracking −0.45 — section heading.
        static let section = Font.system(size: 18, weight: .bold)
        static let sectionTracking: CGFloat = -0.45

        /// Inter Semi Bold 15 / 22.5 — list row title.
        static let rowTitle = Font.system(size: 15, weight: .semibold)
        /// Inter Bold 20 / 28, tracking −0.5 — collapsed vehicle row title.
        static let vehicleRowTitle = Font.system(size: 20, weight: .bold)
        static let vehicleRowTracking: CGFloat = -0.5
        /// Inter Semi Bold 14 / 21 — inline text button.
        static let button = Font.system(size: 14, weight: .semibold)
        /// Inter Regular 15 / 20.6 — AI body copy.
        static let body = Font.system(size: 15)
        /// Inter Bold 15 / 22.5, tracking −0.375 — compact stat value.
        static let statValue = Font.system(size: 15, weight: .bold)
        static let statValueTracking: CGFloat = -0.375

        /// Inter Medium 13 / 19.5 — greeting, card label.
        static let subheadline = Font.system(size: 13, weight: .medium)
        /// Inter Regular 13 / 19.5 — vehicle subtitle.
        static let subheadlineRegular = Font.system(size: 13)
        /// Inter Semi Bold 12 / 18, tracking 0.6 — AI eyebrow.
        static let eyebrow = Font.system(size: 12, weight: .semibold)
        static let eyebrowTracking: CGFloat = 0.6
        /// Inter Regular 12 / 18 — row subtitle, tile label.
        static let caption = Font.system(size: 12)
        /// Inter Semi Bold 11 / 16.5 — status chip.
        static let chip = Font.system(size: 11, weight: .semibold)
        /// Inter Semi Bold 10 / 15 — delta badge, tab label, tier chip.
        static let badge = Font.system(size: 10, weight: .semibold)
        static let badgeTracking: CGFloat = 0.5
        /// Inter Semi Bold 17 / 25.5 — account name.
        static let identityName = Font.system(size: 17, weight: .semibold)
        /// Inter Bold 18 / 28 — avatar initials.
        static let avatar = Font.system(size: 18, weight: .bold)
        /// Inter Regular 11 / 16.5 — stat caption under a value.
        static let statCaption = Font.system(size: 11)
        /// Inter Semi Bold 11 / 16.5, tracking 0.55 — compact eyebrow.
        static let eyebrowSmall = Font.system(size: 11, weight: .semibold)
        static let eyebrowSmallTracking: CGFloat = 0.55
        /// Inter Regular 10 / 15 — stat unit.
        static let statUnit = Font.system(size: 10)
        /// Inter Medium 9 / 13.5, tracking 0.45 — stat caption.
        static let statLabel = Font.system(size: 9, weight: .medium)
        static let statLabelTracking: CGFloat = 0.45

        /// The design's default tracking for body-sized text.
        static let defaultTracking: CGFloat = -0.16
    }
}

// MARK: - Metrics

extension DS {
    enum Layout {
        /// Screen gutter — every section is inset 20pt in a 388pt-wide frame.
        static let gutter: CGFloat = 20
        /// Header uses a wider 24pt inset.
        static let headerGutter: CGFloat = 24
        static let sectionSpacing: CGFloat = 20

        /// Vertical space each tab's content must reserve for the floating tab bar:
        /// the 59pt bar plus its 8pt offset plus breathing room.
        static let tabBarReservedHeight: CGFloat = 75

        static let cardRadius: CGFloat = 28
        static let surfaceRadius: CGFloat = 24
        static let chipRadius: CGFloat = 13.25
        static let hairlineWidth: CGFloat = 1
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Genuinely translucent glass — whatever sits behind shows through. That is what makes
    /// the stat chips read as glass over the vehicle card's blue rather than as black holes.
    /// The tab bar composites its own opaque base separately, because it floats over screens
    /// that are not dark yet.
    func dsGlass(radius: CGFloat, strokeColor: Color = DS.Colors.hairlineStrong) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .fill(DS.Gradients.glass)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .circular)
                        .strokeBorder(strokeColor, lineWidth: DS.Layout.hairlineWidth)
                )
        )
    }

    /// A #151A20 surface with the design's hairline.
    func dsSurface(radius: CGFloat = DS.Layout.surfaceRadius) -> some View {
        background(
            RoundedRectangle(cornerRadius: radius, style: .circular)
                .fill(DS.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .circular)
                        .strokeBorder(DS.Colors.hairline, lineWidth: DS.Layout.hairlineWidth)
                )
        )
    }
}
