import Foundation
import Observation

/// Sync status is a badge, never a blocker. It appears in Settings and — for non-retryable
/// failures only — as a dismissible notice. It never gates a save button.
@MainActor
@Observable
public final class SyncStatusStore {
    public private(set) var state: SyncState = .idle(lastSyncedAt: nil)

    private let provider: any SyncStatusProviding

    public init(provider: any SyncStatusProviding) { self.provider = provider }

    public func refresh() async { state = await provider.currentStatus() }
}
