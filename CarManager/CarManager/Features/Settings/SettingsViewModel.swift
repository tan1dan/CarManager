import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var presentation: SettingsPresentationModel = .placeholder
    /// Transient feedback shown under the list.
    private(set) var message: String?

    private let formatter: SettingsFormatter
    private let preferences: any PreferencesProviding
    private let authStore: AuthSessionStore
    private let syncStore: SyncStatusStore

    init(
        formatter: SettingsFormatter,
        preferences: any PreferencesProviding,
        authStore: AuthSessionStore,
        syncStore: SyncStatusStore
    ) {
        self.formatter = formatter
        self.preferences = preferences
        self.authStore = authStore
        self.syncStore = syncStore
        refresh()
    }

    /// Asks CloudKit for the current account state, then rebuilds the rows.
    func load() async {
        await syncStore.refresh()
        refresh()
    }

    func refresh() {
        presentation = formatter.makeModel(
            authState: authStore.state,
            unitSystem: preferences.unitSystem,
            telemetryEnabled: preferences.telemetryEnabled,
            syncState: syncStore.state
        )
    }
}
