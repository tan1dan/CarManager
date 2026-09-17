import SwiftUI

/// Hosts the authentication stack inside a full-screen cover.
struct AuthenticationFlowView: View {
    let entryPoint: AuthEntryPoint
    @State private var path: [AuthEntryPoint] = []
    @Environment(\.appModel) private var model

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: AuthEntryPoint.self) { entry in
                    switch entry {
                    case .signIn: SignInView(path: $path)
                    case .signUp: SignUpView(path: $path)
                    }
                }
        }
    }

    @ViewBuilder
    private var root: some View {
        switch entryPoint {
        case .signIn: SignInView(path: $path)
        case .signUp: SignUpView(path: $path)
        }
    }
}
