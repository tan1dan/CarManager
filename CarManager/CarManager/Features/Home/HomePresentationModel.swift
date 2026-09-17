import Foundation

/// Display-ready values for the Home screen. Every string is already formatted; the View
/// performs no arithmetic and no date/number formatting.
struct HomePresentationModel: Equatable, Sendable {
    var greeting: String
    var title: String
    var unreadCount: Int
    var vehicle: VehicleCard
    var insight: InsightCard?
    var upcoming: [UpcomingRow]
    var tiles: [StatTile]

    struct VehicleCard: Equatable, Sendable {
        var name: String
        var subtitle: String
        var statusChip: String?
        var stats: [CompactStat]
    }

    /// A caption + value + unit triple. `value` is nil when the metric genuinely has no data —
    /// the view renders an em dash rather than a fabricated zero.
    struct CompactStat: Equatable, Sendable, Identifiable {
        var id: String { caption }
        var caption: String
        var value: String?
        var unit: String?
    }

    struct InsightCard: Equatable, Sendable {
        var eyebrow: String
        var body: String
    }

    struct UpcomingRow: Equatable, Sendable, Identifiable {
        enum Tone: Equatable, Sendable { case neutral, danger }

        var id: String
        var symbolName: String
        var tone: Tone
        var title: String
        var subtitle: String
        var destination: AppRoute?
    }

    struct StatTile: Equatable, Sendable, Identifiable {
        var id: String { label }
        var label: String
        var value: String?
        var delta: String?
        var deltaTone: UpcomingRow.Tone
    }

    static let placeholder = HomePresentationModel(
        greeting: "", title: "Your garage", unreadCount: 0,
        vehicle: VehicleCard(name: "", subtitle: "", statusChip: nil, stats: []),
        insight: nil, upcoming: [], tiles: []
    )
}

/// Maps the domain dashboard onto display values. Pure and injected with a clock, so it is
/// unit-testable without a view.
struct HomeFormatter: Sendable {
    let clock: any ClockProviding
    let unitSystem: UnitSystem

    func makeModel(
        from dashboard: HomeDashboard,
        userName: String?
    ) -> HomePresentationModel {
        HomePresentationModel(
            greeting: greeting(for: userName),
            title: "Your garage",
            unreadCount: dashboard.unreadNotificationCount,
            vehicle: vehicleCard(dashboard),
            insight: dashboard.insights.first.map {
                .init(eyebrow: "AI RECOMMENDATION", body: $0.body.isEmpty ? $0.headline : $0.body)
            },
            upcoming: upcomingRows(dashboard),
            tiles: tiles(dashboard)
        )
    }

    // MARK: - Pieces

    func greeting(for userName: String?) -> String {
        let hour = clock.calendar.component(.hour, from: clock.now)
        let period = switch hour {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        guard let userName, !userName.isEmpty else { return period }
        return "\(period), \(userName)"
    }

    private func vehicleCard(_ dashboard: HomeDashboard) -> HomePresentationModel.VehicleCard {
        let vehicle = dashboard.vehicle
        let subtitleParts = [
            vehicle.year.map(String.init),
            vehicle.trim,
            vehicle.fuelType.rawValue.capitalized
        ].compactMap { $0 }

        return .init(
            name: vehicle.displayName,
            subtitle: subtitleParts.joined(separator: " · "),
            // The health score is a Phase-6 calculator; no chip until it exists.
            statusChip: nil,
            stats: [
                .init(
                    caption: "MILEAGE",
                    value: dashboard.currentOdometer.map { distanceValue($0.value) },
                    unit: distanceUnit
                ),
                // Next service needs the reminder projector; the row shows the nearest
                // mileage-triggered reminder when there is one.
                .init(
                    caption: "NEXT SVC",
                    value: nextServiceDistance(dashboard).map(distanceValue),
                    unit: distanceUnit
                ),
                .init(caption: "HEALTH", value: nil, unit: "%")
            ]
        )
    }

    private func nextServiceDistance(_ dashboard: HomeDashboard) -> Distance? {
        dashboard.upcomingReminders
            .compactMap(\.progress?.remainingDistance)
            .min { $0.kilometers < $1.kilometers }
    }

    private func upcomingRows(_ dashboard: HomeDashboard) -> [HomePresentationModel.UpcomingRow] {
        let reminders = dashboard.upcomingReminders.map { evaluation in
            HomePresentationModel.UpcomingRow(
                id: "reminder-\(evaluation.reminder.id.raw.uuidString)",
                symbolName: symbol(for: evaluation.reminder.kind),
                tone: needsAttention(evaluation.status) ? .danger : .neutral,
                title: evaluation.reminder.title,
                subtitle: subtitle(for: evaluation),
                destination: .reminderDetail(evaluation.reminder.id)
            )
        }

        let documents = dashboard.expiringDocuments.compactMap { item -> HomePresentationModel.UpcomingRow? in
            guard let subtitle = subtitle(for: item.status) else { return nil }
            return HomePresentationModel.UpcomingRow(
                id: "document-\(item.document.id.raw.uuidString)",
                symbolName: "checkmark.shield",
                tone: isExpired(item.status) ? .danger : .neutral,
                title: item.document.name,
                subtitle: subtitle,
                destination: .documentDetail(item.document.id)
            )
        }

        return Array((reminders + documents).prefix(4))
    }

    private func tiles(_ dashboard: HomeDashboard) -> [HomePresentationModel.StatTile] {
        [
            // Both figures come from the analytics engine, which is not built yet.
            .init(label: "This month", value: nil, delta: nil, deltaTone: .neutral),
            .init(label: "Avg. L/100km", value: nil, delta: nil, deltaTone: .neutral)
        ]
    }

    // MARK: - Units

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

    // MARK: - Copy

    /// Attention tone once a reminder is inside its lead window. `ReminderEvaluator` reports
    /// `daysRemaining` only within that window, so this needs no extra thresholds.
    private func needsAttention(_ status: ReminderStatus) -> Bool {
        switch status {
        case .overdue, .due: true
        case .upcoming(let daysRemaining): daysRemaining != nil
        case .indeterminate: false
        }
    }

    private func isExpired(_ status: DocumentExpiryStatus) -> Bool {
        if case .expired = status { return true }
        return false
    }

    private func subtitle(for evaluation: ReminderEvaluation) -> String {
        if let remaining = evaluation.progress?.remainingDistance {
            return "Due in \(distanceValue(remaining)) \(distanceUnit)"
        }
        return switch evaluation.status {
        case .overdue(let days?): "Overdue by \(days) days"
        case .overdue: "Overdue"
        case .due: "Due now"
        case .upcoming(let days?): "Due in \(days) days"
        case .upcoming: "Scheduled"
        case .indeterminate: "Add a mileage reading"
        }
    }

    private func subtitle(for status: DocumentExpiryStatus) -> String? {
        switch status {
        case .expiringSoon(let days): "Expires in \(days) days"
        case .expired(let days): "Expired \(days) days ago"
        case .valid, .noExpiry: nil
        }
    }

    /// lucide icons in the design map onto the closest SF Symbols.
    private func symbol(for kind: ReminderKind) -> String {
        switch kind {
        case .oilChange: "drop"
        case .filterReplacement: "air.purifier"
        case .tireChange, .tirePressure: "circle.circle"
        case .technicalInspection: "checkmark.seal"
        case .insurance: "exclamationmark.shield"
        case .battery: "minus.plus.batteryblock"
        case .brakePads: "hexagon"
        case .timingBelt: "gearshape.2"
        case .vehicleTax: "banknote"
        case .custom: "bell"
        }
    }
}
