import Foundation

/// Files that follow the records into iCloud.
///
/// Every file is written twice: to disk, which is the fast cache every read hits first, and to
/// SwiftData (`SDStoredFile`), which CloudKit mirrors to the user's private database. After a
/// reinstall or on a new device the disk is empty, so a read falls back to the synced copy and
/// puts it back on disk.
///
/// Receipt photos stay on disk only: a receipt scan is thrown away once the user confirms or
/// discards it, so its photo has no record to come back with.
public actor SyncedFileStorage: FileStorage {
    private let disk: DiskFileStorage
    private let store: PersistenceActor
    private let clock: any ClockProviding
    static let syncedKinds: [FileKind] = [.vehiclePhoto, .document, .thumbnail, .scan]

    init(disk: DiskFileStorage = DiskFileStorage(), store: PersistenceActor, clock: any ClockProviding) {
        self.disk = disk
        self.store = store
        self.clock = clock
    }

    public func store(_ data: Data, preferredName: String, kind: FileKind) async throws -> FileRef {
        let ref = try await disk.store(data, preferredName: preferredName, kind: kind)
        if Self.syncedKinds.contains(kind) {
            try await store.storeFile(ref, kind: kind, data: data, at: clock.now)
        }
        return ref
    }

    public func read(_ ref: FileRef) async throws -> Data {
        if let data = try? await disk.read(ref) { return data }
        guard let data = try await store.fileData(id: ref.id) else { throw DomainError.document(.fileNotFound) }
        try? await disk.write(data, at: ref)
        return data
    }

    public func availability(_ ref: FileRef) async -> FileAvailability {
        if await disk.availability(ref) == .local { return .local }
        // A record whose bytes are not here yet is still on its way from iCloud.
        return (try? await store.fileData(id: ref.id)) != nil ? .local : .remote
    }

    public func delete(_ ref: FileRef) async throws {
        try await disk.delete(ref)
        try await store.deleteFile(id: ref.id)
    }

    /// Files saved before this storage existed live on disk only. Copies them into the synced
    /// store once, so they survive a reinstall too. Returns how many were copied.
    @discardableResult
    func uploadLocalOnlyFiles() async -> Int {
        guard let synced = try? await store.storedFileIDs() else { return 0 }
        var copied = 0
        for kind in Self.syncedKinds {
            for ref in await disk.refs(of: kind) where !synced.contains(ref.id) {
                guard let data = try? await disk.read(ref) else { continue }
                if (try? await store.storeFile(ref, kind: kind, data: data, at: clock.now)) != nil { copied += 1 }
            }
        }
        return copied
    }
}
