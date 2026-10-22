import SwiftUI

/// The main TabView. The central "+" is not a tab — it presents `ModalRoute.quickLog`,
/// which is why it sits in the toolbar area rather than in the tab set.
struct RootTabView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        if let model {
            TabView(selection: Binding(
                get: { model.router.selectedTab },
                set: { model.router.select(tab: $0) }
            )) {
                ForEach(AppTab.allCases) { tab in
                    Tab(value: tab) {
                        TabStackView(tab: tab)
                            // The system bar is hidden; the design's floating pill replaces it.
                            .toolbarVisibility(.hidden, for: .tabBar)

                    }
                }
            }
            // Drawn once, above every tab. Screens reserve room for it with
            // `DS.Layout.tabBarReservedHeight` — neither safeAreaInset on the TabView nor on
            // the tab content propagates into the tabs' scroll views.
            .overlay(alignment: .bottom) {
                if !hidesTabBar(model) {
                    CarManagerTabBar(
                        selectedTab: model.router.selectedTab,
                        onSelect: { model.router.select(tab: $0) },
                        onAdd: { model.router.present(.quickLog) }
                    )
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: hidesTabBar(model))
        }
    }

    /// The chat owns the bottom edge for its composer, like Messages.
    private func hidesTabBar(_ model: AppModel) -> Bool {
        if case .aiChat = model.router.router(for: model.router.selectedTab).path.last { return true }
        return false
    }
}

/// One NavigationStack per tab, bound to that tab's typed route path.
struct TabStackView: View {
    let tab: AppTab
    @Environment(\.appModel) private var model

    var body: some View {
        if let model {
            @Bindable var router = model.router.router(for: tab)
            NavigationStack(path: $router.path) {
                tabRoot
                    .navigationDestination(for: AppRoute.self) { route in
                        AppRouteView(route: route)
                    }
            }
        }
    }

    @ViewBuilder
    private var tabRoot: some View {
        switch tab {
        case .home: HomeView()
        case .garage: GarageView()
        case .ai: AIHubView()
        case .profile: ProfileView()
        }
    }
}
