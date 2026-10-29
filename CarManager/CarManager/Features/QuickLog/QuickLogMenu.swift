import Foundation

/// The rows of the Add menu (Figma node 3:4415), in design order. Pure, so the order and
/// lock state are testable without a view.
enum QuickLogMenu {
    enum Action: String, Sendable, CaseIterable {
        case fuel, service, expense, reminder, scanReceipt, document
    }

    struct Item: Equatable, Sendable, Identifiable {
        var id: Action { action }
        var action: Action
        var symbolName: String
        var title: String
        var subtitle: String
        var iconStyle: RowIconStyle
        /// Display-only; RouteGuard still decides where the tap lands.
        var isLocked: Bool
    }

    static func items(isLocked: (PremiumFeature) -> Bool) -> [Item] {
        [
            .init(action: .fuel, symbolName: "fuelpump", title: String(localized: "Add Fuel"),
                  subtitle: String(localized: "Log a fill-up"), iconStyle: .accent, isLocked: false),
            .init(action: .service, symbolName: "wrench.adjustable", title: String(localized: "Add Service"),
                  subtitle: String(localized: "Maintenance record"), iconStyle: .neutral, isLocked: false),
            .init(action: .expense, symbolName: "dollarsign.square", title: String(localized: "Add Expense"),
                  subtitle: String(localized: "Any car cost"), iconStyle: .neutral, isLocked: false),
            .init(action: .reminder, symbolName: "bell", title: String(localized: "Add Reminder"),
                  subtitle: String(localized: "Never miss a date"), iconStyle: .accent, isLocked: false),
            .init(action: .scanReceipt, symbolName: "camera", title: String(localized: "Scan Receipt"),
                  subtitle: String(localized: "AI recognition"), iconStyle: .ai, isLocked: isLocked(.receiptScan)),
            .init(action: .document, symbolName: "doc.badge.arrow.up", title: String(localized: "Upload Document"),
                  subtitle: String(localized: "PDF · image"), iconStyle: .neutral, isLocked: false)
        ]
    }
}
