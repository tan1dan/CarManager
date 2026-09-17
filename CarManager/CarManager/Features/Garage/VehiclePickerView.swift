import SwiftUI

struct VehiclePickerView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            List(model?.vehicles.summaries ?? []) { summary in
                Button(summary.displayName) {
                    Task {
                        await model?.vehicles.select(summary.id)
                        model?.router.dismissModal()
                    }
                }
            }
            .navigationTitle("Select vehicle")
            .toolbar { Button("Close") { model?.router.dismissModal() } }
        }
    }
}
