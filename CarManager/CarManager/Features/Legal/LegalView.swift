import SwiftUI
import SafariServices

/// Privacy Policy / Terms of Use, opened in an in-app Safari sheet so the published text is
/// always the current one. Reachable signed out (the welcome screen links here).
struct LegalView: View {
    let document: LegalDocument

    var body: some View {
        SafariView(url: document.url)
            .ignoresSafeArea()
            .accessibilityLabel(document.title)
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.preferredBarTintColor = UIColor(DS.Colors.background)
        controller.preferredControlTintColor = UIColor(DS.Colors.accent)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
