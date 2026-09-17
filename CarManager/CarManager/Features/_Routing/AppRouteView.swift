import SwiftUI

/// The single route → view mapping for pushed destinations. Adding a route forces a case here,
/// so a destination can never be unreachable by accident.
struct AppRouteView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        // Vehicle
        case .vehicleDetail(let id): VehicleDetailsView(vehicleID: id)
        case .vehicleEditor(let mode): VehicleEditorView(mode: mode)

        // Records
        case .fuelHistory(let id): FuelHistoryView(vehicleID: id)
        case .fuelDetail(let id): FuelDetailsView(entryID: id)
        case .serviceHistory(let id): ServiceHistoryView(vehicleID: id)
        case .serviceDetail(let id): ServiceDetailsView(recordID: id)
        case .expenses(let id): ExpensesView(vehicleID: id)
        case .expenseDetail(let id): ExpenseDetailsView(expenseID: id)
        case .reminders(let id): RemindersView(vehicleID: id)
        case .reminderDetail(let id): ReminderDetailsView(reminderID: id)
        case .documents(let id): DocumentsView(vehicleID: id)
        case .documentDetail(let id): DocumentDetailsView(documentID: id)

        // Analytics
        case .analytics(let id, let period): AnalyticsView(vehicleID: id, period: period)
        case .analyticsSection(let section): AnalyticsSectionView(section: section)

        // AI
        case .aiChat(let id): AIChatView(conversationID: id)
        case .conversationHistory: ConversationHistoryView()
        case .aiInsightDetail(let id): AIInsightDetailsView(insightID: id)
        case .dashboardScanResult(let id): DashboardScanResultView(scanID: id)
        case .damageAnalysisResult(let id): DamageResultView(analysisID: id)

        // Alerts
        case .alerts: AlertsView()
        case .notificationDetail(let id): NotificationDetailsView(notificationID: id)

        // Profile / Settings
        case .settings: SettingsView()
        case .settingsSection(let section): SettingsSectionView(section: section)
        case .manageVehicles: ManageVehiclesView()
        case .defaultVehicle: DefaultVehicleView()
        case .subscriptionSettings: SubscriptionSettingsView()
        case .supportSettings: SupportSettingsView()
        case .legalSettings: LegalSettingsView()
        case .about: AboutView()
        }
    }
}

/// Presents `modalStack[depth]` and recursively hosts the next level, so a paywall really can
/// cover an editor. Binding a single `.sheet` to `modalStack.last` cannot do that — SwiftUI
/// swaps the item instead of stacking, which leaves the presentation broken.
struct ModalHost: ViewModifier {
    let depth: Int
    @Environment(\.appModel) private var model

    func body(content: Content) -> some View {
        content.sheet(item: Binding(
            get: { model?.router.modal(at: depth) },
            set: { if $0 == nil { model?.router.dismissModal(from: depth) } }
        )) { route in
            ModalRouteView(route: route)
                .modifier(ModalHost(depth: depth + 1))
        }
    }
}

/// Sheet presentations.
struct ModalRouteView: View {
    let route: ModalRoute

    var body: some View {
        switch route {
        case .quickLog: QuickLogView()
        case .vehicleEditor(let mode): NavigationStack { VehicleEditorView(mode: mode) }
        case .fuelEditor(let mode): NavigationStack { AddFuelView(mode: mode) }
        case .serviceEditor(let mode): NavigationStack { AddServiceView(mode: mode) }
        case .expenseEditor(let mode): NavigationStack { AddExpenseView(mode: mode) }
        case .reminderEditor(let mode): NavigationStack { AddReminderView(mode: mode) }
        case .documentEditor(let id): NavigationStack { AddDocumentView(vehicleID: id) }
        case .vehiclePicker: VehiclePickerView()
        case .paywall(let context): PaywallView(context: context)
        case .receiptReview(let id): NavigationStack { ReceiptReviewView(scanID: id) }
        case .legal(let document): LegalView(document: document)
        case .shareExport(let url): ShareExportView(url: url)
        case .forgotPassword: NavigationStack { ForgotPasswordView() }
        case .disclaimerAcknowledgement(let kind): DisclaimerAcknowledgementView(kind: kind)
        }
    }
}

/// Full-screen covers — camera and other immersive or blocking flows, isolated from the
/// normal navigation stacks.
struct FullScreenRouteView: View {
    let route: FullScreenRoute

    var body: some View {
        switch route {
        case .onboarding: OnboardingView()
        case .authentication(let entry): AuthenticationFlowView(entryPoint: entry)
        case .camera(let purpose): CameraFlowView(purpose: purpose)
        case .documentViewer(let id): DocumentPreviewView(documentID: id)
        }
    }
}
