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
                }
            },
            set: { newValue in
                guard let preferences = model?.dependencies.preferences else { return }
                switch kind {
                case .notifications: preferences.notificationsEnabled = newValue
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
        case .present(let modal):
            model.router.present(modal)
        case .openURL(let url):
            openURL(url)
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
                syncStore: model.sync
            )
        }
        await viewModel?.load()
    }
}

extension Bundle {
    var appVersionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return version
    }
}
