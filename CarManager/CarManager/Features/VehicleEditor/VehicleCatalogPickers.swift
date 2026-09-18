import SwiftUI

/// Brand → model → year pickers in the style of classifieds sites (otomoto, OLX): a
/// searchable list with popular brands pinned on top and an A–Z index.
///
/// The catalog suggests, it does not constrain. Whatever is typed into search can be used
/// as-is, so a car the catalog does not know never blocks the user.
///
/// Pickers only report the choice; the editor pops them. The environment's dismiss action is
/// not used because while `.searchable` is active it closes the search field, not the screen.

// MARK: - Brand

struct BrandPickerView: View {
    let catalog: VehicleCatalog?
    let selected: String
    let onSelect: (String) -> Void

    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty {
                if !popular.isEmpty {
                    Section("Popular") {
                        ForEach(popular) { row($0.name) }
                    }
                }
                ForEach(sections, id: \.letter) { section in
                    Section(section.letter) {
                        ForEach(section.brands) { row($0.name) }
                    }
                    .sectionIndexLabel(section.letter)
                }
            } else {
                CustomEntryRow(query: query, existing: brands.flatMap(\.searchNames)) { choose($0) }
                ForEach(CatalogSearch.filter(brands, query: query, names: \.searchNames)) { row($0.name) }
            }

            if let source = catalog?.source {
                CatalogAttribution(source: source)
            }
        }
        .listSectionIndexVisibility(.visible)
        .catalogPickerStyle(title: "Brand")
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search brands"
        )
    }

    private var brands: [VehicleCatalog.Brand] { catalog?.brands ?? [] }
    private var popular: [VehicleCatalog.Brand] { brands.filter(\.popular) }

    /// Grouped by the folded first letter, so Škoda sits under S and Citroën under C.
    private var sections: [(letter: String, brands: [VehicleCatalog.Brand])] {
        let grouped = Dictionary(grouping: brands) { brand -> String in
            guard let first = CatalogSearch.key(brand.name).first else { return "#" }
            return first.isLetter ? String(first).uppercased() : "#"
        }
        return grouped.keys.sorted { lhs, rhs in
            // "#" (names starting with a digit) goes last, as in Contacts.
            lhs == "#" ? false : (rhs == "#" ? true : lhs < rhs)
        }
        .map { ($0, grouped[$0] ?? []) }
    }

    private func row(_ name: String) -> some View {
        PickerRow(title: name, isSelected: CatalogSearch.key(name) == CatalogSearch.key(selected)) {
            choose(name)
        }
    }

    private func choose(_ name: String) { onSelect(name) }
}

// MARK: - Model

struct ModelPickerView: View {
    let brandName: String
    let brand: VehicleCatalog.Brand?
    let selected: String
    let onSelect: (String) -> Void

    @State private var query = ""

    var body: some View {
        List {
            if !query.isEmpty {
                CustomEntryRow(query: query, existing: models.map(\.name)) { choose($0) }
            }
            if models.isEmpty && query.isEmpty {
                Text("No models listed for \(brandName). Type the model name above.")
                    .font(DS.Text.subheadlineRegular)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .listRowBackground(Color.clear)
            }
            ForEach(CatalogSearch.filter(models, query: query, name: \.name)) { model in
                PickerRow(
                    title: model.name,
                    subtitle: VehicleEditorFormatter.productionRange(model),
                    isSelected: CatalogSearch.key(model.name) == CatalogSearch.key(selected)
                ) {
                    choose(model.name)
                }
            }
        }
        .catalogPickerStyle(title: brandName)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search \(brandName) models"
        )
    }

    private var models: [VehicleCatalog.Model] { brand?.models ?? [] }

    private func choose(_ name: String) { onSelect(name) }
}

// MARK: - Year

struct YearPickerView: View {
    let modelName: String?
    /// The chosen model's production years, when known. Offered first; all years stay one tap
    /// away because the source's ranges are not guaranteed to be complete.
    let modelYears: [Int]?
    let allYears: [Int]
    let selected: Int?
    let onSelect: (Int?) -> Void

    @State private var showsAllYears = false

    var body: some View {
        List {
            Section {
                PickerRow(title: "Not specified", isSelected: selected == nil) { choose(nil) }
            }
            Section {
                ForEach(visibleYears, id: \.self) { year in
                    PickerRow(title: String(year), isSelected: year == selected) { choose(year) }
                }
            } header: {
                if isFiltered, let modelName {
                    Text("\(modelName) production years")
                }
            } footer: {
                if isFiltered {
                    Button("Show all years") { showsAllYears = true }
                        .font(DS.Text.button)
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.top, 8)
                        .accessibilityIdentifier("vehicleYearShowAll")
                }
            }
        }
        .catalogPickerStyle(title: "Year")
    }

    private var isFiltered: Bool { modelYears != nil && !showsAllYears }
    private var visibleYears: [Int] { isFiltered ? (modelYears ?? allYears) : allYears }

    private func choose(_ year: Int?) { onSelect(year) }
}

// MARK: - Fuel

struct FuelTypePickerView: View {
    let selected: FuelType
    let onSelect: (FuelType) -> Void


    var body: some View {
        List {
            ForEach(FuelType.allCases) { fuel in
                PickerRow(title: fuel.displayName, isSelected: fuel == selected) { onSelect(fuel) }
            }
        }
        .catalogPickerStyle(title: "Fuel type")
    }
}

// MARK: - Building blocks

private struct PickerRow: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Text.rowTitle)
                        .tracking(DS.Text.defaultTracking)
                        .foregroundStyle(DS.Colors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(DS.Text.caption)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowBackground(DS.Colors.surface)
        .listRowSeparatorTint(Color.white.opacity(0.051))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Use “Syrena”" — offered whenever the search text is not already in the list.
private struct CustomEntryRow: View {
    let query: String
    let existing: [String]
    let action: (String) -> Void

    var body: some View {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if CatalogSearch.isNew(trimmed, among: existing) {
            Button { action(trimmed) } label: {
                Label("Use “\(trimmed)”", systemImage: "plus.circle")
                    .font(DS.Text.rowTitle)
                    .foregroundStyle(DS.Colors.accent)
            }
            .listRowBackground(DS.Colors.surface)
            .accessibilityIdentifier("catalogCustomEntry")
        }
    }
}

/// The data licence (ODbL) requires attribution wherever the data is shown.
private struct CatalogAttribution: View {
    let source: VehicleCatalog.Source

    /// Built as markdown so the project name is a tappable link. A plain interpolated
    /// `Text` would not parse it.
    private var attribution: AttributedString {
        let markdown = "Brand and model data: [\(source.name)](\(source.url)), "
            + "compiled from \(source.upstream). \(source.license)."
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    var body: some View {
        Section {
            EmptyView()
        } footer: {
            Text(attribution)
                .font(DS.Text.caption)
                .foregroundStyle(DS.Colors.textSecondary)
                .tint(DS.Colors.textSecondary)
        }
    }
}

private extension View {
    func catalogPickerStyle(title: String) -> some View {
        self
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Colors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}
