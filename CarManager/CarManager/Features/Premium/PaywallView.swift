import SwiftUI

/// No View imports StoreKit. The paywall reads `EntitlementStore` and nothing else.
struct PaywallView: View {
    let context: PaywallContext
    @Environment(\.appModel) private var model
    @State private var viewModel: PaywallViewModel?

    var body: some View {
        NavigationStack {
            List {
                Text("Premium")
                // The context says WHY the paywall appeared, so the copy can match.
                Text("Trigger: \(String(describing: context))")

                Section("Plans") {
                    ForEach(viewModel?.products ?? []) { product in
                        Button("\(product.displayName) · \(product.displayPrice)") {
                            Task { await viewModel?.purchase(product.id) }
                        }
                        .accessibilityIdentifier("paywallPlan_\(product.id.rawValue)")
                    }
                }

                Section {
                    Button("Subscribe") {
                        Task { await viewModel?.purchase(.yearly) }
                    }
                    .accessibilityIdentifier("paywallSubscribe")
                    Button("Restore Purchases") { Task { await viewModel?.restore() } }
                        .accessibilityIdentifier("paywallRestore")
                }

                Section("Legal") {
                    Button("Terms of Use") { model?.router.present(.legal(.termsOfUse)) }
                        .accessibilityIdentifier("paywallTerms")
                    Button("Privacy Policy") { model?.router.present(.legal(.privacyPolicy)) }
                        .accessibilityIdentifier("paywallPrivacy")
                }

                if let message = viewModel?.message {
                    Section { Text(message).accessibilityIdentifier("paywallMessage") }
                }
            }
            .navigationTitle("Go Premium")
            .toolbar {
                Button("Close") {
                    model?.router.clearPendingDestination()
                    model?.router.dismissModal()
                }
                .accessibilityIdentifier("paywallClose")
            }
        }
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = PaywallViewModel(entitlements: model.entitlements, router: model.router)
            await viewModel?.load()
        }
    }
}
