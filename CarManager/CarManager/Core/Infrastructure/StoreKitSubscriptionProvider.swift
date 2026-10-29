import Foundation
import StoreKit
import UIKit

/// Premium through StoreKit 2. The only file in the app that imports StoreKit.
///
/// - Every transaction is checked with `VerificationResult` before it grants anything; an
///   unverified (jailbroken / tampered) transaction never unlocks Premium.
/// - Entitlement is always derived from `Transaction.currentEntitlements`, which StoreKit keeps
///   on the device — so a subscriber stays Premium offline and on a plane.
/// - One app-lifetime listener on `Transaction.updates` catches renewals, refunds, Ask to Buy
///   approvals, family sharing and purchases made on another device, finishes them, and
///   publishes the new entitlement through `entitlementUpdates()`.
public actor StoreKitSubscriptionProvider: SubscriptionProviding {
    private let clock: any ClockProviding
    private var cachedProducts: [ProductID: Product] = [:]
    private var updatesTask: Task<Void, Never>?
    private var continuations: [UUID: AsyncStream<Entitlement>.Continuation] = [:]

    public init(clock: any ClockProviding) {
        self.clock = clock
    }

    // MARK: - Products

    public func products() async throws -> [SubscriptionProduct] {
        let storeProducts: [Product]
        do {
            storeProducts = try await Product.products(for: ProductID.allCases.map(\.rawValue))
        } catch {
            throw DomainError.subscription(.productsUnavailable)
        }
        guard !storeProducts.isEmpty else { throw DomainError.subscription(.productsUnavailable) }

        var result: [SubscriptionProduct] = []
        for product in storeProducts {
            guard let id = ProductID(rawValue: product.id), let subscription = product.subscription else { continue }
            cachedProducts[id] = product
            let eligible = await subscription.isEligibleForIntroOffer
            result.append(SubscriptionProduct(
                id: id,
                displayName: product.displayName,
                displayPrice: product.displayPrice,
                price: product.price,
                period: Self.period(subscription.subscriptionPeriod),
                pricePerMonth: Self.pricePerMonth(product, period: subscription.subscriptionPeriod),
                isEligibleForIntroOffer: eligible && subscription.introductoryOffer != nil,
                introOffer: subscription.introductoryOffer.map(Self.introOffer)
            ))
        }
        // Monthly first, then yearly: the order the paywall lays the plans out in.
        return result.sorted { $0.id.sortOrder < $1.id.sortOrder }
    }

    // MARK: - Entitlement

    public func currentEntitlement() async -> Entitlement {
        startListeningIfNeeded()
        var best: Entitlement = .free
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  ProductID(rawValue: transaction.productID) != nil,
                  transaction.revocationDate == nil else { continue }
            let entitlement = await entitlement(for: transaction)
            // Two products in one group cannot both be active, but an upgrade can overlap
            // for a moment: keep the one that runs longest.
            if !best.isPremium || (entitlement.expiresAt ?? .distantFuture) > (best.expiresAt ?? .distantPast) {
                best = entitlement
            }
        }
        return best
    }

    public func entitlementUpdates() -> AsyncStream<Entitlement> {
        startListeningIfNeeded()
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func entitlement(for transaction: Transaction) async -> Entitlement {
        var source: EntitlementSource = transaction.ownershipType == .familyShared ? .familyShared : .direct
        if transaction.offer?.type == .introductory { source = .introOffer }
        var willAutoRenew = false
        var inBillingRetry = false
        if let status = await transaction.subscriptionStatus {
            if case .verified(let renewal) = status.renewalInfo { willAutoRenew = renewal.willAutoRenew }
            switch status.state {
            case .inBillingRetryPeriod: inBillingRetry = true
            case .inGracePeriod: source = .grace
            default: break
            }
        }
        return Entitlement(
            tier: .premium, source: source, expiresAt: transaction.expirationDate,
            willAutoRenew: willAutoRenew, isInBillingRetry: inBillingRetry, lastVerifiedAt: clock.now
        )
    }

    // MARK: - Purchase & restore

    public func purchase(_ productID: ProductID) async throws -> PurchaseOutcome {
        let product: Product
        if let cached = cachedProducts[productID] {
            product = cached
        } else {
            _ = try await products()
            guard let loaded = cachedProducts[productID] else { throw DomainError.subscription(.productsUnavailable) }
            product = loaded
        }

        let result: Product.PurchaseResult
        do {
            result = try await purchase(product)
        } catch StoreKitError.userCancelled {
            return .userCancelled
        } catch {
            throw DomainError.subscription(.purchaseFailed(error.localizedDescription))
        }

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw DomainError.subscription(.unverifiedTransaction)
            }
            await transaction.finish()
            let entitlement = await currentEntitlement()
            publish(entitlement)
            return .success(entitlement.isPremium ? entitlement : await self.entitlement(for: transaction))
        case .pending:
            // Ask to Buy or SCA: the answer arrives later through Transaction.updates.
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .userCancelled
        }
    }

    /// Given a scene, StoreKit shows the confirmation sheet over the right window.
    private func purchase(_ product: Product) async throws -> Product.PurchaseResult {
        if let scene = await Self.activeScene() {
            return try await product.purchase(confirmIn: scene)
        }
        return try await product.purchase()
    }

    public func restore() async throws -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch StoreKitError.userCancelled {
            // The Apple ID sheet was dismissed: report what is already on the device.
        } catch {
            throw DomainError.subscription(.restoreFailed)
        }
        let entitlement = await currentEntitlement()
        publish(entitlement)
        return entitlement.isPremium ? .restored(entitlement) : .nothingToRestore
    }

    public func openManageSubscriptions() async {
        if let scene = await Self.activeScene() {
            do {
                try await AppStore.showManageSubscriptions(in: scene)
                return
            } catch {}
        }
        // No scene (or the sheet failed): the App Store account page does the same job.
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            await MainActor.run { UIApplication.shared.open(url) }
        }
    }

    // MARK: - Transaction updates

    private func startListeningIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task(priority: .background) { [weak self] in
            // Anything left unfinished by a crash or a kill mid-purchase is settled first.
            for await result in Transaction.unfinished {
                if case .verified(let transaction) = result { await transaction.finish() }
            }
            for await result in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result { await transaction.finish() }
                await self.publish(await self.currentEntitlement())
            }
        }
    }

    private func publish(_ entitlement: Entitlement) {
        for continuation in continuations.values { continuation.yield(entitlement) }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }

    // MARK: - Mapping

    @MainActor
    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func period(_ period: Product.SubscriptionPeriod) -> SubscriptionPeriodUnit {
        switch period.unit {
        case .year: .year
        case .month where period.value >= 12: .year
        case .week, .day: .week
        default: .month
        }
    }

    /// "€4.17" for a yearly plan — StoreKit's own currency formatting, never ours.
    private static func pricePerMonth(_ product: Product, period: Product.SubscriptionPeriod) -> String? {
        let months: Decimal
        switch period.unit {
        case .year: months = Decimal(12 * period.value)
        case .month: months = Decimal(period.value)
        default: return nil
        }
        guard months > 1 else { return nil }
        var monthly = product.price / months
        var rounded = Decimal()
        NSDecimalRound(&rounded, &monthly, 2, .down)
        return product.priceFormatStyle.format(rounded)
    }

    private static func introOffer(_ offer: Product.SubscriptionOffer) -> IntroOffer {
        let length = duration(offer.period, count: offer.periodCount)
        switch offer.paymentMode {
        case .freeTrial: return IntroOffer(kind: .freeTrial, duration: length, price: nil)
        default: return IntroOffer(kind: .discounted, duration: length, price: offer.displayPrice)
        }
    }

    /// "1 week", "3 months" — spelled out in the user's language by the system.
    private static func duration(_ period: Product.SubscriptionPeriod, count: Int) -> String {
        var components = DateComponents()
        let value = period.value * max(count, 1)
        switch period.unit {
        case .day: components.day = value
        case .week: components.weekOfMonth = value
        case .month: components.month = value
        case .year: components.year = value
        @unknown default: components.day = value
        }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 1
        return formatter.string(from: components) ?? ""
    }
}

private extension ProductID {
    var sortOrder: Int { self == .monthly ? 0 : 1 }
}
