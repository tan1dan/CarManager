import Foundation

/// Display-ready values for Settings (Figma node 3:5480).
struct SettingsPresentationModel: Equatable, Sendable {
    var title: String
    var sections: [Section]

    struct Section: Equatable, Sendable, Identifiable {
        var id: String { title }
        var title: String
        var rows: [Row]
    }

    struct Row: Equatable, Sendable, Identifiable {
        var id: String
        var symbolName: String
        var title: String
        var trailing: Trailing
        var action: Action
    }

    /// What sits on the right of a row.
    enum Trailing: Equatable, Sendable {
        case chevron
        case value(String)
        /// Identifies which preference the switch drives; the view resolves the binding so the
        /// model stays plain data.
        case toggle(ToggleKind)
        case none
    }

    enum ToggleKind: String, Equatable, Sendable {
        case notifications, telemetry
    }

    /// What tapping a row does. Kept as data so the row list is testable without a router.
    enum Action: Equatable, Sendable {
        /// Tapping does nothing — the row only displays a value.
        case inert
        case push(AppRoute)
        case openURL(URL)
        case exportPDF
    }

    static let placeholder = SettingsPresentationModel(title: "Settings", sections: [])
}

/// Pure mapping onto display values.
struct SettingsFormatter: Sendable {
    let locale: Locale
    let timeZone: TimeZone
    let appVersion: String

    /// The App Store's own billing page. The app never collects or stores card details —
    /// see the security rules in the architecture docs.
    static let appStoreBillingURL = URL(string: "https://apps.apple.com/account/billing")!

    /// Plain-language rendering of `SyncState` for the Settings row.
    static func describe(_ state: SyncState) -> String {
        switch state {
        case .idle(let lastSyncedAt):
            guard let lastSyncedAt else { return "On" }
            return "On · \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))"
        case .syncing: return "Syncing…"
        case .failed(let message, _): return message
        case .unavailable(let reason): return reason
        }
    }

    func makeModel(
        authState: AuthState,
        unitSystem: UnitSystem,
        telemetryEnabled: Bool,
        syncState: SyncState
    ) -> SettingsPresentationModel {
        SettingsPresentationModel(
            title: "Settings",
            sections: [
                .init(title: "ACCOUNT", rows: accountRows(authState: authState)),
                .init(title: "PREFERENCES", rows: preferenceRows(unitSystem: unitSystem)),
                .init(title: "DATA", rows: dataRows(syncDescription: Self.describe(syncState))),
                .init(title: "ABOUT", rows: aboutRows())
            ]
        )
    }

    private func accountRows(authState: AuthState) -> [SettingsPresentationModel.Row] {
        let email = authState.profile?.email
        return [
            // The only way in is Sign in with Apple, so there is no password to manage.
            .init(
                id: "email", symbolName: "apple.logo", title: "Apple ID",
                trailing: email.map { .value(truncatedEmail($0)) } ?? .value("Not signed in"),
                action: .push(.settingsSection(.account))
            ),
            .init(
                id: "subscription", symbolName: "crown", title: "Subscription",
                trailing: .chevron, action: .push(.subscriptionSettings)
            ),
            // The design shows a stored card ("Visa ·· 4832"). The app deliberately holds no
            // card data, so this row links out to the App Store's billing settings instead of
            // displaying a number it has no right to know.
            .init(
                id: "payment", symbolName: "creditcard", title: "Payment method",
                trailing: .chevron, action: .openURL(Self.appStoreBillingURL)
            )
        ]
    }

    private func preferenceRows(unitSystem: UnitSystem) -> [SettingsPresentationModel.Row] {
        [
            .init(
                id: "units", symbolName: "globe", title: "Units",
                trailing: .value(unitSystem == .metric ? "Metric" : "Imperial"),
                action: .push(.settingsSection(.units))
            ),
            // Region and time zone belong to iOS, not to this app: shown, never edited here.
            .init(
                id: "region", symbolName: "mappin.and.ellipse", title: "Region",
                trailing: .value(regionName), action: .inert
            ),
            .init(
                id: "timezone", symbolName: "clock", title: "Time zone",
                trailing: .value(timeZoneName), action: .inert
            ),
            .init(
                id: "notifications", symbolName: "bell", title: "Notifications",
                trailing: .toggle(.notifications), action: .inert
            )
        ]
    }

    private func dataRows(syncDescription: String) -> [SettingsPresentationModel.Row] {
        [
            // A switch here would be a lie: mirroring is configured when the store opens,
            // and whether it works depends on the device's iCloud account. So the row
            // reports the truth instead of pretending to control it.
            .init(
                id: "icloud", symbolName: "icloud", title: "iCloud sync",
                trailing: .value(syncDescription), action: .inert
            ),
            .init(
                id: "export", symbolName: "square.and.arrow.down", title: "Export as PDF",
                trailing: .chevron, action: .exportPDF
            ),
            // "Analytics" here is product telemetry, unrelated to the app's Analytics feature.
            // It is a switch, not a read-only value, because it must be possible to opt out.
            .init(
                id: "telemetry", symbolName: "chart.line.uptrend.xyaxis", title: "Analytics",
                trailing: .toggle(.telemetry), action: .inert
            )
        ]
    }

    private func aboutRows() -> [SettingsPresentationModel.Row] {
        [
            .init(
                id: "version", symbolName: "info.circle", title: "Version",
                trailing: .value(appVersion), action: .inert
            ),
            .init(
                id: "support", symbolName: "lifepreserver", title: "Support",
                trailing: .chevron, action: .push(.supportSettings)
            )
        ]
    }

    // MARK: - Values

    var regionName: String {
        guard let region = locale.region?.identifier else { return "—" }
        return locale.localizedString(forRegionCode: region) ?? region
    }

    var timeZoneName: String {
        timeZone.abbreviation() ?? timeZone.identifier
    }

    /// The design truncates a long address to fit the row.
    func truncatedEmail(_ email: String) -> String {
        guard email.count > 14 else { return email }
        return String(email.prefix(5)) + "…"
    }
}
