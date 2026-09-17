import SwiftUI

struct AIChatView: View {
    let conversationID: ConversationID?
    @Environment(\.appModel) private var model
    @State private var viewModel: AIChatViewModel?

    var body: some View {
        VStack {
            Text("AI Chat")
            List {
                ForEach(viewModel?.messages ?? []) { message in
                    Text("\(message.role.rawValue): \(message.text)")
                }
                if let streaming = viewModel?.streamingText, !streaming.isEmpty {
                    Text("assistant: \(streaming)")
                        .accessibilityIdentifier("aiStreamingBubble")
                }
            }

            if viewModel?.isStreaming == true {
                Button("Stop") { viewModel?.cancel() }
                    .accessibilityIdentifier("aiChatStop")
            }

            HStack {
                TextField("Ask your car anything...", text: Binding(
                    get: { viewModel?.composerText ?? "" },
                    set: { viewModel?.composerText = $0 }
                ))
                .accessibilityIdentifier("aiChatComposer")
                Button("Send") { viewModel?.send() }
                    .accessibilityIdentifier("aiChatSend")
            }
            .padding()
        }
        .navigationTitle("AI Assistant")
        .task {
            guard let model else { return }
            if viewModel == nil {
                viewModel = AIChatViewModel(
                    conversationID: conversationID,
                    vehicleID: model.selectedVehicleID,
                    askAI: AskAI(
                        conversations: model.dependencies.conversations,
                        provider: model.dependencies.ai,
                        buildContext: BuildAIContext(
                            vehicles: model.dependencies.vehicles,
                            odometer: model.dependencies.odometer,
                            fuel: model.dependencies.fuel,
                            services: model.dependencies.services,
                            expenses: model.dependencies.expenses,
                            clock: model.dependencies.clock
                        ),
                        clock: model.dependencies.clock
                    ),
                    loadConversation: LoadConversation(
                        conversations: model.dependencies.conversations
                    ),
                    featureGate: model.featureGate,
                    router: model.router
                )
            }
            await viewModel?.load()
        }
        // Leaving the screen cancels the stream; the partial answer is kept, never discarded.
        .onDisappear { viewModel?.cancel() }
    }
}
