import Testing
import Foundation
@testable import CarManager

/// Photos and documents stored next to the records, so iCloud brings them back after a reinstall.
@Suite("Synced files")
struct SyncedFileStorageTests {
    private let clock = FixedClock()
    private let bytes = Data("photo bytes".utf8)

    private func makeStore() -> PersistenceActor {
        PersistenceActor(modelContainer: PersistenceContainer.make(inMemory: true).container)
    }

    /// A fresh, empty folder — what a reinstalled app or a second device starts with.
    private func emptyDisk() -> DiskFileStorage {
        DiskFileStorage(root: FileManager.default.temporaryDirectory.appendingPathComponent("files-\(UUID().uuidString)"))
    }

    @Test("A scan photo comes back after a reinstall: empty disk, same synced store")
    func survivesReinstall() async throws {
        let store = makeStore()
        let ref = try await SyncedFileStorage(disk: emptyDisk(), store: store, clock: clock)
            .store(bytes, preferredName: "damage", kind: .scan)

        let reinstalled = SyncedFileStorage(disk: emptyDisk(), store: store, clock: clock)
        #expect(await reinstalled.availability(ref) == .local)
        #expect(try await reinstalled.read(ref) == bytes)
    }

    @Test("Receipt photos stay on the device: the scan behind them is never kept")
    func receiptsAreNotSynced() async throws {
        let store = makeStore()
        let ref = try await SyncedFileStorage(disk: emptyDisk(), store: store, clock: clock)
            .store(bytes, preferredName: "receipt", kind: .receipt)
        #expect(try await store.fileData(id: ref.id) == nil)
    }

    @Test("Deleting a file removes the synced copy too")
    func deleteRemovesSyncedCopy() async throws {
        let store = makeStore()
        let files = SyncedFileStorage(disk: emptyDisk(), store: store, clock: clock)
        let ref = try await files.store(bytes, preferredName: "doc", kind: .document)
        try await files.delete(ref)

        #expect(try await store.fileData(id: ref.id) == nil)
        await #expect(throws: DomainError.self) { try await files.read(ref) }
    }

    @Test("Files saved before syncing existed are copied up once, under the same ref")
    func uploadsLocalOnlyFiles() async throws {
        let disk = emptyDisk()
        let old = try await disk.store(bytes, preferredName: "damage", kind: .scan)
        let receipt = try await disk.store(bytes, preferredName: "receipt", kind: .receipt)
        let store = makeStore()
        let files = SyncedFileStorage(disk: disk, store: store, clock: clock)

        #expect(await files.uploadLocalOnlyFiles() == 1)
        #expect(await files.uploadLocalOnlyFiles() == 0)
        #expect(try await store.fileData(id: old.id) == bytes)
        #expect(try await store.fileData(id: receipt.id) == nil)
    }
}
