import SwiftUI

/// The central Add action. Each row is guard-evaluated individually, so a free user sees the
/// paywall on Scan Receipt but the editor on Add Fuel.
struct QuickLogView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            List {
                Text("What's new?")

                Button("Add Fuel") { replace(.fuelEditor(.create(vehicleID))) }
                    .accessibilityIdentifier("quickLogAddFuel")
                Button("Add Service") { replace(.serviceEditor(.create(vehicleID))) }
                    .accessibilityIdentifier("quickLogAddService")
                Button("Add Expense") { replace(.expenseEditor(.create(vehicleID))) }
                    .accessibilityIdentifier("quickLogAddExpense")
                Button("Add Reminder") { replace(.reminderEditor(.create(vehicleID))) }
                    .accessibilityIdentifier("quickLogAddReminder")
                Button("Add Document") { replace(.documentEditor(model?.selectedVehicleID)) }
                    .accessibilityIdentifier("quickLogAddDocument")

                Button("Scan Receipt") { fullScreen(.camera(.receipt)) }
                    .accessibilityIdentifier("quickLogScanReceipt")
                Button("Scan Dashboard") { fullScreen(.camera(.dashboard)) }
                    .accessibilityIdentifier("quickLogScanDashboard")

                Button("Close") { model?.router.dismissModal() }
            }
            .navigationTitle("Quick log")
        }
    }

    private var vehicleID: VehicleID { model?.selectedVehicleID ?? VehicleID() }

    /// Replace rather than stack: the quick-log sheet steps aside for the next sheet.
    private func replace(_ route: ModalRoute) { model?.router.replaceModal(with: route) }

    private func fullScreen(_ route: FullScreenRoute) {
        model?.router.dismissModal()
        model?.router.presentFullScreen(route)
    }
}
