import SwiftUI

struct LegalView: View {
    let document: LegalDocument
    /// `dismiss` rather than the router: this view is shown both as a routed sheet (where the
    /// ModalHost binding forwards the dismissal to the router) and locally from the auth flow.
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document == .privacyPolicy ? "Privacy Policy" : "Terms of Use")
                    .padding()
            }
            .navigationTitle(document == .privacyPolicy ? "Privacy" : "Terms")
            .toolbar {
                Button("Close") { dismiss() }
                    .accessibilityIdentifier("legalClose")
            }
        }
    }
}
