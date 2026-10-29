import Foundation

extension FuelType {
    /// `rawValue.capitalized` turned `hybridPetrol` into "Hybridpetrol"; every screen that
    /// shows a fuel type uses this instead.
    var displayName: String {
        switch self {
        case .petrol: String(localized: "Petrol")
        case .diesel: String(localized: "Diesel")
        case .lpg: "LPG"
        case .cng: "CNG"
        case .hybridPetrol: String(localized: "Hybrid (petrol)")
        case .hybridDiesel: String(localized: "Hybrid (diesel)")
        case .electric: String(localized: "Electric")
        case .pluginHybrid: String(localized: "Plug-in hybrid")
        case .other: String(localized: "Other")
        }
    }
}
