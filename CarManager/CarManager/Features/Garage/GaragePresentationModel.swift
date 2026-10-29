import Foundation

/// Display-ready values for the Garage screen (Figma node 3:4196).
///
/// Every vehicle is the same full card; the primary one leads and wears the "Primary" badge,
/// the others offer "Make primary" in the same spot.
struct GaragePresentationModel: Equatable, Sendable {
    var title: String
    /// Primary first, then the rest in garage order.
    var cards: [VehicleCard]

    var primary: VehicleCard? { cards.first(where: \.isPrimary) }

    struct VehicleCard: Equatable, Sendable, Identifiable {
        var id: VehicleID
        var subtitle: String
        var name: String
        var isPrimary: Bool
        var stats: [Stat]
    }

    /// `value` is nil when the vehicle simply has not recorded it — the view renders an em
    /// dash instead of inventing a figure.
    struct Stat: Equatable, Sendable, Identifiable {
        var id: String { caption }
        var caption: String
        var value: String?
        var unit: String?
    }

    static let empty = GaragePresentationModel(title: String(localized: "Garage"), cards: [])
}

/// Pure mapping from `[VehicleSummary]` onto display values.
struct GarageFormatter: Sendable {
    let unitSystem: UnitSystem

    func makeModel(from summaries: [VehicleSummary]) -> GaragePresentationModel {
        // The primary vehicle leads; if none is flagged the first one is treated as primary.
        let primarySummary = summaries.first(where: \.isDefault) ?? summaries.first
        let others = summaries.filter { $0.id != primarySummary?.id }

        return GaragePresentationModel(
            title: String(localized: "Garage"),
            cards: (primarySummary.map { [$0] } ?? []).map { card($0, isPrimary: true) }
                + others.map { card($0, isPrimary: false) }
        )
    }

    private func card(_ summary: VehicleSummary, isPrimary: Bool) -> GaragePresentationModel.VehicleCard {
        .init(
            id: summary.id,
            subtitle: subtitle(for: summary),
            name: summary.displayName,
            isPrimary: isPrimary,
            stats: [
                .init(
                    caption: String(localized: "MILEAGE"),
                    value: summary.currentOdometer.map { distanceValue($0.value) },
                    unit: distanceUnit
                ),
                .init(
                    caption: String(localized: "FUEL"),
                    value: summary.fuelType.displayName,
                    unit: nil
                ),
                .init(caption: "VIN", value: shortVIN(summary.vin), unit: nil)
            ]
        )
    }

    private func subtitle(for summary: VehicleSummary) -> String {
        [summary.year.map(String.init), summary.fuelType.displayName]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The design truncates the VIN to fit the chip. Returns nil when no VIN was entered,
    /// which the chip renders as an em dash.
    private func shortVIN(_ vin: String?) -> String? {
        guard let vin = VehicleValidator.normalizedVIN(vin) else { return nil }
        return vin.count > 6 ? String(vin.prefix(5)) + "…" : vin
    }

    private var distanceUnit: String { DisplayFormat(unitSystem: unitSystem).distanceUnit }

    private func distanceValue(_ distance: Distance) -> String {
        let raw = unitSystem == .metric ? distance.kilometers : distance.miles
        return Self.integerFormatter.string(from: NSNumber(value: raw)) ?? "\(Int(raw))"
    }

    private static let integerFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
