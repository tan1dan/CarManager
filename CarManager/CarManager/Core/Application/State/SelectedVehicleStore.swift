import Foundation
import Observation

/// The ActiveVehicle concept, decoupled from UI. Lives in Application, imports only
/// Foundation + Observation, and has no idea SwiftUI exists.
@MainActor
@Observable
public final class SelectedVehicleStore {
    public enum LoadState: Equatable, Sendable { case loading, loaded, failed(String) }

    public private(set) var summaries: [VehicleSummary] = []
    public private(set) var selected: Vehicle?
    public private(set) var state: LoadState = .loading

    private let vehicles: any VehicleRepository
    private let preferences: any PreferencesProviding

    public init(vehicles: any VehicleRepository, preferences: any PreferencesProviding) {
        self.vehicles = vehicles
        self.preferences = preferences
    }

    public var hasVehicles: Bool { !summaries.isEmpty }
    public var vehicleCount: Int { summaries.count }

    public func bootstrap() async { await refresh() }

    public func refresh() async {
        do {
            summaries = try await vehicles.summaries()
            selected = try await resolveSelection()
            state = .loaded
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Deterministic resolution order:
    /// 1. the stored preference, if it still exists
    /// 2. the vehicle flagged isDefault
    /// 3. the most recently updated vehicle
    /// 4. nil → empty-garage state
    private func resolveSelection() async throws -> Vehicle? {
        if let preferred = preferences.defaultVehicleID,
           let vehicle = try await vehicles.vehicle(id: preferred) {
            return vehicle
        }
        if let flagged = try await vehicles.defaultVehicle() { return flagged }
        let all = try await vehicles.all()
        return all.sorted { $0.updatedAt > $1.updatedAt }.first
    }

    public func select(_ id: VehicleID) async {
        preferences.defaultVehicleID = id
        selected = try? await vehicles.vehicle(id: id)
        await refresh()
    }
}
