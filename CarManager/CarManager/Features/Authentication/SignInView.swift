import SwiftUI

struct SignInView: View {
    @Binding var path: [AuthEntryPoint]
    @Environment(\.appModel) private var model
    @State private var viewModel: SignInViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SignInContentView(viewModel: viewModel, path: $path)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Welcome back")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = SignInViewModel(
                signIn: SignIn(auth: model.dependencies.auth),
                authStore: model.auth,
                router: model.router
            )
        }
    }
}

private struct SignInContentView: View {
    @Bindable var viewModel: SignInViewModel
    @Binding var path: [AuthEntryPoint]
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Section("Sign in") {
                Text("Sign In")
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("signInEmail")
                SecureField("Password", text: $viewModel.password)
                    .accessibilityIdentifier("signInPassword")

                Button("Sign in") { Task { await viewModel.signIn() } }
                    .accessibilityIdentifier("signInSubmit")
                Button("Continue with Apple") { Task { await viewModel.signInWithApple() } }
                    .accessibilityIdentifier("signInApple")
                Button("Continue with Google") { Task { await viewModel.signInWithGoogle() } }
                    .accessibilityIdentifier("signInGoogle")
            }

            Section {
                Button("Forgot password?") { model?.router.present(.forgotPassword) }
                    .accessibilityIdentifier("signInForgotPassword")
                Button("No account? Sign up") { path.append(.signUp) }
                    .accessibilityIdentifier("signInToSignUp")
            }

            if let error = viewModel.state.error {
                Section { Text(error.messageKey).accessibilityIdentifier("signInError") }
            }
        }
    }
}
