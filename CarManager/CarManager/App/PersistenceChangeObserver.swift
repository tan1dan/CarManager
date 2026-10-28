import Foundation
import CoreData

/// Records written by iCloud import — on a fresh install, after signing back in, or from
/// another device — land in the store after the app has already loaded the garage. Core Data
/// posts `NSPersistentStoreRemoteChange` for each such write; this turns a burst of them into
/// one reload of the vehicle store, whose `revision` the screens watch.
@MainActor
final class PersistenceChangeObserver {
    private var task: Task<Void, Never>?
    private var pending: Task<Void, Never>?

    func start(onChange: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        task = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                self?.schedule(onChange)
            }
        }
    }

    /// Imports arrive in bursts of dozens of notifications; wait until they settle.
    private func schedule(_ onChange: @escaping @MainActor () async -> Void) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await onChange()
        }
    }
}
