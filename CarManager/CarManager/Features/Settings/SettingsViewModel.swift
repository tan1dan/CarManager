import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var presentation: SettingsPresentationModel = .placeholder
    /// Transient feedback shown under the list (export result, gate refusal).
    private(set) var message: String?

    private let formatter: SettingsFormatter
    private let preferences: any PreferencesProviding
    private let authStore: AuthSessionStore
    private let featureGate: FeatureGate
    private let exportPDF: ExportVehicleHistoryPDF
    private let router: AppRouter

    init(
        formatter: SettingsFormatter,
        preferences: any PreferencesProviding,
        authStore: AuthSessionStore,
        featureGate: FeatureGate,
        exportPDF: ExportVehicleHistoryPDF,
        router: AppRouter
    ) {
        self.formatter = formatter
        self.preferences = preferences
        self.authStore = authStore
        self.featureGate = featureGate
        self.exportPDF = exportPDF
        self.router = router
        refresh()
    }

    func refresh() {
        presentation = formatter.makeModel(
            authState: authStore.state,
            unitSystem: preferences.unitSystem,
            telemetryEnabled: preferences.telemetryEnabled
        )
    }

    /// Premium-gated. A refusal routes to the paywall rather than surfacing an error.
    func exportPDF(vehicleID: VehicleID?) async {
        message = nil
        let access = featureGate.evaluate(.pdfExport)
        guard access.isAllowed else {
            if let reason = access.lockReason {
                router.present(.paywall(RouteGuard.paywallContext(for: .pdfExport, reason: reason)))
            }
            return
        }
        guard let vehicleID else {
            message = "Add a vehicle first."
            return
        }
        do {
            let url = try await exportPDF(vehicleID: vehicleID, period: .allTime)
            router.present(.shareExport(url))
        } catch {
            message = ErrorPresenter.present(error).messageKey
        }
    }
}
