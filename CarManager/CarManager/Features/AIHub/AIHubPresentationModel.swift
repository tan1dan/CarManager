import Foundation

/// Display-ready values for the AI tab (Figma node 3:5048).
struct AIHubPresentationModel: Equatable, Sendable {
    var tools: [Tool]
    var recentChats: RecentChats
    /// Only shown when some conversations did not fit in the list — otherwise every chat is
    /// already on screen and the link would lead nowhere new.
    var showsAllChatsLink: Bool

    struct Tool: Equatable, Sendable, Identifiable {
        enum Kind: String, Sendable, CaseIterable {
            case dashboard, receipt, damage, chat
        }

        var id: Kind { kind }
        var kind: Kind
        var symbolName: String
        var title: String
        var subtitle: String
        /// Display-only. Tapping a locked tool still navigates; RouteGuard decides what the
        /// user ends up seeing (normally the paywall with the right context).
        var isLocked: Bool
    }

    struct ChatRow: Equatable, Sendable, Identifiable {
        var id: ConversationID
        var title: String
        var subtitle: String
    }

    enum RecentChats: Equatable, Sendable {
        case loading
        case empty
        case loaded([ChatRow])
        case failed(String)
    }

    static let placeholder = AIHubPresentationModel(
        tools: AIHubFormatter.tools { _ in false },
        recentChats: .loading,
        showsAllChatsLink: false
    )
}

extension AIHubPresentationModel.Tool.Kind {
    var feature: PremiumFeature {
        switch self {
        case .dashboard: .dashboardScan
        case .receipt: .receiptScan
        case .damage: .damageAnalysis
        case .chat: .aiChat
        }
    }
}

/// Pure mapping onto display values. The clock and locale are injected so "Yesterday" and
/// "Nov 3" are deterministic under test.
struct AIHubFormatter: Sendable {
    /// The design shows two rows; three keeps the section short while leaving room for one
    /// more before "See all" is needed.
    static let recentChatLimit = 3

    let now: Date
    let calendar: Calendar
    let locale: Locale

    func makeModel(
        summaries: [ConversationSummary],
        isLocked: (PremiumFeature) -> Bool
    ) -> AIHubPresentationModel {
        let visible = summaries.prefix(Self.recentChatLimit).map { summary in
            AIHubPresentationModel.ChatRow(
                id: summary.id,
                title: summary.title,
                subtitle: relativeDay(summary.updatedAt)
            )
        }
        return AIHubPresentationModel(
            tools: Self.tools(isLocked: isLocked),
            recentChats: visible.isEmpty ? .empty : .loaded(visible),
            showsAllChatsLink: summaries.count > Self.recentChatLimit
        )
    }

    static func tools(isLocked: (PremiumFeature) -> Bool) -> [AIHubPresentationModel.Tool] {
        [
            .init(kind: .dashboard, symbolName: "camera", title: "Scan Dashboard",
                  subtitle: "Warning lights", isLocked: isLocked(.dashboardScan)),
            .init(kind: .receipt, symbolName: "receipt", title: "Scan Receipt",
                  subtitle: "Auto-fill expense", isLocked: isLocked(.receiptScan)),
            .init(kind: .damage, symbolName: "exclamationmark.shield", title: "Analyze Damage",
                  subtitle: "Photo diagnosis", isLocked: isLocked(.damageAnalysis)),
            .init(kind: .chat, symbolName: "message", title: "Ask AI",
                  subtitle: "Anything car", isLocked: isLocked(.aiChat))
        ]
    }

    /// "Today", "Yesterday", "Nov 3", or "Nov 3, 2024" once the year differs.
    func relativeDay(_ date: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            style = style.year()
        }
        return date.formatted(style)
    }
}
