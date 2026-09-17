import SwiftUI

/// Settings is a read/write view over `PreferencesProviding` — not a god-object.
struct SettingsView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        List {
            Text("Settings")

            Section("Vehicle") {
                Button("Manage Vehicles") { push(.manageVehicles) }
                    .accessibilityIdentifier("settingsManageVehicles")
                Button("Default Vehicle") { push(.defaultVehicle) }
                    .accessibilityIdentifier("settingsDefaultVehicle")
            }

            Section("App") {
                Button("Currency") { push(.settingsSection(.currency)) }
                Button("Language") { push(.settingsSection(.language)) }
                Button("Notifications") { push(.settingsSection(.notifications)) }
                    .accessibilityIdentifier("settingsNotifications")
                Button("Appearance") { push(.settingsSection(.appearance)) }
                Button("Units") { push(.settingsSection(.units)) }
                    .accessibilityIdentifier("settingsUnits")
            }

            Section("Subscription") {
                Button("Subscription") { push(.subscriptionSettings) }
                    .accessibilityIdentifier("settingsSubscription")
            }

            Section("Data") {
                Button("Data") { push(.settingsSection(.data)) }
                    .accessibilityIdentifier("settingsData")
            }

            Section("Support") {
                Button("Support") { push(.supportSettings) }
                    .accessibilityIdentifier("settingsSupport")
            }

            Section("Legal") {
                Button("Legal") { push(.legalSettings) }
                    .accessibilityIdentifier("settingsLegal")
            }

            Section("About") {
                Button("About") { push(.about) }
                Text("Version 1.0.0")
            }
        }
        .navigationTitle("Settings")
    }

    private func push(_ route: AppRoute) { model?.router.push(route, in: .profile) }
}

struct SettingsSectionView: View {
    let section: SettingsSection
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Text("Settings · \(section.rawValue)")

            switch section {
            case .units:
                Picker("Units", selection: Binding(
                    get: { model?.dependencies.preferences.unitSystem ?? .metric },
                    set: { model?.dependencies.preferences.unitSystem = $0 }
                )) {
                    ForEach(UnitSystem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .accessibilityIdentifier("unitsPicker")

            case .appearance:
                Picker("Appearance", selection: Binding(
                    get: { model?.dependencies.preferences.appearance ?? .system },
                    set: { model?.dependencies.preferences.appearance = $0 }
                )) {
                    ForEach(AppearancePreference.allCases) { Text($0.rawValue).tag($0) }
                }

            case .notifications:
                Toggle("Notifications", isOn: Binding(
                    get: { model?.dependencies.preferences.notificationsEnabled ?? true },
                    set: { model?.dependencies.preferences.notificationsEnabled = $0 }
                ))

            case .data:
                // Per the architecture recommendation, iCloud sync is NOT premium-gated.
                Toggle("iCloud Sync", isOn: Binding(
                    get: { model?.dependencies.preferences.iCloudSyncEnabled ?? true },
                    set: { model?.dependencies.preferences.iCloudSyncEnabled = $0 }
                ))
                .accessibilityIdentifier("iCloudSyncToggle")
                Button("Export Data") {}.accessibilityIdentifier("settingsExport")
                Button("Import Data") {}
                Button("Delete All Data", role: .destructive) {}
                    .accessibilityIdentifier("settingsDeleteAll")
                // "Analytics" here means product telemetry, unrelated to the Analytics feature.
                Toggle("Analytics (telemetry)", isOn: Binding(
                    get: { model?.dependencies.preferences.telemetryEnabled ?? false },
                    set: { model?.dependencies.preferences.telemetryEnabled = $0 }
                ))

            case .account:
                Text("Email")
                Text("Password")
                // The app NEVER collects card data — this deep-links to App Store billing.
                Link("Payment method", destination: URL(string: "https://apps.apple.com/account/billing")!)

            case .currency, .language, .about:
                Text("Placeholder")
            }
        }
        .navigationTitle(section.rawValue.capitalized)
    }
}

struct ManageVehiclesView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        List {
            Text("Manage Vehicles")
            ForEach(model?.vehicles.summaries ?? []) { summary in
                Button(summary.displayName) {
                    model?.router.push(.vehicleDetail(summary.id), in: .profile)
                }
            }
            Button("Add vehicle") { model?.router.present(.vehicleEditor(.create)) }
        }
        .navigationTitle("Vehicles")
    }
}

struct DefaultVehicleView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        List(model?.vehicles.summaries ?? []) { summary in
            Button("\(summary.isDefault ? "✓ " : "")\(summary.displayName)") {
                Task { await model?.vehicles.select(summary.id) }
            }
        }
        .navigationTitle("Default vehicle")
    }
}

struct SubscriptionSettingsView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        List {
            Text("Subscription")
            Button("Upgrade to Premium") { model?.router.present(.paywall(.settingsUpgrade)) }
                .accessibilityIdentifier("subscriptionUpgrade")
            Button("Manage Subscription") {
                Task { await model?.entitlements.openManageSubscriptions() }
            }
            .accessibilityIdentifier("subscriptionManage")
            Button("Restore Purchases") {
                Task { _ = try? await model?.entitlements.restore() }
            }
            .accessibilityIdentifier("subscriptionRestore")
        }
        .navigationTitle("Subscription")
    }
}

struct SupportSettingsView: View {
    var body: some View {
        List {
            Text("Support")
            Button("Contact Support") {}
            Button("Rate the App") {}
            Text("About")
        }
        .navigationTitle("Support")
    }
}

struct LegalSettingsView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        List {
            Text("Legal")
            Button("Privacy Policy") { model?.router.present(.legal(.privacyPolicy)) }
                .accessibilityIdentifier("legalPrivacy")
            Button("Terms of Use") { model?.router.present(.legal(.termsOfUse)) }
                .accessibilityIdentifier("legalTerms")
        }
        .navigationTitle("Legal")
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Text("About")
            Text("Version 1.0.0")
        }
        .navigationTitle("About")
    }
}
