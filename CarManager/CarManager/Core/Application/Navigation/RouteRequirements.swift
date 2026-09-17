import Foundation

/// What a destination needs before it may be shown. Declared as data next to the routes,
/// so adding a route forces a decision about its gating.
public struct RouteRequirements: Sendable, Hashable {
    public var requiresAccount: Bool
    public var requiredFeature: PremiumFeature?
    public var requiresVehicle: Bool
    public var requiredDisclaimer: DisclaimerKind?

    public init(
        requiresAccount: Bool = false, requiredFeature: PremiumFeature? = nil,
        requiresVehicle: Bool = false, requiredDisclaimer: DisclaimerKind? = nil
    ) {
        self.requiresAccount = requiresAccount
        self.requiredFeature = requiredFeature
        self.requiresVehicle = requiresVehicle
        self.requiredDisclaimer = requiredDisclaimer
    }

    public static let none = RouteRequirements()
}

public extension AppRoute {
    var requirements: RouteRequirements {
        switch self {
        case .vehicleDetail, .vehicleEditor, .manageVehicles, .defaultVehicle:
            .none
        case .fuelHistory, .fuelDetail, .serviceHistory, .serviceDetail,
             .expenses, .expenseDetail, .reminders, .reminderDetail,
             .documents, .documentDetail, .alerts, .notificationDetail:
            RouteRequirements(requiresVehicle: true)
        case .analytics, .analyticsSection:
            RouteRequirements(requiredFeature: .advancedAnalytics, requiresVehicle: true)
        case .aiChat, .conversationHistory:
            RouteRequirements(requiresAccount: true, requiredFeature: .aiChat)
        case .aiInsightDetail:
            RouteRequirements(requiredFeature: .aiInsights)
        case .dashboardScanResult, .damageAnalysisResult:
            .none
        case .settings, .settingsSection, .subscriptionSettings,
             .supportSettings, .legalSettings, .about:
            .none
        }
    }
}

public extension ModalRoute {
    var requirements: RouteRequirements {
        switch self {
        case .quickLog, .vehiclePicker, .paywall, .legal, .forgotPassword,
             .disclaimerAcknowledgement, .vehicleEditor:
            .none
        // Gating happens before the file is produced, so presenting it needs nothing.
        case .shareExport:
            .none
        case .fuelEditor, .serviceEditor, .expenseEditor, .reminderEditor, .documentEditor:
            RouteRequirements(requiresVehicle: true)
        case .receiptReview:
            RouteRequirements(requiredFeature: .receiptScan, requiresVehicle: true)
        }
    }
}

public extension FullScreenRoute {
    var requirements: RouteRequirements {
        switch self {
        case .onboarding, .authentication, .documentViewer:
            .none
        case .camera(let purpose):
            switch purpose {
            case .receipt:
                RouteRequirements(requiredFeature: .receiptScan, requiresVehicle: true)
            case .dashboard:
                RouteRequirements(
                    requiredFeature: .dashboardScan,
                    requiredDisclaimer: .notProfessionalDiagnostics
                )
            case .damage:
                RouteRequirements(
                    requiredFeature: .damageAnalysis, requiresVehicle: true,
                    requiredDisclaimer: .costEstimateOnly
                )
            case .plate:
                RouteRequirements(requiredFeature: .plateScan)
            case .vehiclePhoto:
                .none
            }
        }
    }
}
