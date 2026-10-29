import SwiftUI

/// Asked once, before the first AI chat message or AI scan (App Store Guideline 5.1.2(i)):
/// names the third-party AI, says exactly what is sent and what never is, and takes a clear
/// yes. "Not now" sends nothing and leaves the rest of the app untouched. The answer can be
/// changed any time under Profile → Support.
struct AIConsentView: View {
    @Environment(\.appModel) private var model

    private var points: [(String, String)] {
        [
            ("bubble.left.and.text.bubble.right", String(localized: "Messages you write to the AI assistant, with your car's make, model, year, fuel type and mileage.")),
            ("camera.viewfinder", String(localized: "Photos of receipts, dashboards and damage that you choose to scan — without location data.")),
            ("server.rack", String(localized: "They pass through our server in the EU (Supabase) to OpenAI, which uses them only to answer you. We don't keep them, and OpenAI doesn't use them to train its models.")),
            ("hand.raised", String(localized: "Your name, email, Apple ID, VIN and number plate are never sent."))
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(DS.Gradients.aiCard))
                    .padding(.top, 32)
                    .accessibilityHidden(true)
                Text("Your data and AI").font(DS.Text.title).tracking(DS.Text.titleTracking).foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                Text("AI features are powered by \(AIDataSharing.provider). To answer you, the app sends only what you choose to send:")
                    .font(DS.Text.body).foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(points, id: \.1) { symbol, text in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                                .foregroundStyle(DS.Colors.accent).frame(width: 24)
                                .accessibilityHidden(true)
                            Text(text).font(DS.Text.body).foregroundStyle(.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text("You can change this any time in Profile → Support.")
                    .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                Button("Privacy Policy") { model?.router.present(.legal(.privacyPolicy)) }
                    .font(DS.Text.caption.weight(.semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .accessibilityIdentifier("aiConsentPrivacy")
            }
            .padding(.horizontal, DS.Layout.gutter)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                SaveButton(title: String(localized: "Allow")) {
                    model?.dependencies.preferences.aiDataSharingConsentVersion = AIDataSharing.currentVersion
                    model?.router.dismissModal()
                    // Continue to the chat or scan the user was heading to.
                    model?.router.replayPendingDestination()
                }
                .accessibilityIdentifier("aiConsentAllow")
                Button("Not now") {
                    model?.router.clearPendingDestination()
                    model?.router.dismissModal()
                }
                .font(DS.Text.button).foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("aiConsentDecline")
            }
            .padding(.horizontal, DS.Layout.gutter)
            .padding(.bottom, 8)
            .background(DS.Colors.background)
        }
        .background(DS.Colors.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
    }
}
