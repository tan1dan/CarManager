import SwiftUI

/// The app's primary call to action: accent gradient capsule, 56pt (the design's 54.5 rounded
/// to the same height the paywall and vehicle editor use).
struct AccentCapsuleButton: View {
    let title: String
    var isBusy = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(DS.Text.rowTitle)
                        .tracking(DS.Text.defaultTracking)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: DS.Layout.buttonHeight)
            .background(Capsule().fill(DS.Gradients.accentButton))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBusy)
    }
}

/// Secondary action on dark backgrounds: translucent glass capsule with a hairline.
struct GlassCapsuleButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        Button(action: action) {
            label
                .font(DS.Text.rowTitle)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Layout.buttonHeight)
                .background(
                    Capsule()
                        .fill(DS.Gradients.glass)
                        .overlay(Capsule().strokeBorder(DS.Colors.hairlineStrong, lineWidth: DS.Layout.hairlineWidth))
                )
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

extension GlassCapsuleButton where Label == Text {
    init(_ title: String, action: @escaping () -> Void) {
        self.action = action
        self.label = Text(title)
    }
}

/// The 40pt round back button used on full-screen flows.
struct CircleBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.051)))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }
}
