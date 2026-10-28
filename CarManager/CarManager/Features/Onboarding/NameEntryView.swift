import SwiftUI

/// Shown once after signing in when Apple did not share a name (the user chose not to, or
/// used "Hide My Email"). The name is only displayed in the app — greeting, Profile.
struct NameEntryView: View {
    @Environment(\.appModel) private var model
    @State private var name = ""
    @State private var isSaving = false
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmed.isEmpty && trimmed.count <= UserProfile.maxDisplayNameLength && !isSaving }

    var body: some View {
        ZStack {
            SplashBackground()
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 40)
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(DS.Gradients.accentButton))
                    .padding(.bottom, 24)
                Text("What should we call you?")
                    .font(DS.Text.title).tracking(DS.Text.titleTracking)
                    .foregroundStyle(.white)
                    .padding(.bottom, 8)
                Text("Only used to greet you and show in your profile. You can change it any time in Settings.")
                    .font(DS.Text.subheadlineRegular)
                    .foregroundStyle(DS.Colors.onCardSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 28)

                HStack(spacing: 10) {
                    TextField("", text: $name, prompt: Text("Your name").foregroundStyle(DS.Colors.textSecondary))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .tint(DS.Colors.accent)
                        .textContentType(.givenName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.continue)
                        .focused($focused)
                        .onSubmit(save)
                        .accessibilityIdentifier("nameEntryField")
                    if !name.isEmpty {
                        Button { name = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Colors.textSecondary)
                        }
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 56)
                .dsGlass(radius: 28)

                if trimmed.count > UserProfile.maxDisplayNameLength {
                    Text("Keep it under \(UserProfile.maxDisplayNameLength) characters.")
                        .font(DS.Text.caption).foregroundStyle(DS.Colors.warning).padding(.top, 8)
                }
                if let error {
                    Text(error).font(DS.Text.caption).foregroundStyle(DS.Colors.danger).padding(.top, 8)
                }

                Spacer()
                SaveButton(title: "Continue", symbol: "arrow.right", isBusy: isSaving, isEnabled: canSave, action: save)
                    .accessibilityIdentifier("nameEntryContinue")
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, DS.Layout.headerGutter)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { focused = true }
    }

    private func save() {
        guard canSave, let model else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await model.auth.updateDisplayName(trimmed)
            } catch {
                self.error = UserMessage.text(for: error)
            }
        }
    }
}
