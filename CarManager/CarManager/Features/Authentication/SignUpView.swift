import SwiftUI

struct SignUpView: View {
    @Binding var path: [AuthEntryPoint]
    @Environment(\.appModel) private var model
    @State private var viewModel: SignUpViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SignUpContentView(viewModel: viewModel, path: $path)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Create account")
        .task {
            guard viewModel == nil, let model else { return }
            viewModel = SignUpViewModel(
                signUp: SignUp(auth: model.dependencies.auth),
                authStore: model.auth,
                router: model.router
            )
        }
    }
}

private struct SignUpContentView: View {
    @Bindable var viewModel: SignUpViewModel
    @Binding var path: [AuthEntryPoint]
    @Environment(\.appModel) private var model

    var body: some View {
        Form {
            Section("Create account") {
                Text("Sign Up")
                TextField("Name", text: $viewModel.name)
                    .accessibilityIdentifier("signUpName")
                TextField("Email", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .accessibilityIdentifier("signUpEmail")
                SecureField("Password", text: $viewModel.password)
                    .accessibilityIdentifier("signUpPassword")
                Toggle("I agree to the Terms and Privacy Policy", isOn: $viewModel.acceptedTerms)
                    .accessibilityIdentifier("signUpTerms")

                Button("Create account") { Task { await viewModel.signUp() } }
                    .accessibilityIdentifier("signUpSubmit")
            }

            Section("Legal") {
                Button("Terms of Use") { model?.router.present(.legal(.termsOfUse)) }
                Button("Privacy Policy") { model?.router.present(.legal(.privacyPolicy)) }
            }

            Section {
                Button("Already have an account? Sign in") { path.append(.signIn) }
                    .accessibilityIdentifier("signUpToSignIn")
            }

            if let error = viewModel.state.error {
                Section { Text(error.messageKey).accessibilityIdentifier("signUpError") }
            }
        }
    }
}
