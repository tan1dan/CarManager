import SwiftUI

/// The central Add action, built from Figma node 3:4415.
///
/// Each row is guard-evaluated individually, so a free user sees the paywall on Scan Receipt
/// but the editor on Add Fuel. The design draws this over the tab bar; it stays a sheet so it
/// keeps the modal stack's replace-on-select behaviour and can be swiped away.
struct QuickLogView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        ZStack {
            DS.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VStack(spacing: 12) {
                        ForEach(items) { item in
                            row(item)
                        }
                    }
                    .padding(.horizontal, DS.Layout.gutter)
                }
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(DS.Colors.background)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Quick log")
                .font(DS.Text.subheadline)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(DS.Colors.textSecondary)
            Text("What's new?")
                .font(DS.Text.title)
                .tracking(DS.Text.titleTracking)
                .foregroundStyle(DS.Colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, DS.Layout.headerGutter)
    }

    private func row(_ item: QuickLogMenu.Item) -> some View {
        SettingsRowView(
            symbolName: item.symbolName,
            title: item.title,
            subtitle: item.subtitle,
            iconStyle: item.iconStyle,
            action: { perform(item.action) }
        ) {
            HStack(spacing: 8) {
                if item.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .accessibilityLabel(Text("Premium"))
                }
                SettingsRowChevron()
            }
        }
        .dsSurface()
        .accessibilityIdentifier(Self.identifier(for: item.action))
    }

    // MARK: - Actions

    private var items: [QuickLogMenu.Item] {
        QuickLogMenu.items { feature in model?.featureGate.canUse(feature) == false }
    }

    private func perform(_ action: QuickLogMenu.Action) {
        switch action {
        case .fuel: replace(.fuelEditor(.create(vehicleID)))
        case .service: replace(.serviceEditor(.create(vehicleID)))
        case .expense: replace(.expenseEditor(.create(vehicleID)))
        case .reminder: replace(.reminderEditor(.create(vehicleID)))
        case .scanReceipt: fullScreen(.camera(.receipt))
        case .document: replace(.documentEditor(model?.selectedVehicleID))
        }
    }

    private var vehicleID: VehicleID { model?.selectedVehicleID ?? VehicleID() }

    /// Replace rather than stack: the quick-log sheet steps aside for the next sheet.
    private func replace(_ route: ModalRoute) { model?.router.replaceModal(with: route) }

    private func fullScreen(_ route: FullScreenRoute) {
        model?.router.dismissModal()
        model?.router.presentFullScreen(route)
    }

    private static func identifier(for action: QuickLogMenu.Action) -> String {
        switch action {
        case .fuel: "quickLogAddFuel"
        case .service: "quickLogAddService"
        case .expense: "quickLogAddExpense"
        case .reminder: "quickLogAddReminder"
        case .scanReceipt: "quickLogScanReceipt"
        case .document: "quickLogAddDocument"
        }
    }
}
