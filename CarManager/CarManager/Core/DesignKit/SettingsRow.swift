import SwiftUI

/// The list row shared by Settings and Profile (Figma: 346×73, padding 14, gap 12,
/// 44pt icon circle filled white 5.1%, hairline separators between rows).
struct SettingsRowView<Trailing: View>: View {
    let symbolName: String
    let title: String
    let action: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        if let action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DS.Colors.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.white.opacity(0.051)))

            Text(title)
                .font(DS.Text.rowTitle)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(DS.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(14)
        .contentShape(.rect)
    }
}

// MARK: - Standard trailing accessories

/// A grey value on the right — "Metric", "1.0.0", "alex@…".
struct SettingsRowValue: View {
    let text: String

    var body: some View {
        Text(text)
            .font(DS.Text.subheadlineRegular)
            .tracking(DS.Text.defaultTracking)
            .foregroundStyle(DS.Colors.onCardTertiary)
            .lineLimit(1)
    }
}

struct SettingsRowChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.Colors.textSecondary)
    }
}

/// Hairline between two rows inside one surface.
struct SettingsRowSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.051))
            .frame(height: DS.Layout.hairlineWidth)
    }
}

/// A titled group of rows: an uppercase caption above a #151A20 surface.
struct SettingsSectionContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Text.eyebrowSmall)
                .tracking(DS.Text.eyebrowSmallTracking)
                .foregroundStyle(Color.white.opacity(0.4))

            VStack(spacing: 0) { content }
                .dsSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
