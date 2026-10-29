import Foundation
import Observation

/// Display values for Service history (Figma 39).
struct ServiceHistoryPresentation: Equatable, Sendable {
    struct Hero: Equatable, Sendable {
        var eyebrow: String
        var title: String
        var tone: Tone
    }
    struct Row: Equatable, Sendable, Identifiable {
        var id: ServiceRecordID
        var date: String
        var title: String
        var meta: String
        var cost: String
        var isRepair: Bool
    }
    var hero: Hero
    var rows: [Row]
}

@MainActor
@Observable
final class ServiceHistoryViewModel {
    private(set) var state: ViewState<ServiceHistoryPresentation> = .idle

    private let query: QueryServiceHistory
    private let evaluateReminders: EvaluateReminderTriggers
    private let deleteRecord: DeleteServiceRecord
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let format: DisplayFormat
    private let clock: any ClockProviding

    init(
        query: QueryServiceHistory, evaluateReminders: EvaluateReminderTriggers, deleteRecord: DeleteServiceRecord,
        vehicles: any VehicleRepository, odometer: any OdometerRepository, format: DisplayFormat, clock: any ClockProviding
    ) {
        self.query = query
        self.evaluateReminders = evaluateReminders
        self.deleteRecord = deleteRecord
        self.vehicles = vehicles
        self.odometer = odometer
        self.format = format
        self.clock = clock
    }

    func load(vehicleID: VehicleID) async {
        if case .loaded = state {} else { state = .loading }
        do {
            async let records = query(ServiceQuery(vehicleID: vehicleID))
            async let evaluations = evaluateReminders(vehicleID: vehicleID)
            async let vehicle = vehicles.vehicle(id: vehicleID)
            async let reading = odometer.current(vehicleID: vehicleID)
            let loaded = try await records
            guard !loaded.isEmpty else { state = .empty; return }
            state = .loaded(present(
                records: loaded, evaluations: try await evaluations,
                vehicleName: try await vehicle?.displayName ?? "", odometer: try await reading?.value
            ))
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func delete(_ id: ServiceRecordID, vehicleID: VehicleID) async {
        try? await deleteRecord(id: id)
        await load(vehicleID: vehicleID)
    }

    func present(
        records: [ServiceRecord], evaluations: [ReminderEvaluation], vehicleName: String, odometer: Odometer?
    ) -> ServiceHistoryPresentation {
        let eyebrow = [vehicleName, odometer.map(format.odometer)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        let dateStyle = Date.FormatStyle(locale: format.locale, calendar: format.calendar, timeZone: format.calendar.timeZone)
            .day(.twoDigits).month(.abbreviated).year()
        let rows = records.map { record in
            ServiceHistoryPresentation.Row(
                id: record.id,
                date: record.date.formatted(dateStyle).uppercased(),
                title: Self.title(for: record),
                meta: [record.odometer.map(format.odometer), record.workshop].compactMap { $0 }.joined(separator: " · "),
                cost: format.money(record.totalCost, fractionDigits: nil),
                isRepair: record.isRepair
            )
        }
        return ServiceHistoryPresentation(hero: hero(evaluations, eyebrow: eyebrow), rows: rows)
    }

    /// "Oil & filter change", or "Oil change + 2" when one visit covered several jobs.
    static func title(for record: ServiceRecord) -> String {
        guard let first = record.items.first else { return String(localized: "Service") }
        let name = first.name.isEmpty ? first.type.displayName : first.name
        return record.items.count > 1 ? "\(name) + \(record.items.count - 1)" : name
    }

    /// The next service comes from the service-type reminders — never estimated from history.
    private func hero(_ evaluations: [ReminderEvaluation], eyebrow: String) -> ServiceHistoryPresentation.Hero {
        let service = evaluations.filter { !$0.reminder.kind.satisfyingServiceTypes.isEmpty }
        if let overdue = service.first(where: { if case .overdue = $0.status { return true }; return false }) {
            return .init(eyebrow: eyebrow, title: String(localized: "\(overdue.reminder.title) is overdue"), tone: .danger)
        }
        let byDistance = service.compactMap { e in e.progress?.remainingDistance.map { (e, $0) } }
            .min { $0.1.kilometers < $1.1.kilometers }
        if let (_, distance) = byDistance {
            return .init(eyebrow: eyebrow, title: String(localized: "Next service in \(format.distance(distance))"), tone: .accent)
        }
        let byDate = service.compactMap { e -> Date? in
            switch e.reminder.trigger {
            case .date(let t), .whicheverFirst(let t, _): t.dueDate
            case .mileage: nil
            }
        }.min()
        if let byDate {
            return .init(eyebrow: eyebrow, title: String(localized: "Next service on \(format.longDate(byDate))"), tone: .accent)
        }
        return .init(eyebrow: eyebrow, title: String(localized: "No service scheduled"), tone: .neutral)
    }
}

@MainActor
@Observable
final class AddServiceViewModel {
    var type: ServiceType = .oilChange {
        didSet { extras.remove(type) }
    }
    var date: Date
    var odometerText = ""
    var costText = ""
    var workshop = ""
    /// Further jobs done in the same visit. Each becomes its own item, which is what lets one
    /// visit satisfy several reminders at once.
    private(set) var extras: Set<ServiceType> = []
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var odometerHint: String?
    private(set) var currency: CurrencyCode

    private let vehicleID: VehicleID
    private let addServiceRecord: AddServiceRecord
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let router: AppRouter
    let format: DisplayFormat
    let now: Date

    init(
        vehicleID: VehicleID, addServiceRecord: AddServiceRecord, vehicles: any VehicleRepository,
        odometer: any OdometerRepository, router: AppRouter, currency: CurrencyCode, format: DisplayFormat, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addServiceRecord = addServiceRecord
        self.vehicles = vehicles
        self.odometer = odometer
        self.router = router
        self.currency = currency
        self.format = format
        self.now = now
        self.date = now
    }

    func prepare() async {
        if let vehicle = try? await vehicles.vehicle(id: vehicleID) { currency = vehicle.primaryCurrency }
        if let current = try? await odometer.current(vehicleID: vehicleID) {
            odometerHint = format.integer(current.value.kilometers)
        }
    }

    var extraOptions: [ServiceType] { ServiceType.allCases.filter { $0 != type && $0 != .other } }

    func toggle(_ extra: ServiceType) {
        if extras.contains(extra) { extras.remove(extra) } else { extras.insert(extra) }
    }

    var canSave: Bool { (NumberInput.decimal(costText) ?? -1) >= 0 && !costText.isEmpty && !isSaving }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let items = ([type] + ServiceType.allCases.filter(extras.contains)).map {
            ServiceItem(type: $0, name: $0.displayName)
        }
        let reading = NumberInput.double(odometerText).flatMap { $0 > 0 ? Odometer(kilometers: $0) : nil }
        do {
            _ = try await addServiceRecord(
                vehicleID: vehicleID, date: date, odometerValue: reading, items: items,
                workshop: workshop.trimmingCharacters(in: .whitespaces).isEmpty ? nil : workshop,
                totalCost: Money(NumberInput.decimal(costText) ?? 0, currency)
            )
            router.dismissModal()
        } catch {
            errorMessage = UserMessage.text(for: error)
        }
    }

    func cancel() { router.dismissModal() }
}
