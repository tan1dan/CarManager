import SwiftUI

/// The root application flow. It reacts to state — nothing here is hardcoded to one screen.
///
///   launch → restore session → check auth → check onboarding → main app
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
        case .anonymous, .authenticated, .signedOut:
            if model.onboarding.isCompleted {
                RootTabView()
            } else {
                OnboardingView()
            }
        }
    }
}

struct LaunchPlaceholderView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Launching")
        }
    }
}
