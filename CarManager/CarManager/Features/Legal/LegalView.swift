import SwiftUI

struct LegalView: View {
    let document: LegalDocument
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(document == .privacyPolicy ? "Privacy Policy" : "Terms of Use")
                    .padding()
            }
            .navigationTitle(document == .privacyPolicy ? "Privacy" : "Terms")
            .toolbar {
                Button("Close") { model?.router.dismissModal() }
                    .accessibilityIdentifier("legalClose")
            }
        }
    }
}
