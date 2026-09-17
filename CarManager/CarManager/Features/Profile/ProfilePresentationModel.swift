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
            case darkModeToggle
        }

        var id: String
        var symbolName: String
        var title: String
        var trailing: Trailing
        var destination: AppRoute?
    }

    static let placeholder = ProfilePresentationModel(
        title: "Profile",
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
            title: "Profile",
            identity: identity(authState: authState, isPremium: isPremium),
            stats: [
                .init(
                    symbolName: "car",
                    value: "\(statistics.vehicleCount)",
                    label: statistics.vehicleCount == 1 ? "Vehicle" : "Vehicles"
                ),
                .init(symbolName: "fuelpump", value: "\(statistics.fuelEntryCount)", label: "Fill-ups"),
                .init(
                    symbolName: "wrench.adjustable",
                    value: "\(statistics.serviceRecordCount)",
                    label: "Services"
                )
            ],
            premium: premiumBanner(isPremium: isPremium),
            rows: rows()
        )
    }

    private func identity(authState: AuthState, isPremium: Bool) -> ProfilePresentationModel.Identity {
        switch authState {
        case .authenticated(let profile):
            let name = profile.displayName ?? profile.email ?? "Signed in"
            return .init(
                initials: Self.initials(from: name),
                name: name,
                subtitle: profile.email ?? "",
                isPremium: isPremium,
                badgeTitle: isPremium ? "PREMIUM" : "FREE"
            )
        case .anonymous, .signedOut, .restoring:
            return .init(
                initials: "—",
                name: "Not signed in",
                subtitle: "Sign in to sync and use AI",
                isPremium: isPremium,
                badgeTitle: isPremium ? "PREMIUM" : "FREE"
            )
        }
    }

    private func premiumBanner(isPremium: Bool) -> ProfilePresentationModel.PremiumBanner? {
        isPremium
            ? .init(eyebrow: "PREMIUM", body: "Unlimited vehicles, AI scans, cloud backup.")
            : .init(eyebrow: "GO PREMIUM", body: "Unlimited vehicles, AI scans, cloud backup.")
    }

    private func rows() -> [ProfilePresentationModel.Row] {
        [
            // NOT in the Figma design — added because the app needs a way into Settings.
            .init(id: "settings", symbolName: "gearshape", title: "Settings",
                  trailing: .chevron, destination: .settings),
            .init(id: "language", symbolName: "globe", title: "Language",
                  trailing: .value(languageName), destination: .settingsSection(.language)),
            .init(id: "appearance", symbolName: "moon", title: "Dark mode",
                  trailing: .darkModeToggle, destination: nil),
            .init(id: "support", symbolName: "lifepreserver", title: "Support",
                  trailing: .chevron, destination: .supportSettings)
        ]
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "—" : letters.joined().uppercased()
    }
}
