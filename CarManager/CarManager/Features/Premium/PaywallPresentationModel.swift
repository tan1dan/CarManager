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
        title: "Go Premium",
        subtitle: "Unlock the full power of your AI car companion.",
        benefits: PaywallFormatter.benefits,
        plans: [],
        callToAction: "Subscribe",
        footerPrefix: "Cancel anytime ·",
        restoreTitle: "Restore purchase"
    )
}

/// Pure mapping from StoreKit-derived products onto display values.
struct PaywallFormatter: Sendable {
    /// Wording matches the architecture's gating matrix, not the design's stale copy:
    /// iCloud sync is free, so the paywall does not claim it.
    static let benefits = [
        "Unlimited vehicles",
        "Advanced AI scans & damage analysis",
        "AI insights & recommendations",
        "PDF export of history",
        "Priority support"
    ]

    func makeModel(
        products: [SubscriptionProduct],
        selected: ProductID
    ) -> PaywallPresentationModel {
        let plans = products.map { product in
            PaywallPresentationModel.Plan(
                id: product.id,
                name: product.id == .yearly ? "Yearly" : "Monthly",
                price: product.displayPrice,
                caption: caption(for: product),
                isPromoted: product.id == ProductCatalogIDs.promoted,
                flag: "BEST"
            )
        }

        let selectedProduct = products.first { $0.id == selected }
        return PaywallPresentationModel(
            title: "Go Premium",
            subtitle: "Unlock the full power of your AI car companion.",
            benefits: Self.benefits,
            plans: plans,
            callToAction: callToAction(for: selectedProduct),
            footerPrefix: "Cancel anytime ·",
            restoreTitle: "Restore purchase"
        )
    }

    private func caption(for product: SubscriptionProduct) -> String {
        switch product.id {
        case .monthly: "per month"
        case .yearly: "2 months free"
        }
    }

    /// Only promises a trial when StoreKit says this account is actually eligible.
    private func callToAction(for product: SubscriptionProduct?) -> String {
        guard let product else { return "Subscribe" }
        if product.isEligibleForIntroOffer, let offer = product.introOfferDescription {
            return "Start \(offer)"
        }
        return "Subscribe"
    }
}

/// The promoted plan, kept next to the product identifiers.
enum ProductCatalogIDs {
    static let promoted: ProductID = .yearly
}
