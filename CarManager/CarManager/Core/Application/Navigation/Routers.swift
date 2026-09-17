import Foundation
import Observation

/// One navigation stack per tab.
@MainActor
@Observable
public final class TabRouter {
    public let tab: AppTab
    public var path: [AppRoute] = []

    public init(tab: AppTab) { self.tab = tab }

    public func push(_ route: AppRoute) { path.append(route) }
    public func pop() { if !path.isEmpty { path.removeLast() } }
    public func popToRoot() { path.removeAll() }
    public func replace(with routes: [AppRoute]) { path = routes }
}

/// THE single navigation entry point. Every navigation in the app goes through `navigate(to:)`,
/// which is what makes gating, deep links and state restoration share one implementation.
@MainActor
@Observable
public final class AppRouter {
    public private(set) var selectedTab: AppTab = .home
    /// An array, not an optional: a paywall can legitimately cover an editor.
    public private(set) var modalStack: [ModalRoute] = []
    public private(set) var fullScreen: FullScreenRoute?

    /// Stored when a guard intercepts, replayed after sign-in or purchase, so the user lands
    /// on the screen they originally asked for — not back at Home.
    public private(set) var pendingDestination: AppDestination?

    public private(set) var routers: [AppTab: TabRouter]

    private let guardEvaluator: RouteGuard
    private let contextProvider: @MainActor () -> RouteGuard.Context

    public init(
        guardEvaluator: RouteGuard? = nil,
        contextProvider: @escaping @MainActor () -> RouteGuard.Context
    ) {
        self.guardEvaluator = guardEvaluator ?? RouteGuard()
        self.contextProvider = contextProvider
        var routers: [AppTab: TabRouter] = [:]
        for tab in AppTab.allCases { routers[tab] = TabRouter(tab: tab) }
        self.routers = routers
    }

    public func router(for tab: AppTab) -> TabRouter {
        routers[tab] ?? TabRouter(tab: tab)
    }

    public var activeModal: ModalRoute? { modalStack.last }

    /// The modal at a given stack depth. A single SwiftUI `.sheet` can present only one thing,
    /// so the presenter is recursive: each level hosts the next.
    public func modal(at depth: Int) -> ModalRoute? {
        modalStack.indices.contains(depth) ? modalStack[depth] : nil
    }

    /// Dismisses the modal at `depth` and everything stacked above it.
    public func dismissModal(from depth: Int) {
        guard modalStack.indices.contains(depth) else { return }
        modalStack.removeSubrange(depth...)
    }

    // MARK: - Navigation

    @discardableResult
    public func navigate(to destination: AppDestination, applyingGuard: Bool = true) -> RouteGuard.Decision {
        let decision = applyingGuard
            ? guardEvaluator.evaluate(destination, context: contextProvider())
            : .allow

        switch decision {
        case .allow:
            apply(destination)
        case .redirect(let replacement):
            pendingDestination = destination
            apply(replacement)
        case .present(let modal):
            pendingDestination = destination
            modalStack.append(modal)
        }
        return decision
    }

    private func apply(_ destination: AppDestination) {
        if let tab = destination.tab {
            selectedTab = tab
            if !destination.path.isEmpty {
                router(for: tab).replace(with: destination.path)
            }
        } else if !destination.path.isEmpty {
            router(for: selectedTab).replace(with: destination.path)
        }
        if let modal = destination.modal { modalStack.append(modal) }
        if let fullScreen = destination.fullScreen { self.fullScreen = fullScreen }
    }

    // MARK: - Convenience

    public func select(tab: AppTab) { selectedTab = tab }

    public func push(_ route: AppRoute, in tab: AppTab? = nil) {
        navigate(to: AppDestination(tab: tab ?? selectedTab, path: currentPath(for: tab ?? selectedTab) + [route]))
    }

    private func currentPath(for tab: AppTab) -> [AppRoute] { router(for: tab).path }

    public func present(_ modal: ModalRoute) {
        navigate(to: .modal(modal))
    }

    /// Used by the quick-log sheet: replace it with the next sheet rather than stacking.
    public func replaceModal(with modal: ModalRoute) {
        if !modalStack.isEmpty { modalStack.removeLast() }
        navigate(to: .modal(modal))
    }

    public func presentFullScreen(_ route: FullScreenRoute) {
        navigate(to: .fullScreen(route))
    }

    public func dismissModal() {
        if !modalStack.isEmpty { modalStack.removeLast() }
    }

    public func dismissFullScreen() { fullScreen = nil }

    public func dismissAll() {
        modalStack.removeAll()
        fullScreen = nil
    }

    /// Called after sign-in, purchase or disclaimer acknowledgement.
    @discardableResult
    public func replayPendingDestination() -> Bool {
        guard let destination = pendingDestination else { return false }
        pendingDestination = nil
        dismissAll()
        navigate(to: destination)
        return true
    }

    public func clearPendingDestination() { pendingDestination = nil }

    // MARK: - External entry points

    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let destination = DeepLinkParser.destination(from: url) else { return false }
        navigate(to: destination)
        return true
    }

    @discardableResult
    public func handle(notificationPayload: [AnyHashable: Any]) -> Bool {
        guard let destination = DeepLinkParser.destination(fromNotificationPayload: notificationPayload)
        else { return false }
        navigate(to: destination)
        return true
    }

    // MARK: - Bindings support

    public var modalBinding: ModalRoute? {
        get { modalStack.last }
        set { if newValue == nil { dismissModal() } }
    }

    public var fullScreenBinding: FullScreenRoute? {
        get { fullScreen }
        set { fullScreen = newValue }
    }
}
