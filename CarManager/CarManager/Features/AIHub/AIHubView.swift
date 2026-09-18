import SwiftUI

/// The AI tab, built from Figma node 3:5048.
///
/// Spacing is normalised to the rest of the app: the design's tiles use 17pt padding and a
/// 12.7pt caption gap; here they use 16pt and the shared section container's 8pt.
struct AIHubView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: AIHubViewModel?

    private enum Metrics {
        static let heroPadding: CGFloat = 24
        static let heroIconSize: CGFloat = 44
        static let tileSpacing: CGFloat = 12
        static let tilePadding: CGFloat = 16
        static let tileIconSize: CGFloat = 40
        static let glowSize: CGFloat = 160
    }

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: DS.Layout.sectionSpacing) {
                    hero
                    toolGrid
                    recentChats
                }
                .padding(.horizontal, DS.Layout.gutter)
                .padding(.top, 16)
                .padding(.bottom, DS.Layout.tabBarReservedHeight)
            }
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        // `.task` runs once per identity; `onAppear` also fires when a chat is popped, so a
        // conversation started there shows up here without a manual refresh.
        .onAppear { Task { await load() } }
    }

    // MARK: - Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: Metrics.heroIconSize, height: Metrics.heroIconSize)
                .background(Circle().fill(Color.white.opacity(0.149)))
                .padding(.bottom, 16)

            Text("AI Car\nAssistant")
                .font(DS.Text.aiHero)
                .tracking(DS.Text.aiHeroTracking)
                .foregroundStyle(.white)
                .padding(.bottom, 8)

            Text("Diagnose, scan, analyze, and get instant answers.")
                .font(DS.Text.subheadlineRegular)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(Color.white.opacity(0.749))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 44)
        }
        .padding(Metrics.heroPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                DS.Gradients.aiCard
                Circle()
                    .fill(Color.white.opacity(0.149))
                    .frame(width: Metrics.glowSize, height: Metrics.glowSize)
                    .blur(radius: 64)
                    .offset(x: 40, y: -40)
            }
        }
        .clipShape(.rect(cornerRadius: DS.Layout.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var toolGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Metrics.tileSpacing),
                count: 2
            ),
            spacing: Metrics.tileSpacing
        ) {
            ForEach(presentation.tools) { tool in
                toolTile(tool)
            }
        }
    }

    private func toolTile(_ tool: AIHubPresentationModel.Tool) -> some View {
        Button { open(tool.kind) } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: Metrics.tileIconSize, height: Metrics.tileIconSize)
                    .background(Circle().fill(DS.Colors.accent.opacity(0.149)))
                    .padding(.bottom, 12)

                Text(tool.title)
                    .font(DS.Text.button)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(tool.subtitle)
                    .font(DS.Text.statCaption)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(Metrics.tilePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                if tool.isLocked {
                    // Not in the design, which is drawn for a subscriber. A free user should
                    // see which tools lead to the paywall before tapping them.
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .padding(Metrics.tilePadding)
                }
            }
            .dsSurface()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("\(tool.title), \(tool.subtitle)"))
        .accessibilityValue(tool.isLocked ? Text("Premium") : Text(""))
        .accessibilityIdentifier(Self.identifier(for: tool.kind))
    }

    private var recentChats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT CHATS")
                    .font(DS.Text.eyebrowSmall)
                    .tracking(DS.Text.eyebrowSmallTracking)
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                if presentation.showsAllChatsLink {
                    Button("See all") { model?.router.push(.conversationHistory, in: .ai) }
                        .font(DS.Text.eyebrowSmall)
                        .foregroundStyle(DS.Colors.accent)
                        .accessibilityIdentifier("aiConversationHistory")
                }
            }

            VStack(spacing: 0) { recentChatsContent }
                .dsSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var recentChatsContent: some View {
        switch presentation.recentChats {
        case .loading:
            ProgressView()
                .tint(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
        case .empty:
            SettingsRowView(
                symbolName: "message",
                title: "Start a conversation",
                subtitle: "Ask anything about your car",
                action: { open(.chat) }
            ) {
                SettingsRowChevron()
            }
            .accessibilityIdentifier("aiStartConversation")
        case .loaded(let rows):
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                SettingsRowView(
                    symbolName: "message",
                    title: row.title,
                    subtitle: row.subtitle,
                    action: { model?.router.push(.aiChat(row.id), in: .ai) }
                ) {
                    SettingsRowChevron()
                }
                .accessibilityIdentifier("aiRecentChat_\(index)")
                if index < rows.count - 1 {
                    SettingsRowSeparator()
                }
            }
        case .failed(let message):
            Text(message)
                .font(DS.Text.subheadlineRegular)
                .foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    // MARK: - Actions

    /// Navigation only. Whether the destination is actually reachable is RouteGuard's call —
    /// a locked tool lands on the paywall with the matching context.
    private func open(_ kind: AIHubPresentationModel.Tool.Kind) {
        guard let router = model?.router else { return }
        switch kind {
        case .dashboard: router.presentFullScreen(.camera(.dashboard))
        case .receipt: router.presentFullScreen(.camera(.receipt))
        case .damage: router.presentFullScreen(.camera(.damage))
        case .chat: router.push(.aiChat(nil), in: .ai)
        }
    }

    private static func identifier(for kind: AIHubPresentationModel.Tool.Kind) -> String {
        switch kind {
        case .dashboard: "aiScanDashboard"
        case .receipt: "aiScanReceipt"
        case .damage: "aiAnalyzeDamage"
        case .chat: "aiAskAI"
        }
    }

    // MARK: - Wiring

    private var presentation: AIHubPresentationModel {
        viewModel?.presentation ?? .placeholder
    }

    private func load() async {
        guard let model else { return }
        if viewModel == nil {
            viewModel = AIHubViewModel(
                listConversations: ListConversations(conversations: model.dependencies.conversations),
                featureGate: model.featureGate,
                clock: model.dependencies.clock
            )
        }
        await viewModel?.load()
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
