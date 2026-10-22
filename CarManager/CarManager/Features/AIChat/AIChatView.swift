import SwiftUI

/// AI chat, built from Figma 18 (answering 35, limit reached 36).
struct AIChatView: View {
    let conversationID: ConversationID?
    @Environment(\.appModel) private var model
    @State private var viewModel: AIChatViewModel?

    var body: some View {
        ZStack {
            Color.clear
            if let viewModel { AIChatContentView(viewModel: viewModel) { model?.router.pop() } }
        }
        .dsScreen()
        .task {
            guard let model else { return }
            if viewModel == nil {
                let d = model.dependencies
                viewModel = AIChatViewModel(
                    conversationID: conversationID,
                    vehicleID: model.selectedVehicleID,
                    askAI: AskAI(
                        conversations: d.conversations, provider: d.ai,
                        buildContext: BuildAIContext(vehicles: d.vehicles, odometer: d.odometer, fuel: d.fuel,
                                                     services: d.services, expenses: d.expenses, clock: d.clock),
                        clock: d.clock
                    ),
                    loadConversation: LoadConversation(conversations: d.conversations),
                    featureGate: model.featureGate,
                    consumeQuota: { [entitlements = model.entitlements] in entitlements.consumeAIRequest() },
                    router: model.router,
                    clock: d.clock
                )
            }
            await viewModel?.load()
        }
        // Leaving the screen cancels the stream; the partial answer is kept, never discarded.
        .onDisappear { viewModel?.cancel() }
    }
}

private struct AIChatContentView: View {
    @Bindable var viewModel: AIChatViewModel
    let onBack: () -> Void
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty && !viewModel.isStreaming { intro }
                        ForEach(viewModel.messages) { message in
                            MessageBubble(text: message.text, isUser: message.role == .user, isPartial: message.isPartial)
                        }
                        if viewModel.isStreaming {
                            MessageBubble(text: viewModel.streamingText, isUser: false, isPartial: false, isTyping: viewModel.streamingText.isEmpty)
                                .accessibilityIdentifier("aiStreamingBubble")
                            stopButton
                        }
                        if let error = viewModel.errorMessage {
                            InfoBanner(symbol: "exclamationmark.triangle", text: error, tone: .danger)
                        }
                        if viewModel.limitResetsAt != nil { limitCard }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, DS.Layout.gutter)
                    .padding(.vertical, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                // The tab bar is hidden here, so no room is reserved for it.
                .contentMargins(.bottom, 0, for: .scrollContent)
                .onChange(of: viewModel.messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: viewModel.streamingText) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            composer
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleBackButton(action: onBack)
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Circle().fill(DS.Gradients.aiCard))
            VStack(alignment: .leading, spacing: 0) {
                Text("AI Assistant").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(viewModel.status).font(DS.Text.statCaption).foregroundStyle(DS.Colors.textSecondary)
                    .contentTransition(.opacity)
            }
            Spacer()
        }
        .padding(.horizontal, DS.Layout.gutter)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(DS.Colors.hairline).frame(height: 1) }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask about your car")
                .font(DS.Text.section).tracking(DS.Text.sectionTracking).foregroundStyle(.white)
            Text("Answers use your own fuel, service and expense records. For anything safety-critical, check with a mechanic.")
                .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
            ForEach(viewModel.suggestions, id: \.self) { suggestion in
                Button { viewModel.send(suggestion) } label: {
                    HStack {
                        Text(suggestion).font(DS.Text.subheadline).foregroundStyle(.white).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.Colors.accent)
                    }
                    .padding(14)
                    .dsGlass(radius: 16)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLocked)
            }
        }
        .padding(.top, 8)
    }

    private var stopButton: some View {
        Button { viewModel.cancel() } label: {
            Label("Stop generating", systemImage: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .dsGlass(radius: 16)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("aiChatStop")
    }

    private var limitCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "crown")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.18)))
                .padding(.bottom, 10)
            Text("You've used today's free questions").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
            Text("Premium removes the daily limit and unlocks scans.").font(DS.Text.subheadlineRegular).foregroundStyle(.white.opacity(0.8))
            Button(action: viewModel.upgrade) {
                Text("Go Premium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x0A121F))
                    .padding(.horizontal, 28)
                    .frame(height: 40)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(DS.Gradients.aiCard))
        .padding(.top, 24)
    }

    @ViewBuilder
    private var composer: some View {
        Group {
            if let resetsAt = viewModel.limitResetsAt {
                HStack(spacing: 10) {
                    Image(systemName: "lock").foregroundStyle(DS.Colors.textSecondary)
                    Text("Daily limit reached — resets at \(resetsAt.formatted(date: .omitted, time: .shortened))")
                        .font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(height: 52)
            } else {
                HStack(spacing: 8) {
                    TextField("", text: $viewModel.composerText,
                              prompt: Text("Ask your car anything…").foregroundStyle(DS.Colors.textSecondary), axis: .vertical)
                        .lineLimit(1...5)
                        .font(DS.Text.subheadlineRegular)
                        .foregroundStyle(.white)
                        .tint(DS.Colors.accent)
                        .focused($composerFocused)
                        .submitLabel(.send)
                        .onSubmit { viewModel.send() }
                        .accessibilityIdentifier("aiChatComposer")
                    Button { viewModel.send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(viewModel.canSend ? AnyShapeStyle(DS.Gradients.accentButton) : AnyShapeStyle(Color.white.opacity(0.08))))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canSend)
                    .accessibilityLabel("Send")
                    .accessibilityIdentifier("aiChatSend")
                }
                .padding(.leading, 18)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
            }
        }
        .dsGlass(radius: 26)
        .padding(.horizontal, DS.Layout.gutter)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

private struct MessageBubble: View {
    let text: String
    let isUser: Bool
    let isPartial: Bool
    var isTyping = false

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                if isTyping {
                    TypingDots()
                } else {
                    // Answers may use **bold**; anything that fails to parse shows as plain text.
                    Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
                        .font(DS.Text.button.weight(.regular))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                }
                if isPartial {
                    Text("Stopped").font(DS.Text.statCaption).foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background {
                if isUser {
                    UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20)
                        .fill(DS.Gradients.accentButton)
                } else {
                    UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20)
                        .fill(DS.Gradients.glass)
                        .overlay(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6, bottomTrailingRadius: 20, topTrailingRadius: 20)
                            .strokeBorder(DS.Colors.hairlineStrong))
                }
            }
            if !isUser { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isUser ? "You: " : "Assistant: ") + (isTyping ? "typing" : text))
    }
}

private struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.3)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle().fill(Color.white.opacity(i == step ? 0.9 : 0.35)).frame(width: 7, height: 7)
                }
            }
            .frame(height: 20)
        }
    }
}

/// Conversations, built from Figma 37.
struct ConversationHistoryView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: ConversationsViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "Conversations", onBack: { model?.router.pop() }) {
                    CircleIconButton(symbol: "square.and.pencil", accessibilityLabel: "New conversation") {
                        model?.router.push(.aiChat(nil))
                    }
                }
                if let viewModel { ConversationsContentView(viewModel: viewModel) }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .task {
            guard let model else { return }
            if viewModel == nil {
                let d = model.dependencies
                viewModel = ConversationsViewModel(
                    list: ListConversations(conversations: d.conversations),
                    delete: DeleteConversation(conversations: d.conversations),
                    format: DisplayFormat(calendar: d.clock.calendar, unitSystem: d.preferences.unitSystem),
                    clock: d.clock
                )
            }
            await viewModel?.load()
        }
    }
}

private struct ConversationsContentView: View {
    @Bindable var viewModel: ConversationsViewModel
    @Environment(\.appModel) private var model

    var body: some View {
        VStack(spacing: 16) {
            switch viewModel.state {
            case .loaded:
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(DS.Colors.textSecondary)
                    TextField("", text: $viewModel.searchText,
                              prompt: Text("Search conversations").foregroundStyle(DS.Colors.textSecondary))
                        .font(DS.Text.subheadlineRegular).foregroundStyle(.white).tint(DS.Colors.accent)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .dsGlass(radius: 22)
                ForEach(viewModel.groups) { group in
                    VStack(spacing: 8) {
                        Eyebrow(text: group.title)
                        RowGroup(items: group.rows) { row in
                            Button { model?.router.push(.aiChat(row.id)) } label: {
                                RecordRow(symbol: "bubble.left", title: row.title, subtitle: row.subtitle)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel.remove(row.id) }
                                }
                            }
                        }
                    }
                }
                Text("Conversations are stored in your iCloud and can be deleted any time — press and hold one.")
                    .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .empty:
                EmptyStateView(symbol: "bubble.left.and.bubble.right", title: "No conversations yet",
                               message: "Ask about a warning light, a strange noise or your running costs.",
                               actionTitle: "Ask AI") { model?.router.push(.aiChat(nil)) }
            case .failed(let error):
                EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load conversations",
                               message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
            default:
                ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
            }
        }
        .padding(.horizontal, DS.Layout.gutter)
    }
}
