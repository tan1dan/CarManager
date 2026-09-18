import Foundation

extension FuelType {
    /// `rawValue.capitalized` turned `hybridPetrol` into "Hybridpetrol"; every screen that
    /// shows a fuel type uses this instead.
    var displayName: String {
        switch self {
        case .petrol: "Petrol"
        case .diesel: "Diesel"
        case .lpg: "LPG"
        case .cng: "CNG"
        case .hybridPetrol: "Hybrid (petrol)"
        case .hybridDiesel: "Hybrid (diesel)"
        case .electric: "Electric"
        case .pluginHybrid: "Plug-in hybrid"
        case .other: "Other"
        }
    }
}
