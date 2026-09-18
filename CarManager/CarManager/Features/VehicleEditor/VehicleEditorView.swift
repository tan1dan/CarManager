import SwiftUI

/// Add and Edit share one editor — the mode distinguishes them. Built from Figma node 3:4358.
///
/// Brand, model, year and fuel open searchable lists (see `VehicleCatalogPickers`) instead
/// of free-text fields; VIN and mileage are typed in place.
struct VehicleEditorView: View {
    let mode: VehicleEditorMode
    @Environment(\.appModel) private var model
    @State private var viewModel: VehicleEditorViewModel?

    /// Owned here rather than by the modal host so a picker can be popped explicitly.
    @State private var path: [VehicleEditorPicker] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DS.Colors.background.ignoresSafeArea()
                if let viewModel {
                    VehicleEditorContentView(viewModel: viewModel, closePicker: closePicker)
                } else {
                    ProgressView().tint(DS.Colors.textSecondary)
                }
            }
        }
        // Dark at the stack level so the pickers' bars and search fields match.
        .environment(\.colorScheme, .dark)
        .task {
            guard viewModel == nil, let model else { return }
            let created = VehicleEditorViewModel(
                mode: mode,
                createVehicle: CreateVehicle(
                    vehicles: model.dependencies.vehicles,
                    odometer: model.dependencies.odometer,
                    reminders: model.dependencies.reminders,
                    clock: model.dependencies.clock
                ),
                updateVehicle: UpdateVehicle(
                    vehicles: model.dependencies.vehicles, clock: model.dependencies.clock
                ),
                loadCatalog: LoadVehicleCatalog(catalog: model.dependencies.vehicleCatalog),
                vehicles: model.dependencies.vehicles,
                vehicleStore: model.vehicles,
                featureGate: model.featureGate,
                router: model.router,
                clock: model.dependencies.clock
            )
            viewModel = created
            await created.prepare()
        }
    }

    private func closePicker() {
        if !path.isEmpty { path.removeLast() }
    }
}

private enum VehicleEditorPicker: Hashable {
    case brand, model, year, fuel
}

private struct VehicleEditorContentView: View {
    @Bindable var viewModel: VehicleEditorViewModel
    let closePicker: () -> Void
    @Environment(\.appModel) private var model

    private enum Metrics {
        static let rowHeight: CGFloat = 54
        static let rowPadding: CGFloat = 16
        static let scanButtonHeight: CGFloat = 84
        static let ctaHeight: CGFloat = 56
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                scanPlateButton
                fields
                saveButton
                if let error = viewModel.state.error {
                    Text(error.messageKey)
                        .font(DS.Text.subheadlineRegular)
                        .foregroundStyle(DS.Colors.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("vehicleEditorError")
                }
            }
            .padding(.horizontal, DS.Layout.gutter)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .navigationDestination(for: VehicleEditorPicker.self, destination: picker)
        // The design's Cancel / title / Save row IS a navigation bar, so it is built as one.
        // A hidden bar plus a hand-drawn header left a stale inset after popping a picker
        // whose search field was active.
        .navigationTitle(viewModel.isCreating ? "Add vehicle" : "Edit vehicle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Colors.background, for: .navigationBar)
        .toolbar { header }
    }

    // MARK: - Sections

    @ToolbarContentBuilder
    private var header: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { model?.router.dismissModal() }
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Colors.onCardSecondary)
                .accessibilityIdentifier("vehicleCancel")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .font(DS.Text.rowTitle)
                .foregroundStyle(viewModel.canSave ? DS.Colors.accent : DS.Colors.textSecondary)
                .disabled(!viewModel.canSave)
                .accessibilityIdentifier("vehicleSaveTop")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var scanPlateButton: some View {
        Button { model?.router.presentFullScreen(.camera(.plate)) } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera")
                    .font(.system(size: 14, weight: .semibold))
                Text("Scan license plate")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(DS.Text.defaultTracking)
                if viewModel.isPlateScanLocked {
                    // Plate scanning is premium; RouteGuard sends a free user to the paywall.
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .foregroundStyle(DS.Colors.accent)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.scanButtonHeight)
            .dsSurface()
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vehicleScanPlate")
    }

    private var fields: some View {
        VStack(spacing: 0) {
            pickerRow("Brand", value: viewModel.draft.brand, destination: .brand, id: "vehicleBrand")
            SettingsRowSeparator()
            pickerRow(
                "Model", value: viewModel.draft.model, destination: .model, id: "vehicleModel",
                isEnabled: !viewModel.draft.brand.isEmpty,
                placeholder: viewModel.draft.brand.isEmpty ? "Choose brand first" : "Select"
            )
            SettingsRowSeparator()
            pickerRow(
                "Year", value: viewModel.draft.year.map(String.init) ?? "",
                destination: .year, id: "vehicleYear"
            )
            SettingsRowSeparator()
            pickerRow(
                "Fuel type", value: viewModel.draft.fuelType.displayName,
                destination: .fuel, id: "vehicleFuel"
            )
            SettingsRowSeparator()
            textRow("VIN") {
                TextField("Optional", text: Binding(
                    get: { viewModel.draft.vin ?? "" },
                    // Raw text goes into the draft; CreateVehicle/UpdateVehicle normalise it.
                    set: { viewModel.draft.vin = $0 }
                ))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .accessibilityIdentifier("vehicleVINField")
            }
            if viewModel.isCreating {
                // Mileage seeds the first odometer reading. After that it changes through
                // fuel and service entries, so Edit does not offer it.
                SettingsRowSeparator()
                textRow("Mileage") {
                    HStack(spacing: 4) {
                        TextField("0", text: $viewModel.mileageText)
                            .keyboardType(.numberPad)
                            .accessibilityIdentifier("vehicleMileageField")
                        Text("km").foregroundStyle(DS.Colors.onCardTertiary)
                    }
                }
            }
        }
        .dsSurface()
    }

    private var saveButton: some View {
        Button { save() } label: {
            Group {
                if viewModel.isSaving {
                    ProgressView().tint(.white)
                } else {
                    Text(viewModel.isCreating ? "Add to garage" : "Save changes")
                        .font(DS.Text.rowTitle)
                        .tracking(DS.Text.defaultTracking)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.ctaHeight)
            .background(Capsule().fill(DS.Gradients.accentButton))
            .opacity(viewModel.canSave ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSave)
        .accessibilityIdentifier("vehicleSave")
    }

    // MARK: - Rows

    private func pickerRow(
        _ label: String, value: String, destination: VehicleEditorPicker, id: String,
        isEnabled: Bool = true, placeholder: String = "Select"
    ) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 8) {
                rowLabel(label)
                Spacer(minLength: 12)
                Text(value.isEmpty ? placeholder : value)
                    .font(value.isEmpty ? DS.Text.subheadlineRegular : DS.Text.button)
                    .tracking(DS.Text.defaultTracking)
                    .foregroundStyle(value.isEmpty ? DS.Colors.onCardTertiary : .white)
                    .lineLimit(1)
                // Not in the design: marks the rows that open a list, unlike VIN and Mileage.
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.onCardTertiary)
            }
            .padding(.horizontal, Metrics.rowPadding)
            .frame(height: Metrics.rowHeight)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityIdentifier(id)
    }

    private func textRow(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        HStack(spacing: 12) {
            rowLabel(label)
            field()
                .font(DS.Text.button)
                .tracking(DS.Text.defaultTracking)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, Metrics.rowPadding)
        .frame(height: Metrics.rowHeight)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Text.subheadlineRegular)
            .tracking(DS.Text.defaultTracking)
            .foregroundStyle(DS.Colors.onCardTertiary)
            .fixedSize()
    }

    // MARK: - Pickers

    @ViewBuilder
    private func picker(_ destination: VehicleEditorPicker) -> some View {
        switch destination {
        case .brand:
            BrandPickerView(
                catalog: viewModel.catalog,
                selected: viewModel.draft.brand,
                onSelect: { viewModel.selectBrand($0); closePicker() }
            )
        case .model:
            ModelPickerView(
                brandName: viewModel.draft.brand,
                brand: viewModel.selectedBrand,
                selected: viewModel.draft.model,
                onSelect: { viewModel.selectModel($0); closePicker() }
            )
        case .year:
            YearPickerView(
                modelName: viewModel.selectedModel?.name,
                modelYears: viewModel.modelYears,
                allYears: viewModel.allYears,
                selected: viewModel.draft.year,
                onSelect: { viewModel.draft.year = $0; closePicker() }
            )
        case .fuel:
            FuelTypePickerView(
                selected: viewModel.draft.fuelType,
                onSelect: { viewModel.draft.fuelType = $0; closePicker() }
            )
        }
    }

    private func save() {
        Task { await viewModel.save() }
    }
}
