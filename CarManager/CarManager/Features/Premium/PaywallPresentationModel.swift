import Foundation

/// Display-ready values for the paywall (Figma node 3:5399).
struct PaywallPresentationModel: Equatable, Sendable {
    var title: String
    var subtitle: String
    var benefits: [String]
    var plans: [Plan]
    var callToAction: String
    /// Price, period and renewal terms for the selected plan — App Review requires them
    /// next to the purchase button.
    var disclosure: String
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
        disclosure: "",
        footerPrefix: String(localized: "Cancel anytime ·"),
        restoreTitle: String(localized: "Restore purchase")
    )
}

/// Pure mapping from StoreKit-derived products onto display values. Every price on screen is
/// StoreKit's own localised string; this type only compares raw amounts to compute savings.
struct PaywallFormatter: Sendable {
    /// Exactly what Premium unlocks in `FeatureGating` — nothing the app does not do.
    /// iCloud sync is free, so the paywall does not claim it.
    static let benefits = [
        String(localized: "Unlimited vehicles"),
        String(localized: "Unlimited AI chat"),
        String(localized: "Receipt scanning with currency conversion"),
        String(localized: "Dashboard scans & damage analysis"),
        String(localized: "AI insights & recommendations")
    ]

    func makeModel(
        products: [SubscriptionProduct],
        selected: ProductID
    ) -> PaywallPresentationModel {
        let monthly = products.first { $0.id == .monthly }
        let plans = products.map { product in
            PaywallPresentationModel.Plan(
                id: product.id,
                name: product.id == .yearly ? String(localized: "Yearly") : String(localized: "Monthly"),
                price: product.displayPrice,
                caption: caption(for: product),
                isPromoted: product.id == ProductCatalogIDs.promoted,
                flag: savings(of: product, against: monthly).map { String(localized: "SAVE \($0)%") } ?? String(localized: "BEST")
            )
        }

        let selectedProduct = products.first { $0.id == selected }
        return PaywallPresentationModel(
            title: String(localized: "Go Premium"),
            subtitle: String(localized: "Unlock the full power of your AI car companion."),
            benefits: Self.benefits,
            plans: plans,
            callToAction: callToAction(for: selectedProduct),
            disclosure: disclosure(for: selectedProduct),
            footerPrefix: String(localized: "Cancel anytime ·"),
            restoreTitle: String(localized: "Restore purchase")
        )
    }

    private func caption(for product: SubscriptionProduct) -> String {
        switch product.period {
        case .year:
            product.pricePerMonth.map { String(localized: "per year · \($0)/month") } ?? String(localized: "per year")
        case .month: String(localized: "per month")
        case .week: String(localized: "per week")
        }
    }

    /// Whole percent saved by paying yearly instead of twelve monthly payments, if any.
    func savings(of product: SubscriptionProduct, against monthly: SubscriptionProduct?) -> Int? {
        guard product.period == .year, let monthly, monthly.price > 0, product.price > 0 else { return nil }
        let fullYear = (monthly.price * 12 as NSDecimalNumber).doubleValue
        let percent = Int(((1 - (product.price as NSDecimalNumber).doubleValue / fullYear) * 100).rounded(.down))
        return percent > 0 ? percent : nil
    }

    /// Only promises a trial when StoreKit says this account is actually eligible.
    private func callToAction(for product: SubscriptionProduct?) -> String {
        guard let product else { return String(localized: "Subscribe") }
        if product.isEligibleForIntroOffer, let offer = product.introOffer, offer.kind == .freeTrial {
            return String(localized: "Try \(offer.duration) free")
        }
        return String(localized: "Subscribe")
    }

    private func disclosure(for product: SubscriptionProduct?) -> String {
        guard let product else { return "" }
        let recurring = switch product.period {
        case .year: String(localized: "\(product.displayPrice) per year")
        case .month: String(localized: "\(product.displayPrice) per month")
        case .week: String(localized: "\(product.displayPrice) per week")
        }
        var lead = recurring
        if product.isEligibleForIntroOffer, let offer = product.introOffer {
            lead = switch offer.kind {
            case .freeTrial: String(localized: "\(offer.duration) free, then \(recurring).")
            case .discounted: String(localized: "\(offer.price ?? product.displayPrice) for \(offer.duration), then \(recurring).")
            }
        } else {
            lead += "."
        }
        return lead + " " + String(localized: "Payment is charged to your Apple ID. The subscription renews automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel it in your App Store account settings.")
    }
}

/// The promoted plan, kept next to the product identifiers.
enum ProductCatalogIDs {
    static let promoted: ProductID = .yearly
}
