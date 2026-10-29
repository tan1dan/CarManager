import SwiftUI

// The app supports iOS 18. A few touches use iOS 26 API; each one goes through a wrapper here
// so the availability check lives in one place and the call sites stay readable.

extension View {
    /// The letter the system A–Z index shows for this section (iOS 26). Earlier systems use
    /// `SectionIndexBar` instead, which scrolls to the section's `id`.
    @ViewBuilder
    func sectionIndexLabelIfAvailable(_ label: String) -> some View {
        if #available(iOS 26.0, *) {
            sectionIndexLabel(label)
        } else {
            self
        }
    }

    /// Shows the system A–Z index on iOS 26.
    @ViewBuilder
    func listSectionIndexVisibleIfAvailable() -> some View {
        if #available(iOS 26.0, *) {
            listSectionIndexVisibility(.visible)
        } else {
            self
        }
    }
}

extension ToolbarContent {
    /// iOS 26 draws a shared glass capsule behind toolbar items; this keeps a plain text
    /// button. Earlier systems have no such background, so there is nothing to hide.
    @ToolbarContentBuilder
    func hidingSharedBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// A–Z jump bar for lists on iOS 18–25, where `listSectionIndexVisibility` does not exist.
/// Tap or drag along it; each letter scrolls to the section whose `id` is that letter.
struct SectionIndexBar: View {
    let letters: [String]
    let onSelect: (String) -> Void

    @State private var current: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 20, height: 15)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { pick(at: $0.location.y) }
                .onEnded { _ in current = nil }
        )
        .sensoryFeedback(.selection, trigger: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Section index"))
        .accessibilityAdjustableAction { direction in
            let index = current.flatMap(letters.firstIndex(of:)) ?? -1
            let next = direction == .increment ? index + 1 : index - 1
            if letters.indices.contains(next) { select(letters[next]) }
        }
    }

    private func pick(at y: CGFloat) {
        let index = Int((y - 6) / 15)
        guard letters.indices.contains(index) else { return }
        select(letters[index])
    }

    private func select(_ letter: String) {
        guard letter != current else { return }
        current = letter
        onSelect(letter)
    }
}
