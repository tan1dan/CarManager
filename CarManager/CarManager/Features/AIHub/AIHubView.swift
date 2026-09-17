import SwiftUI

struct AIHubView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: AIHubViewModel?

    var body: some View {
        List {
            Text("AI Assistant")

            Section("Tools") {
                // Rows render their lock state from FeatureAccess but never enforce it —
                // enforcement is RouteGuard plus the use case.
                Button("Scan Dashboard") { fullScreen(.camera(.dashboard)) }
                    .accessibilityIdentifier("aiScanDashboard")
                Button("Scan Receipt") { fullScreen(.camera(.receipt)) }
                    .accessibilityIdentifier("aiScanReceipt")
                Button("Analyze Damage") { fullScreen(.camera(.damage)) }
                    .accessibilityIdentifier("aiAnalyzeDamage")
                Button("Ask AI") { model?.router.push(.aiChat(nil), in: .ai) }
                    .accessibilityIdentifier("aiAskAI")
            }

            Section("Recent chats") {
                switch viewModel?.state {
                case .loading: ProgressView()
                case .loaded(let summaries):
                    ForEach(summaries) { summary in
                        Button(summary.title) {
                            model?.router.push(.aiChat(summary.id), in: .ai)
                        }
                    }
                case .empty: Text("No conversations yet")
                case .failed(let error): Text(error.messageKey)
                default: Text("Idle")
                }
                Button("Conversation history") { model?.router.push(.conversationHistory, in: .ai) }
                    .accessibilityIdentifier("aiConversationHistory")
            }
        }
        .navigationTitle("AI")
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = AIHubViewModel(
                    listConversations: ListConversations(
                        conversations: model.dependencies.conversations
                    ),
                    featureGate: model.featureGate
                )
            }
            await viewModel?.load()
        }
    }

    private func fullScreen(_ route: FullScreenRoute) {
        model?.router.presentFullScreen(route)
    }
}

struct ConversationHistoryView: View {
    @Environment(\.appModel) private var model
    @State private var summaries: [ConversationSummary] = []

    var body: some View {
        List(summaries) { summary in
            Button(summary.title) { model?.router.push(.aiChat(summary.id), in: .ai) }
        }
        .navigationTitle("Conversations")
        .task {
            guard let model else { return }
            summaries = (try? await ListConversations(
                conversations: model.dependencies.conversations
            )(vehicleID: nil)) ?? []
        }
    }
}

struct AIInsightDetailsView: View {
    let insightID: InsightID
    var body: some View { Text("AI Insight Details").navigationTitle("Insight") }
}
