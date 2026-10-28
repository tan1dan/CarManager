import Testing
import Foundation
@testable import CarManager

/// Dashboard scans and damage analyses against the REAL SwiftData stack (in-memory, no CloudKit).
@Suite("Saved scans")
struct ScanPersistenceTests {
    private let clock = FixedClock()

    private func makeRepository() -> (SwiftDataScanRepository, PersistenceActor) {
        let (container, _) = PersistenceContainer.make(inMemory: true)
        let store = PersistenceActor(modelContainer: container)
        return (SwiftDataScanRepository(store: store, receipts: InMemoryScanRepository(store: InMemoryStore())), store)
    }

    private func dashboardScan(vehicle: VehicleID?, minutesAgo: Double = 0) -> DashboardScan {
        DashboardScan(
            vehicleID: vehicle, imageRef: FileRef(relativePath: "scan/a.jpg", checksum: "1"),
            findings: [DashboardFinding(warningName: "Oil pressure", likelyCauses: ["Low oil", "Pump"], severity: .stopDriving,
                                        recommendedAction: "Stop now", drivingSafety: .doNotDrive, confidence: 0.9)],
            createdAt: clock.now.addingTimeInterval(-minutesAgo * 60), summary: "One red light"
        )
    }

    private func damage(vehicle: VehicleID, minutesAgo: Double = 0) -> DamageAnalysis {
        DamageAnalysis(
            vehicleID: vehicle, imageRefs: [FileRef(relativePath: "scan/b.jpg", checksum: "2")],
            findings: [DamageFinding(damageType: "Scratch", severity: .moderate, suggestedRepair: "Repaint",
                                     cosmeticRepairPossible: false,
                                     estimatedCost: CostEstimateRange(low: Money(Decimal(string: "200.50")!, .eur),
                                                                      high: Money(450, .eur), confidence: 0.6))],
            createdAt: clock.now.addingTimeInterval(-minutesAgo * 60), summary: "Rear bumper"
        )
    }

    @Test("A dashboard scan survives the round trip with every field intact")
    func dashboardRoundTrip() async throws {
        let (repo, _) = makeRepository()
        let original = dashboardScan(vehicle: VehicleID())
        try await repo.insert(original)
        let loaded = try #require(try await repo.dashboardScan(id: original.id))
        #expect(loaded == original)
    }

    @Test("A damage analysis survives the round trip, cost range and all")
    func damageRoundTrip() async throws {
        let (repo, _) = makeRepository()
        let original = damage(vehicle: VehicleID())
        try await repo.insert(original)
        let loaded = try #require(try await repo.damageAnalysis(id: original.id))
        #expect(loaded == original)
        #expect(loaded.findings.first?.estimatedCost?.low.amount == Decimal(string: "200.50"))
    }

    @Test("History mixes both kinds, newest first, and respects the limit")
    func history() async throws {
        let (repo, _) = makeRepository()
        let car = VehicleID()
        try await repo.insert(dashboardScan(vehicle: car, minutesAgo: 30))
        try await repo.insert(damage(vehicle: car, minutesAgo: 10))
        try await repo.insert(dashboardScan(vehicle: nil, minutesAgo: 20))

        let all = try await ListScanHistory(scans: repo)()
        #expect(all.map(\.createdAt) == all.map(\.createdAt).sorted(by: >))
        #expect(all.count == 3)
        if case .damage = all.first {} else { Issue.record("expected the damage analysis first") }
        #expect(try await ListScanHistory(scans: repo)(limit: 2).count == 2)
        #expect(try await ListScanHistory(scans: repo)(vehicleID: car).count == 2)
    }

    @Test("Deleting a scan deletes its photo too")
    func deleteScan() async throws {
        let (repo, _) = makeRepository()
        let files = InMemoryFileStorage()
        let ref = try await files.store(Data("jpg".utf8), preferredName: "scan", kind: .scan)
        var scan = dashboardScan(vehicle: nil)
        scan = DashboardScan(id: scan.id, vehicleID: nil, imageRef: ref, findings: scan.findings, createdAt: scan.createdAt)
        try await repo.insert(scan)

        try await DeleteScan(scans: repo, files: files)(.dashboard(scan))
        #expect(try await repo.dashboardScan(id: scan.id) == nil)
        await #expect(throws: (any Error).self) { _ = try await files.read(ref) }
    }

    @Test("Deleting a vehicle removes its damage analyses and unlinks its dashboard scans")
    func vehicleCascade() async throws {
        let (repo, store) = makeRepository()
        let car = Vehicle(brand: "Audi", model: "A4", fuelType: .diesel, createdAt: clock.now, updatedAt: clock.now)
        try await store.saveVehicle(car)
        let analysis = damage(vehicle: car.id)
        let scan = dashboardScan(vehicle: car.id)
        try await repo.insert(analysis)
        try await repo.insert(scan)

        let orphaned = try await store.deleteVehicle(id: car.id)
        #expect(orphaned.contains(analysis.imageRefs[0]))
        #expect(try await repo.damageAnalysis(id: analysis.id) == nil)
        #expect(try await repo.dashboardScan(id: scan.id)?.vehicleID == nil)
    }

    @Test("Receipt scans are still NOT persisted: they live only until confirmed")
    func receiptsStayInMemory() async throws {
        let (repo, store) = makeRepository()
        let receipt = ReceiptScan(vehicleID: VehicleID(), imageRef: FileRef(relativePath: "r.jpg"),
                                  draft: ReceiptDraft(), createdAt: clock.now)
        try await repo.upsert(receipt)
        #expect(try await repo.receiptScan(id: receipt.id) != nil)
        // Nothing receipt-shaped exists in the SwiftData store.
        #expect(try await store.dashboardScans(vehicleID: nil).isEmpty)
    }

    @Test("A scan made through the use case is saved, summary included")
    func useCaseSaves() async throws {
        let (repo, _) = makeRepository()
        struct Vision: VisionAnalysisProvider {
            func analyze(_ request: VisionAnalysisRequest) async throws -> VisionAnalysisResult {
                .dashboard([DashboardFinding(warningName: "ABS", severity: .soon)], summary: "ABS light on")
            }
        }
        let scan = try await ScanDashboard(vision: Vision(), preprocessor: StubImagePreprocessor(),
                                           files: InMemoryFileStorage(), scans: repo, clock: clock)(imageData: Data([1]), vehicleID: nil)
        let saved = try #require(try await repo.dashboardScan(id: scan.id))
        #expect(saved.summary == "ABS light on")
        #expect(saved.findings.map(\.warningName) == ["ABS"])
    }
}
