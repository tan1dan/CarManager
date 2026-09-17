import SwiftUI

/// Settings, built from Figma node 3:5480.
///
/// A read/write view over `PreferencesProviding` — not a god-object. Rows are plain data in
/// `SettingsPresentationModel`, so the list is testable without a router.
struct SettingsView: View {
    @Environment(\.appModel) private var model
    @Environment(\.openURL) private var openURL
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Layout.sectionSpacing) {
                    header

                    ForEach(presentation.sections) { section in
                        SettingsSectionContainer(title: section.title) {
                            ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                                rowView(row)
                                if index < section.rows.count - 1 {
                                    SettingsRowSeparator()
                                }
                            }
                        }
                        .padding(.horizontal, DS.Layout.gutter)
                    }

                    if let message = viewModel?.message {
                        Text(message)
                            .font(DS.Text.caption)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .padding(.horizontal, DS.Layout.gutter)
                    }
                }
                .padding(.bottom, DS.Layout.tabBarReservedHeight)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // The artboard has no back control because it is drawn as a standalone screen;
            // this one is pushed, so it needs one.
            Button { model?.router.router(for: .profile).pop() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .dsGlass(radius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settingsBack")
            .accessibilityLabel("Back")

            Text(presentation.title)
                .font(DS.Text.title)
                .tracking(DS.Text.titleTracking)
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DS.Layout.gutter)
        .padding(.top, 16)
    }

    // MARK: - Rows

    @ViewBuilder
    private func rowView(_ row: SettingsPresentationModel.Row) -> some View {
        SettingsRowView(
            symbolName: row.symbolName,
            title: row.title,
            action: row.action == .inert ? nil : { perform(row.action) }
        ) {
            switch row.trailing {
            case .chevron: SettingsRowChevron()
            case .value(let text): SettingsRowValue(text: text)
            case .toggle(let kind): toggle(kind)
            case .none: EmptyView()
            }
        }
        .accessibilityIdentifier("settingsRow_\(row.id)")
    }

    @ViewBuilder
    private func toggle(_ kind: SettingsPresentationModel.ToggleKind) -> some View {
        Toggle("", isOn: binding(for: kind))
            .labelsHidden()
            .tint(DS.Colors.accent)
            .accessibilityIdentifier("settingsToggle_\(kind.rawValue)")
    }

    private func binding(for kind: SettingsPresentationModel.ToggleKind) -> Binding<Bool> {
        Binding(
            get: {
                guard let preferences = model?.dependencies.preferences else { return false }
                return switch kind {
                case .notifications: preferences.notificationsEnabled
                case .iCloudSync: preferences.iCloudSyncEnabled
                case .telemetry: preferences.telemetryEnabled
                }
            },
            set: { newValue in
                guard let preferences = model?.dependencies.preferences else { return }
                switch kind {
                case .notifications: preferences.notificationsEnabled = newValue
                case .iCloudSync: preferences.iCloudSyncEnabled = newValue
                case .telemetry: preferences.telemetryEnabled = newValue
                }
                viewModel?.refresh()
            }
        )
    }

    private func perform(_ action: SettingsPresentationModel.Action) {
        guard let model else { return }
        switch action {
        case .inert:
            break
        case .push(let route):
            model.router.push(route, in: .profile)
        case .openURL(let url):
            openURL(url)
        case .exportPDF:
            Task { await viewModel?.exportPDF(vehicleID: model.selectedVehicleID) }
        }
    }

    // MARK: - Wiring

    private var presentation: SettingsPresentationModel {
        viewModel?.presentation ?? .placeholder
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            viewModel = SettingsViewModel(
                formatter: SettingsFormatter(
                    locale: .current,
                    timeZone: model.dependencies.clock.timeZone,
                    appVersion: Bundle.main.appVersionString
                ),
                preferences: model.dependencies.preferences,
                authStore: model.auth,
                featureGate: model.featureGate,
                exportPDF: ExportVehicleHistoryPDF(exporter: model.dependencies.exporter),
                router: model.router
            )
        }
        viewModel?.refresh()
    }
}

extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return version
    }
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
