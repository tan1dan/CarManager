import SwiftUI

/// Profile, built from Figma node 3:5270.
///
/// One deliberate addition to the design: a "Settings" row. The design has no entry point to
/// Settings, and the app needs one, so it reuses the design's own row component rather than
/// inventing a new affordance.
struct ProfileView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: ProfileViewModel?

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Layout.sectionSpacing) {
                    header
                    identityCard
                    statsRow
                    if let premium = presentation.premium {
                        premiumBanner(premium)
                    }
                    settingsList
                    signOutButton
                }
                .padding(.bottom, DS.Layout.tabBarReservedHeight)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .onChange(of: model?.router.activeModal) { _, modal in
            if modal == nil { Task { await load() } }
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(presentation.title)
                .font(DS.Text.title)
                .tracking(DS.Text.titleTracking)
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, DS.Layout.headerGutter)
        .padding(.top, 16)
    }

    private var identityCard: some View {
        HStack(spacing: 16) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.identity.name)
                    .font(DS.Text.identityName)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(DS.Colors.onCardPrimary)
                    .lineLimit(1)
                if !presentation.identity.subtitle.isEmpty {
                    Text(presentation.identity.subtitle)
                        .font(DS.Text.subheadlineRegular)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                }
                tierBadge.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface()
        .padding(.horizontal, DS.Layout.gutter)
    }

    private var avatar: some View {
        Text(presentation.identity.initials)
            .font(DS.Text.avatar)
            .tracking(DS.Text.defaultTracking)
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(Circle().fill(DS.Gradients.accentButton))
            .overlay(alignment: .bottomTrailing) {
                if presentation.identity.isPremium {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .offset(x: 2, y: 0)
                }
            }
    }

    private var tierBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "crown.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(presentation.identity.badgeTitle)
                .font(DS.Text.badge)
                .tracking(DS.Text.badgeTracking)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(
            Capsule().fill(
                presentation.identity.isPremium
                    ? AnyShapeStyle(DS.Gradients.accentButton)
                    : AnyShapeStyle(Color.white.opacity(0.149))
            )
        )
        .accessibilityIdentifier("profileTierBadge")
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            ForEach(presentation.stats) { stat in
                VStack(spacing: 4) {
                    Image(systemName: stat.symbolName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(DS.Colors.accent)
                    Text(stat.value)
                        .font(DS.Text.headline)
                        .tracking(DS.Text.headlineTracking)
                        .foregroundStyle(DS.Colors.onCardPrimary)
                    Text(stat.label)
                        .font(DS.Text.statCaption)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .dsSurface()
            }
        }
        .padding(.horizontal, DS.Layout.gutter)
    }

    private func premiumBanner(_ banner: ProfilePresentationModel.PremiumBanner) -> some View {
        Button {
            if !presentation.identity.isPremium {
                model?.router.present(.paywall(.settingsUpgrade))
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .medium))
                    Text(banner.eyebrow)
                        .font(DS.Text.eyebrowSmall)
                        .tracking(DS.Text.eyebrowSmallTracking)
                }
                .foregroundStyle(Color.white.opacity(0.851))

                Text(banner.body)
                    .font(DS.Text.rowTitle)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius, style: .circular)
                    .fill(DS.Gradients.aiCard)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DS.Layout.gutter)
        .accessibilityIdentifier("profilePremium")
    }

    private var settingsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(presentation.rows.enumerated()), id: \.element.id) { index, row in
                SettingsRowView(
                    symbolName: row.symbolName,
                    title: row.title,
                    action: row.destination.map { destination in
                        { model?.router.push(destination, in: .profile) }
                    }
                ) {
                    profileRowTrailing(row.trailing)
                }
                .accessibilityIdentifier("profileRow_\(row.id)")
                if index < presentation.rows.count - 1 {
                    SettingsRowSeparator()
                }
            }
        }
        .dsSurface()
        .padding(.horizontal, DS.Layout.gutter)
    }

    @ViewBuilder
    private var signOutButton: some View {
        if model?.auth.state.isAuthenticated == true {
            Button("Sign out") { Task { await viewModel?.signOut() } }
                .font(DS.Text.rowTitle)
                .foregroundStyle(DS.Colors.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .dsSurface()
                .padding(.horizontal, DS.Layout.gutter)
                .accessibilityIdentifier("profileSignOut")
        } else {
            Button("Sign in") {
                model?.router.presentFullScreen(.authentication(.signIn))
            }
            .font(DS.Text.rowTitle)
            .foregroundStyle(DS.Colors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .dsSurface()
            .padding(.horizontal, DS.Layout.gutter)
            .accessibilityIdentifier("profileSignIn")
        }
    }

    @ViewBuilder
    private func profileRowTrailing(_ trailing: ProfilePresentationModel.Row.Trailing) -> some View {
        switch trailing {
        case .chevron:
            SettingsRowChevron()
        case .value(let text):
            SettingsRowValue(text: text)
        case .darkModeToggle:
            // The app is dark-only today; this persists the preference so the switch is not
            // decorative, but there is no light theme for it to switch to yet.
            Toggle("", isOn: Binding(
                get: { model?.dependencies.preferences.appearance != .light },
                set: { model?.dependencies.preferences.appearance = $0 ? .dark : .light }
            ))
            .labelsHidden()
            .tint(DS.Colors.accent)
            .accessibilityIdentifier("profileDarkModeToggle")
        }
    }

    // MARK: - Wiring

    private var presentation: ProfilePresentationModel {
        viewModel?.presentation ?? .placeholder
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            viewModel = ProfileViewModel(
                loadStatistics: LoadUserStatistics(vehicles: model.dependencies.vehicles),
                formatter: ProfileFormatter(
                    languageName: Locale.current.localizedString(
                        forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en"
                    ) ?? "English"
                ),
                authStore: model.auth,
                entitlements: model.entitlements
            )
        }
        await viewModel?.load()
    }
}
