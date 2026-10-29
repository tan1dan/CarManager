import Foundation
import SwiftData
import CloudKit
import CoreData

/// How the store ended up being opened. The UI needs this: a user whose data is not syncing
/// deserves to be told, not left guessing.
enum PersistenceMode: Sendable, Equatable {
    /// On disk and mirrored to the user's private CloudKit database.
    case cloudKit
    /// On disk, no mirroring — no iCloud account, or the entitlement is missing.
    case localOnly(reason: String)
    /// Nothing is written to disk. Tests and previews only.
    case inMemory
}

enum PersistenceContainer {
    /// The private database of this container. It belongs to the user's iCloud account:
    /// Apple never gives the developer access, which is exactly the point of A-03.
    static let cloudKitContainerID = "iCloud.IvanZnak.CarManager"

    static func make(inMemory: Bool = false) -> (container: ModelContainer, mode: PersistenceMode) {
        let schema = Schema(PersistenceSchema.models)

        if inMemory {
            let configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
            )
            // An in-memory store cannot realistically fail; if it does, the schema is broken
            // and every other path would fail too.
            let container = try! ModelContainer(for: schema, configurations: [configuration])
            return (container, .inMemory)
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") {
            initializeCloudKitSchema()
        }
        #endif

        // 1. The real thing: on disk, mirrored to CloudKit.
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
            return (try ModelContainer(for: schema, configurations: [configuration]), .cloudKit)
        } catch {
            // 2. Same file, no mirroring. Hit when the build has no iCloud entitlement or the
            //    device has no iCloud account. The garage still works offline — that is the
            //    whole promise of the app — and the data is picked up by sync later.
            let reason = String(describing: error)
            do {
                let configuration = ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .none
                )
                return (try ModelContainer(for: schema, configurations: [configuration]), .localOnly(reason: reason))
            } catch {
                // 3. The disk itself refused. Keep the app usable for this session rather than
                //    crashing on launch, and make sure the mode says the data is not kept.
                assertionFailure("Local store unavailable: \(error)")
                let configuration = ModelConfiguration(
                    schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
                )
                let container = try! ModelContainer(for: schema, configurations: [configuration])
                return (container, .localOnly(reason: "Storage unavailable: \(error)"))
            }
        }
    }
}

#if DEBUG
extension PersistenceContainer {
    /// Creates every record type, with every field, in the container's DEVELOPMENT
    /// environment — without having to enter one of each kind of record by hand. Apple's
    /// documented route for SwiftData: build the same model as Core Data, let
    /// `NSPersistentCloudKitContainer` push the schema, then close that store before SwiftData
    /// opens it.
    ///
    /// Run once from Xcode with the `-initCloudKitSchema` launch argument, on a device or
    /// simulator signed in to iCloud, then deploy the schema to Production in the CloudKit
    /// Console. DEBUG only: a shipped build never touches the schema.
    static func initializeCloudKitSchema() {
        let configuration = ModelConfiguration(schema: Schema(PersistenceSchema.models), cloudKitDatabase: .private(cloudKitContainerID))
        autoreleasepool {
            guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PersistenceSchema.models) else {
                print("☁️ CloudKit schema: could not build the Core Data model")
                return
            }
            let description = NSPersistentStoreDescription(url: configuration.url)
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
            description.shouldAddStoreAsynchronously = false

            let container = NSPersistentCloudKitContainer(name: "CarManager", managedObjectModel: model)
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError {
                print("☁️ CloudKit schema: store failed to load — \(loadError)")
                return
            }
            do {
                try container.initializeCloudKitSchema()
                let names = model.entities.compactMap(\.name).sorted().map { "CD_" + $0 }
                print("☁️ CloudKit schema initialized: \(names.count) record types — \(names.joined(separator: ", "))")
            } catch {
                print("☁️ CloudKit schema: initialization failed — \(error)")
            }
            // SwiftData opens the same file next; it must not be held open here.
            for store in container.persistentStoreCoordinator.persistentStores {
                try? container.persistentStoreCoordinator.remove(store)
            }
        }
    }
}
#endif

/// Reports what SwiftData's CloudKit mirroring is actually doing.
///
/// There is no public API for "is it syncing right now", so this combines the mode the store
/// opened in with the iCloud account status — enough to tell the user the truth: syncing,
/// not syncing and why, or signed out.
struct CloudKitSyncStatusProvider: SyncStatusProviding {
    let mode: PersistenceMode
    let containerID: String

    init(mode: PersistenceMode, containerID: String = PersistenceContainer.cloudKitContainerID) {
        self.mode = mode
        self.containerID = containerID
    }

    func currentStatus() async -> SyncState {
        switch mode {
        case .inMemory:
            return .unavailable(reason: String(localized: "Off — in-memory store"))
        case .localOnly:
            // The full reason is a Core Data error dump; the row needs a phrase.
            return .unavailable(reason: String(localized: "Off — this device only"))
        case .cloudKit:
            break
        }

        do {
            switch try await CKContainer(identifier: containerID).accountStatus() {
            case .available:
                return .idle(lastSyncedAt: nil)
            case .noAccount:
                return .unavailable(reason: String(localized: "No iCloud account"))
            case .restricted:
                return .unavailable(reason: String(localized: "Restricted"))
            case .couldNotDetermine, .temporarilyUnavailable:
                return .failed(message: String(localized: "Temporarily unavailable"), willRetry: true)
            @unknown default:
                return .unavailable(reason: String(localized: "Unknown state"))
            }
        } catch {
            return .failed(message: error.localizedDescription, willRetry: true)
        }
    }
}
