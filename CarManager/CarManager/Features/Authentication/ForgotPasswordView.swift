import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.appModel) private var model
    @State private var email = ""
    @State private var didSend = false

    var body: some View {
        Form {
            Text("Forgot Password")
            TextField("Email", text: $email)
            Button("Send reset link") {
                Task {
                    guard let model else { return }
                    try? await RequestPasswordReset(auth: model.dependencies.auth)(email: email)
                    didSend = true
                }
            }
            if didSend { Text("Reset link sent") }
            Button("Close") { model?.router.dismissModal() }
        }
        .navigationTitle("Reset password")
    }
}
