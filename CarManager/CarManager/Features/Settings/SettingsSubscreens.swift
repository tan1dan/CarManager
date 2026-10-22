import SwiftUI

// Settings sub-screens, built from Figma 43 (Units), 47 (Notifications), 49 (Subscription).
// Preferences live behind `PreferencesProviding`, which is not observable, so each screen
// keeps a local copy and writes through on change.

/// A titled group of rows on a settings sub-screen.
private struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            if let title { Eyebrow(text: title) }
            VStack(spacing: 0) { content }.dsSurface()
        }
    }
}

/// Icon disc, title, optional subtitle and a trailing control — the Figma settings row.
private struct SettingsLine<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var isFirst = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.051)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(DS.Text.rowTitle).foregroundStyle(DS.Colors.textPrimary)
                if let subtitle { Text(subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .overlay(alignment: .top) { if !isFirst { SettingsRowSeparator() } }
        .contentShape(.rect)
    }
}

/// A menu-backed value ("Kilometres ⌄").
private struct MenuValue<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.0 == selection }?.1 ?? "").font(DS.Text.button).foregroundStyle(.white)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Colors.textSecondary)
            }
        }
    }
}

private struct SubscreenScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.appModel) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: title, onBack: { model?.router.pop() })
                VStack(spacing: DS.Layout.sectionSpacing) { content }
                    .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
    }
}

private struct Footnote: View {
    let text: String
    var body: some View {
        Text(text).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSectionView: View {
    let section: SettingsSection

    var body: some View {
        switch section {
        case .units, .currency, .language: UnitsSettingsView()
        case .notifications: NotificationSettingsView()
        case .account: AccountSettingsView()
        case .appearance, .data, .about: AboutView()
        }
    }
}

// MARK: - Units & language (Figma 43)

private struct UnitsSettingsView: View {
    @Environment(\.appModel) private var model
    @Environment(\.openURL) private var openURL
    @State private var unitSystem: UnitSystem = .metric
    @State private var currency = CurrencyCode.eur

    private static let currencies = ["EUR", "USD", "GBP", "PLN", "SEK", "NOK", "DKK", "CHF", "CZK", "UAH"].map(CurrencyCode.init)

    var body: some View {
        SubscreenScaffold(title: "Units & language") {
            SettingsGroup(title: "Units") {
                SettingsLine(symbol: "gauge.with.dots.needle.33percent", title: "Distance", isFirst: true) {
                    MenuValue(options: [(.metric, "Kilometres"), (.imperial, "Miles")], selection: $unitSystem)
                        .accessibilityIdentifier("unitsPicker")
                }
                SettingsLine(symbol: "drop", title: "Volume", subtitle: "Follows distance") {
                    Text(unitSystem == .metric ? "Litres" : "Gallons").font(DS.Text.button).foregroundStyle(DS.Colors.textSecondary)
                }
                SettingsLine(symbol: "creditcard", title: "Currency", subtitle: "For new vehicles") {
                    MenuValue(options: Self.currencies.map { ($0, "\($0.iso4217) \(DisplayFormat().currencySymbol($0))") },
                              selection: $currency)
                }
            }
            SettingsGroup(title: "Language") {
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                    SettingsLine(symbol: "globe", title: "App language", subtitle: "Changed in iOS Settings", isFirst: true) {
                        HStack(spacing: 6) {
                            Text(Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "")
                                .font(DS.Text.button).foregroundStyle(.white)
                            SettingsRowChevron()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Footnote(text: unitSystem == .metric
                     ? "Consumption is shown as L/100 km. Switching to miles changes it to mpg everywhere."
                     : "Consumption is shown as mpg (US). Your records stay stored in metric.")
        }
        .onAppear {
            guard let preferences = model?.dependencies.preferences else { return }
            unitSystem = preferences.unitSystem
            currency = preferences.defaultCurrency
        }
        .onChange(of: unitSystem) { _, value in model?.dependencies.preferences.unitSystem = value }
        .onChange(of: currency) { _, value in model?.dependencies.preferences.defaultCurrency = value }
    }
}

// MARK: - Notifications (Figma 47)

private struct NotificationSettingsView: View {
    @Environment(\.appModel) private var model
    @Environment(\.openURL) private var openURL
    @State private var enabled = true
    @State private var system: NotificationAuthorization?

    var body: some View {
        SubscreenScaffold(title: "Notifications") {
            SettingsGroup(title: "What to send") {
                SettingsLine(symbol: "bell", title: "Reminders", subtitle: "Insurance, service, inspection, documents", isFirst: true) {
                    Toggle("", isOn: $enabled).labelsHidden().tint(DS.Colors.accent)
                }
            }
            Footnote(text: "Date reminders notify ahead of time. Mileage reminders show in the app as you log the odometer — iOS can't trigger on distance.")
            if system == .denied {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(DS.Colors.warning)
                    Text("Notifications are off for Car Manager in iOS Settings.")
                        .font(DS.Text.caption).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 8)
                    Button("Open") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.Colors.accent)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(DS.Colors.warning.opacity(0.1)))
            }
        }
        .task {
            enabled = model?.dependencies.preferences.notificationsEnabled ?? true
            system = await model?.dependencies.notifications.authorizationStatus()
        }
        .onChange(of: enabled) { _, value in
            model?.dependencies.preferences.notificationsEnabled = value
            guard value, system == .notDetermined, let notifications = model?.dependencies.notifications else { return }
            Task {
                _ = try? await notifications.requestAuthorization()
                system = await notifications.authorizationStatus()
            }
        }
    }
}

// MARK: - Account

private struct AccountSettingsView: View {
    @Environment(\.appModel) private var model
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var error: String?

    private var profile: UserProfile? { model?.auth.state.profile }

    var body: some View {
        SubscreenScaffold(title: "Account") {
            VStack(spacing: 6) {
                Text(initials)
                    .font(DS.Text.avatar).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(DS.Gradients.accentButton))
                    .padding(.bottom, 6)
                Text(profile?.displayName ?? "Apple account").font(DS.Text.identityName).foregroundStyle(.white)
                if let email = profile?.email { Text(email).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary) }
                Label("Signed in with Apple", systemImage: "apple.logo")
                    .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .dsSurface()

            SettingsGroup(title: nil) {
                Button { confirmingSignOut = true } label: {
                    SettingsLine(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out", isFirst: true) { EmptyView() }
                }
                .buttonStyle(.plain)
                Button { confirmingDelete = true } label: {
                    SettingsLine(symbol: "trash", title: "Delete account", subtitle: "Removes your data from this app") { EmptyView() }
                        .foregroundStyle(DS.Colors.danger)
                }
                .buttonStyle(.plain)
            }
            if let error { Text(error).font(DS.Text.caption).foregroundStyle(DS.Colors.danger) }
            Footnote(text: "Your records sync through your own iCloud account. Signing out keeps them in iCloud.")
        }
        .confirmDialog(isPresented: $confirmingSignOut, symbol: "rectangle.portrait.and.arrow.right", title: "Sign out?",
                       message: "You'll need Sign in with Apple to come back in.", confirmTitle: "Sign out") {
            Task { do { try await model?.auth.signOut() } catch { self.error = UserMessage.text(for: error) } }
        }
        .confirmDialog(isPresented: $confirmingDelete, symbol: "trash", title: "Delete account?",
                       message: "This removes your account from the app. It can't be undone.", confirmTitle: "Delete") {
            Task { do { try await model?.auth.deleteAccount() } catch { self.error = UserMessage.text(for: error) } }
        }
    }

    private var initials: String {
        let parts = (profile?.displayName ?? "").split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "" : letters.uppercased()
    }
}

// MARK: - Subscription (Figma 49)

struct SubscriptionSettingsView: View {
    @Environment(\.appModel) private var model
    @State private var message: String?

    var body: some View {
        SubscreenScaffold(title: "Subscription") {
            statusCard
            SettingsGroup(title: nil) {
                Button { Task { await model?.entitlements.openManageSubscriptions() } } label: {
                    SettingsLine(symbol: "creditcard", title: "Manage in App Store", subtitle: "Change or cancel the plan", isFirst: true) {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subscriptionManage")
                Button(action: restore) {
                    SettingsLine(symbol: "arrow.down.circle", title: "Restore purchases", subtitle: "Signed in with Apple") {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                Button { model?.router.present(.paywall(.settingsUpgrade)) } label: {
                    SettingsLine(symbol: "info.circle", title: "What Premium includes", subtitle: "Scans, unlimited AI, more vehicles") {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subscriptionUpgrade")
            }
            if let message { Footnote(text: message) }
            Footnote(text: "Billing is handled by Apple. We never see your card details.")
        }
    }

    private var statusCard: some View {
        let entitlement = model?.entitlements.entitlement ?? .free
        let premium = model?.entitlements.isPremium ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "crown").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.18)))
                Spacer()
                Text(premium ? "ACTIVE" : "FREE").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .padding(.bottom, 12)
            Text(premium ? "Premium" : "Free plan").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text(detail(entitlement, premium: premium)).font(DS.Text.subheadlineRegular).foregroundStyle(.white.opacity(0.8))
            if !premium {
                Button { model?.router.present(.paywall(.settingsUpgrade)) } label: {
                    Text("Go Premium").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x0A121F))
                        .padding(.horizontal, 24).frame(height: 38).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(premium ? AnyShapeStyle(DS.Gradients.aiCard) : AnyShapeStyle(DS.Gradients.vehicleCard)))
    }

    private func detail(_ entitlement: Entitlement, premium: Bool) -> String {
        guard premium else { return "One vehicle, \(FeatureGating.freeDailyAIRequests) AI questions a day." }
        guard let expires = entitlement.expiresAt else { return "Active" }
        let date = expires.formatted(date: .abbreviated, time: .omitted)
        return entitlement.willAutoRenew ? "Renews \(date)" : "Ends \(date)"
    }

    private func restore() {
        Task {
            do {
                switch try await model?.entitlements.restore() {
                case .restored: message = "Purchases restored."
                default: message = "Nothing to restore for this Apple ID."
                }
            } catch {
                message = UserMessage.text(for: error)
            }
        }
    }
}

// MARK: - Vehicles

struct ManageVehiclesView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        SubscreenScaffold(title: "Vehicles") {
            SettingsGroup(title: nil) {
                ForEach(Array((model?.vehicles.summaries ?? []).enumerated()), id: \.element.id) { index, summary in
                    Button { model?.router.push(.vehicleDetail(summary.id), in: .profile) } label: {
                        SettingsLine(symbol: "car", title: summary.displayName,
                                     subtitle: summary.isDefault ? "Default" : nil, isFirst: index == 0) { SettingsRowChevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
            SaveButton(title: "Add vehicle", symbol: "plus") { model?.router.present(.vehicleEditor(.create)) }
        }
    }
}

struct DefaultVehicleView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        SubscreenScaffold(title: "Default vehicle") {
            SettingsGroup(title: nil) {
                ForEach(Array((model?.vehicles.summaries ?? []).enumerated()), id: \.element.id) { index, summary in
                    Button { Task { await model?.vehicles.select(summary.id) } } label: {
                        SettingsLine(symbol: "car", title: summary.displayName, isFirst: index == 0) {
                            if summary.isDefault { Image(systemName: "checkmark").foregroundStyle(DS.Colors.accent) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Support, legal, about

struct SupportSettingsView: View {
    var body: some View { LegalSettingsView(title: "Support") }
}

struct LegalSettingsView: View {
    var title = "Legal"
    @Environment(\.appModel) private var model

    var body: some View {
        SubscreenScaffold(title: title) {
            SettingsGroup(title: nil) {
                Button { model?.router.present(.legal(.privacyPolicy)) } label: {
                    SettingsLine(symbol: "hand.raised", title: "Privacy Policy", isFirst: true) { SettingsRowChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("legalPrivacy")
                Button { model?.router.present(.legal(.termsOfUse)) } label: {
                    SettingsLine(symbol: "doc.text", title: "Terms of Use") { SettingsRowChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("legalTerms")
            }
            Footnote(text: "Version \(Bundle.main.appVersionString)")
        }
    }
}

struct AboutView: View {
    var body: some View { LegalSettingsView(title: "About") }
}
