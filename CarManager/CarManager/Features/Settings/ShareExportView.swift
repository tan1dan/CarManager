import SwiftUI

/// Hands a generated export to the system share sheet.
struct ShareExportView: View {
    let url: URL
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ShareLink(item: url) {
                    Label("Share export", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("shareExportLink")

                Text(url.lastPathComponent)
                    .font(DS.Text.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Colors.background)
            .navigationTitle("Export")
            .toolbar {
                Button("Close") { model?.router.dismissModal() }
                    .accessibilityIdentifier("shareExportClose")
            }
        }
    }
}
