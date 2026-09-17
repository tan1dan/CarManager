import Foundation
import Observation

@MainActor
@Observable
final class ServiceHistoryViewModel {
    private(set) var state: ViewState<[ServiceRecord]> = .idle

    private let query: QueryServiceHistory
    init(query: QueryServiceHistory) { self.query = query }

    func load(vehicleID: VehicleID, filterTypes: Set<ServiceType>? = nil) async {
        state = .loading
        do {
            let records = try await query(ServiceQuery(vehicleID: vehicleID, types: filterTypes))
            state = records.isEmpty ? .empty : .loaded(records)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}

@MainActor
@Observable
final class AddServiceViewModel {
    var workshop = ""
    var costText = ""
    private(set) var selectedTypes: Set<ServiceType> = [.oilChange]
    private(set) var state: ViewState<ServiceRecord> = .idle
    /// Which reminders this record auto-completed — surfaced as confirmation.
    private(set) var completedReminders: [ReminderID] = []

    private let vehicleID: VehicleID
    private let addServiceRecord: AddServiceRecord
    private let router: AppRouter
    private let currency: CurrencyCode
    private let now: Date

    init(
        vehicleID: VehicleID, addServiceRecord: AddServiceRecord, router: AppRouter,
        currency: CurrencyCode, now: Date
    ) {
        self.vehicleID = vehicleID
        self.addServiceRecord = addServiceRecord
        self.router = router
        self.currency = currency
        self.now = now
    }

    func toggle(_ type: ServiceType) {
        if selectedTypes.contains(type) { selectedTypes.remove(type) } else { selectedTypes.insert(type) }
    }

    func save() async {
        state = .loading
        let items = selectedTypes.map { ServiceItem(type: $0, name: $0.rawValue) }
        do {
            let output = try await addServiceRecord(
                vehicleID: vehicleID, date: now, odometerValue: nil, items: items,
                workshop: workshop.isEmpty ? nil : workshop,
                totalCost: Money(Decimal(Double(costText) ?? 0), currency)
            )
            completedReminders = output.completedReminderIDs
            state = .loaded(output.record)
            router.dismissModal()
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }
}
