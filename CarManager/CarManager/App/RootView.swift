import SwiftUI

/// The root application flow. It reacts to state — nothing here is hardcoded to one screen.
///
///   launch → restore session → signed in with Apple? → main app
///                                              no    → first launch? → intro tour
///                                                      → welcome (Sign in with Apple)
///
/// There is no way past the welcome screen without an Apple account (ADR-016). Signing out,
/// deleting the account or revoking the app in Settings all land back on it.
struct RootView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        if let model {
            content(model)
                // Full-screen flows are isolated from the tab navigation stacks.
                .fullScreenCover(item: Binding(
                    get: { model.router.fullScreen },
                    set: { if $0 == nil { model.router.dismissFullScreen() } }
                )) { route in
                    FullScreenRouteView(route: route)
                }
                // Sheets are presented from the router, never from a view's own @State.
                // ModalHost walks the router's modal stack so sheets can genuinely stack.
                .modifier(ModalHost(depth: 0))
                // Signing in is the onboarding. Signing out drops every stack and sheet, so the
                // next account does not land in the previous one's navigation.
                .onChange(of: model.auth.state.isAuthenticated) { _, isAuthenticated in
                    if isAuthenticated {
                        model.onboarding.complete()
                        // The garage may have arrived from iCloud while the user was signed out.
                        Task { await model.vehicles.refresh() }
                    } else {
                        model.router.resetForSignOut()
                    }
                }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func content(_ model: AppModel) -> some View {
        switch model.auth.state {
        case .restoring:
            // The splash blocks only until session restoration settles; the garage does not
            // wait for the network.
            LaunchPlaceholderView()
        case .authenticated(let profile) where profile.needsDisplayName:
            // Apple shared no name: ask once, so the app never greets someone by a relay address.
            NameEntryView()
        case .authenticated:
            RootTabView()
        case .anonymous, .signedOut:
            // A first launch gets the tour before the sign-in screen; later sign-outs do not.
            if model.onboarding.isCompleted {
                OnboardingView().transition(.opacity)
            } else {
                IntroView().transition(.opacity)
            }
        }
    }
}

/// Shown while the session is restored — the splash without its buttons, so launch does
/// not flash a white screen before the dark app.
struct LaunchPlaceholderView: View {
    var body: some View {
        ZStack {
            SplashBackground()
            SplashBrand()
        }
        .environment(\.colorScheme, .dark)
    }
}
