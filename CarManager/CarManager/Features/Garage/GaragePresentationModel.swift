import Foundation

/// Display-ready values for the Garage screen (Figma node 3:4196).
///
/// The design shows the primary vehicle as an expanded card and every other vehicle as a
/// dimmed collapsed row, so the model splits them rather than making the view decide.
struct GaragePresentationModel: Equatable, Sendable {
    var title: String
    var primary: PrimaryCard?
    var others: [CollapsedRow]

    struct PrimaryCard: Equatable, Sendable {
        var id: VehicleID
        var subtitle: String
        var name: String
        var chip: String
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

    struct CollapsedRow: Equatable, Sendable, Identifiable {
        var id: VehicleID
        var subtitle: String
        var name: String
    }

    static let empty = GaragePresentationModel(title: "Garage", primary: nil, others: [])
}

/// Pure mapping from `[VehicleSummary]` onto display values.
struct GarageFormatter: Sendable {
    let unitSystem: UnitSystem

    func makeModel(from summaries: [VehicleSummary]) -> GaragePresentationModel {
        // The primary vehicle leads; if none is flagged the first is shown expanded so the
        // screen never renders as a list of collapsed rows with no head.
        let primarySummary = summaries.first(where: \.isDefault) ?? summaries.first
        let others = summaries.filter { $0.id != primarySummary?.id }

        return GaragePresentationModel(
            title: "Garage",
            primary: primarySummary.map(primaryCard),
            others: others.map {
                CollapsedRowBuilder.row(from: $0, subtitle: subtitle(for: $0))
            }
        )
    }

    private func primaryCard(_ summary: VehicleSummary) -> GaragePresentationModel.PrimaryCard {
        .init(
            id: summary.id,
            subtitle: subtitle(for: summary),
            name: summary.displayName,
            chip: "Primary",
            stats: [
                .init(
                    caption: "MILEAGE",
                    value: summary.currentOdometer.map { distanceValue($0.value) },
                    unit: distanceUnit
                ),
                .init(
                    caption: "FUEL",
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

    private var distanceUnit: String { unitSystem == .metric ? "km" : "mi" }

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

private enum CollapsedRowBuilder {
    static func row(from summary: VehicleSummary, subtitle: String) -> GaragePresentationModel.CollapsedRow {
        .init(id: summary.id, subtitle: subtitle, name: summary.displayName)
    }
}
