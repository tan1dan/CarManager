import Foundation

/// Display-ready values for Profile (Figma node 3:5270).
struct ProfilePresentationModel: Equatable, Sendable {
    var title: String
    var identity: Identity
    var stats: [Stat]
    var premium: PremiumBanner?
    var rows: [Row]

    struct Identity: Equatable, Sendable {
        var initials: String
        var name: String
        var subtitle: String
        var isPremium: Bool
        var badgeTitle: String
    }

    struct Stat: Equatable, Sendable, Identifiable {
        var id: String { label }
        var symbolName: String
        var value: String
        var label: String
    }

    struct PremiumBanner: Equatable, Sendable {
        var eyebrow: String
        var body: String
    }

    /// One row of the settings list. `trailing` decides what sits on the right.
    struct Row: Equatable, Sendable, Identifiable {
        enum Trailing: Equatable, Sendable {
            case chevron
            case value(String)
        }

        var id: String
        var symbolName: String
        var title: String
        var trailing: Trailing
        var destination: AppRoute?
    }

    static let placeholder = ProfilePresentationModel(
        title: String(localized: "Profile"),
        identity: Identity(initials: "", name: "", subtitle: "", isPremium: false, badgeTitle: ""),
        stats: [], premium: nil, rows: []
    )
}

/// Pure mapping onto display values.
struct ProfileFormatter: Sendable {
    let languageName: String

    func makeModel(
        authState: AuthState,
        entitlement: Entitlement,
        isPremium: Bool,
        statistics: UserStatistics
    ) -> ProfilePresentationModel {
        ProfilePresentationModel(
            title: String(localized: "Profile"),
            identity: identity(authState: authState, isPremium: isPremium),
            stats: [
                .init(
                    symbolName: "car",
                    value: "\(statistics.vehicleCount)",
                    label: statistics.vehicleCount == 1 ? String(localized: "Vehicle") : String(localized: "Vehicles")
                ),
                .init(symbolName: "fuelpump", value: "\(statistics.fuelEntryCount)", label: String(localized: "Fill-ups")),
                .init(
                    symbolName: "wrench.adjustable",
                    value: "\(statistics.serviceRecordCount)",
                    label: String(localized: "Services")
                )
            ],
            premium: premiumBanner(isPremium: isPremium),
            rows: rows()
        )
    }

    private func identity(authState: AuthState, isPremium: Bool) -> ProfilePresentationModel.Identity {
        switch authState {
        case .authenticated(let profile):
            // Never the email as a name: with "Hide My Email" it is a random relay address.
            let name = profile.needsDisplayName ? String(localized: "Driver") : (profile.displayName ?? String(localized: "Driver"))
            return .init(
                initials: Self.initials(from: name),
                name: name,
                subtitle: profile.hasPrivateRelayEmail ? String(localized: "Private email via Apple") : (profile.email ?? ""),
                isPremium: isPremium,
                badgeTitle: isPremium ? String(localized: "PREMIUM") : String(localized: "FREE")
            )
        case .anonymous, .signedOut, .restoring:
            return .init(
                initials: "—",
                name: String(localized: "Not signed in"),
                subtitle: String(localized: "Sign in to sync and use AI"),
                isPremium: isPremium,
                badgeTitle: isPremium ? String(localized: "PREMIUM") : String(localized: "FREE")
            )
        }
    }

    private func premiumBanner(isPremium: Bool) -> ProfilePresentationModel.PremiumBanner? {
        isPremium
            ? .init(eyebrow: String(localized: "PREMIUM"), body: String(localized: "Unlimited vehicles, AI scans, cloud backup."))
            : .init(eyebrow: String(localized: "GO PREMIUM"), body: String(localized: "Unlimited vehicles, AI scans, cloud backup."))
    }

    private func rows() -> [ProfilePresentationModel.Row] {
        [
            // NOT in the Figma design — added because the app needs a way into Settings.
            .init(id: "settings", symbolName: "gearshape", title: String(localized: "Settings"),
                  trailing: .chevron, destination: .settings),
            .init(id: "language", symbolName: "globe", title: String(localized: "Language"),
                  trailing: .value(languageName), destination: .settingsSection(.language)),
            .init(id: "support", symbolName: "lifepreserver", title: String(localized: "Support"),
                  trailing: .chevron, destination: .supportSettings)
        ]
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "—" : letters.joined().uppercased()
    }
}
