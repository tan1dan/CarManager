import SwiftUI

/// Shared layout for the sign-in screen (Figma 3:3838): round back button, 32pt title, grey
/// subtitle, then the content.
///
/// The design stacks title, subtitle and buttons with no gaps between them; here they get the
/// app's rhythm — 4pt title→subtitle, 24pt to the content, 20pt between groups.
struct AuthScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void
    var errorMessage: String?
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CircleBackButton(action: onBack)
                        .padding(.bottom, 16)
                        .accessibilityIdentifier("authBack")

                    Text(title)
                        .font(DS.Text.hero)
                        .tracking(DS.Text.heroTracking)
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: DS.Layout.sectionSpacing) {
                        content
                        if let errorMessage {
                            AuthErrorText(message: errorMessage)
                        }
                    }
                    .padding(.top, 24)
                }
                .padding(.horizontal, DS.Layout.headerGutter)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct AuthErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(DS.Text.subheadline)
            .foregroundStyle(DS.Colors.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("authError")
    }
}
