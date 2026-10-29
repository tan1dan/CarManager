import Foundation

/// Display-ready values for the paywall (Figma node 3:5399).
struct PaywallPresentationModel: Equatable, Sendable {
    var title: String
    var subtitle: String
    var benefits: [String]
    var plans: [Plan]
    var callToAction: String
    var footerPrefix: String
    var restoreTitle: String

    struct Plan: Equatable, Sendable, Identifiable {
        var id: ProductID
        var name: String
        var price: String
        var caption: String
        var isPromoted: Bool
        var flag: String
    }

    static let placeholder = PaywallPresentationModel(
        title: String(localized: "Go Premium"),
        subtitle: String(localized: "Unlock the full power of your AI car companion."),
        benefits: PaywallFormatter.benefits,
        plans: [],
        callToAction: String(localized: "Subscribe"),
        footerPrefix: String(localized: "Cancel anytime ·"),
        restoreTitle: String(localized: "Restore purchase")
    )
}

/// Pure mapping from StoreKit-derived products onto display values.
struct PaywallFormatter: Sendable {
    /// Wording matches the architecture's gating matrix, not the design's stale copy:
    /// iCloud sync is free, so the paywall does not claim it.
    static let benefits = [
        String(localized: "Unlimited vehicles"),
        String(localized: "Advanced AI scans & damage analysis"),
        String(localized: "AI insights & recommendations"),
        String(localized: "PDF export of history"),
        String(localized: "Priority support")
    ]

    func makeModel(
        products: [SubscriptionProduct],
        selected: ProductID
    ) -> PaywallPresentationModel {
        let plans = products.map { product in
            PaywallPresentationModel.Plan(
                id: product.id,
                name: product.id == .yearly ? String(localized: "Yearly") : String(localized: "Monthly"),
                price: product.displayPrice,
                caption: caption(for: product),
                isPromoted: product.id == ProductCatalogIDs.promoted,
                flag: String(localized: "BEST")
            )
        }

        let selectedProduct = products.first { $0.id == selected }
        return PaywallPresentationModel(
            title: String(localized: "Go Premium"),
            subtitle: String(localized: "Unlock the full power of your AI car companion."),
            benefits: Self.benefits,
            plans: plans,
            callToAction: callToAction(for: selectedProduct),
            footerPrefix: String(localized: "Cancel anytime ·"),
            restoreTitle: String(localized: "Restore purchase")
        )
    }

    private func caption(for product: SubscriptionProduct) -> String {
        switch product.id {
        case .monthly: String(localized: "per month")
        case .yearly: String(localized: "2 months free")
        }
    }

    /// Only promises a trial when StoreKit says this account is actually eligible.
    private func callToAction(for product: SubscriptionProduct?) -> String {
        guard let product else { return String(localized: "Subscribe") }
        if product.isEligibleForIntroOffer, let offer = product.introOfferDescription {
            return String(localized: "Start \(offer)")
        }
        return String(localized: "Subscribe")
    }
}

/// The promoted plan, kept next to the product identifiers.
enum ProductCatalogIDs {
    static let promoted: ProductID = .yearly
}
