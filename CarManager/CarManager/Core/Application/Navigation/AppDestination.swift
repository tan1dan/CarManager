import Foundation

/// The tab set. The central "+" is NOT a tab — it presents `ModalRoute.quickLog`.
/// Analytics is a full feature module reachable from Home, Vehicle Detail and Profile;
/// promoting it to a fifth tab later is a one-line change here.
public enum AppTab: String, CaseIterable, Codable, Sendable, Identifiable {
    case home, garage, ai, profile
    public var id: String { rawValue }

    public var titleKey: String {
        switch self {
        case .home: "tab.home"
        case .garage: "tab.garage"
        case .ai: "tab.ai"
        case .profile: "tab.profile"
        }
    }

    public var systemImage: String {
        switch self {
        case .home: "house"
        case .garage: "car.2"
        case .ai: "sparkles"
        case .profile: "person.crop.circle"
        }
    }
}

public enum VehicleEditorMode: Hashable, Codable, Sendable {
    case create
    case edit(VehicleID)
}

public enum RecordEditorMode: Hashable, Codable, Sendable {
    case create(VehicleID)
    case edit(vehicleID: VehicleID, recordID: UUID)

    public var vehicleID: VehicleID {
        switch self {
        case .create(let id): id
        case .edit(let id, _): id
        }
    }
}

public enum AnalyticsSection: String, Hashable, Codable, Sendable {
    case consumption, costs, categories, ownership
}

public enum SettingsSection: String, Hashable, Codable, Sendable, Identifiable, CaseIterable {
    case account, units, currency, language, appearance, notifications, data, about
    public var id: String { rawValue }
}

public enum LegalDocument: String, Hashable, Codable, Sendable, Identifiable {
    case privacyPolicy, termsOfUse
    public var id: String { rawValue }
}

public enum CameraPurpose: String, Hashable, Codable, Sendable {
    case receipt, dashboard, damage, plate, vehiclePhoto
}

public enum AuthEntryPoint: String, Hashable, Codable, Sendable {
    case signIn, signUp
}

/// Why the paywall appeared. A context-free paywall is a wasted paywall — and this lets
/// conversion be attributed per trigger.
public enum PaywallContext: Hashable, Codable, Sendable {
    case vehicleLimit
    case feature(PremiumFeature)
    case aiQuota(resetAt: Date)
    case settingsUpgrade
    case onboarding
}

/// Pushed destinations. One unified set so a deep link can target any of them.
public enum AppRoute: Hashable, Codable, Sendable {
    // Vehicle
    case vehicleDetail(VehicleID)
    case vehicleEditor(VehicleEditorMode)
    // Records
    case fuelHistory(VehicleID)
    case fuelDetail(FuelEntryID)
    case serviceHistory(VehicleID)
    case serviceDetail(ServiceRecordID)
    case expenses(VehicleID)
    case expenseDetail(ExpenseID)
    case reminders(VehicleID)
    case reminderDetail(ReminderID)
    case documents(VehicleID?)
    case documentDetail(DocumentID)
    // Analytics
    case analytics(VehicleID?, AnalyticsPeriod)
    case analyticsSection(AnalyticsSection)
    // AI
    case aiChat(ConversationID?)
    case conversationHistory
    case aiInsightDetail(InsightID)
    case dashboardScanResult(DashboardScanID)
    case damageAnalysisResult(DamageAnalysisID)
    // Alerts
    case alerts
    case notificationDetail(NotificationID)
    // Profile / Settings
    case settings
    case settingsSection(SettingsSection)
    case manageVehicles
    case defaultVehicle
    case subscriptionSettings
    case supportSettings
    case legalSettings
    case about
}

/// Sheets. Dismissible, non-committal, may stack (a paywall over an editor).
public enum ModalRoute: Hashable, Codable, Sendable, Identifiable {
    case quickLog
    case vehicleEditor(VehicleEditorMode)
    case fuelEditor(RecordEditorMode)
    case serviceEditor(RecordEditorMode)
    case expenseEditor(RecordEditorMode)
    case reminderEditor(RecordEditorMode)
    case documentEditor(VehicleID?)
    case vehiclePicker
    case paywall(PaywallContext)
    case receiptReview(ReceiptScanID)
    case legal(LegalDocument)
    /// Hands a generated file to the system share sheet.
    case shareExport(URL)
    case forgotPassword
    case disclaimerAcknowledgement(DisclaimerKind)

    public var id: Self { self }
}

/// Full-screen covers. Immersive or blocking flows, isolated from the navigation stack.
public enum FullScreenRoute: Hashable, Codable, Sendable, Identifiable {
    case onboarding
    case authentication(AuthEntryPoint)
    case camera(CameraPurpose)
    case documentViewer(DocumentID)

    public var id: Self { self }
}

/// The single addressable unit for deep links, notification taps, tests and state restoration.
public struct AppDestination: Hashable, Codable, Sendable {
    public var tab: AppTab?
    public var path: [AppRoute]
    public var modal: ModalRoute?
    public var fullScreen: FullScreenRoute?

    public init(
        tab: AppTab? = nil, path: [AppRoute] = [],
        modal: ModalRoute? = nil, fullScreen: FullScreenRoute? = nil
    ) {
        self.tab = tab; self.path = path; self.modal = modal; self.fullScreen = fullScreen
    }

    public static func tab(_ tab: AppTab, path: [AppRoute] = []) -> AppDestination {
        AppDestination(tab: tab, path: path)
    }
    public static func modal(_ modal: ModalRoute) -> AppDestination {
        AppDestination(modal: modal)
    }
    public static func fullScreen(_ route: FullScreenRoute) -> AppDestination {
        AppDestination(fullScreen: route)
    }
}
