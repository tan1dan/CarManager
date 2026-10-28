import SwiftUI

// Settings sub-screens, built from Figma 43 (Units), 47 (Notifications), 49 (Subscription).
// Preferences live behind `PreferencesProviding`, which is not observable, so each screen
// keeps a local copy and writes through on change.

/// A titled group of rows on a settings sub-screen.
private struct SettingsGroup<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 8) {
            if let title { Eyebrow(text: title) }
            VStack(spacing: 0) { content }.dsSurface()
        }
    }
}

/// Icon disc, title, optional subtitle and a trailing control — the Figma settings row.
private struct SettingsLine<Trailing: View>: View {
    let symbol: String
    let title: String
    var subtitle: String?
    var isFirst = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.051)))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(DS.Text.rowTitle).foregroundStyle(DS.Colors.textPrimary)
                if let subtitle { Text(subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 68)
        .overlay(alignment: .top) { if !isFirst { SettingsRowSeparator() } }
        .contentShape(.rect)
    }
}

/// A menu-backed value ("Kilometres ⌄").
private struct MenuValue<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        Menu {
            Picker("", selection: $selection) {
                ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(options.first { $0.0 == selection }?.1 ?? "").font(DS.Text.button).foregroundStyle(.white)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(DS.Colors.textSecondary)
            }
        }
    }
}

private struct SubscreenScaffold<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.appModel) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: title, onBack: { model?.router.pop() })
                VStack(spacing: DS.Layout.sectionSpacing) { content }
                    .padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
    }
}

private struct Footnote: View {
    let text: String
    var body: some View {
        Text(text).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSectionView: View {
    let section: SettingsSection

    var body: some View {
        switch section {
        case .units, .language: UnitsSettingsView()
        case .currency: CurrencyPickerView()
        case .notifications: NotificationSettingsView()
        case .account: AccountSettingsView()
        case .appearance, .data, .about: AboutView()
        }
    }
}

// MARK: - Units & language (Figma 43)

private struct UnitsSettingsView: View {
    @Environment(\.appModel) private var model
    @Environment(\.openURL) private var openURL
    @State private var unitSystem: UnitSystem = .metric
    @State private var currency = CurrencyCode.eur

    var body: some View {
        SubscreenScaffold(title: "Units & language") {
            SettingsGroup(title: "Units") {
                SettingsLine(symbol: "gauge.with.dots.needle.33percent", title: "Distance", isFirst: true) {
                    MenuValue(options: [(.metric, "Kilometres"), (.imperial, "Miles")], selection: $unitSystem)
                        .accessibilityIdentifier("unitsPicker")
                }
                SettingsLine(symbol: "drop", title: "Volume", subtitle: "Follows distance") {
                    Text(unitSystem == .metric ? "Litres" : "Gallons").font(DS.Text.button).foregroundStyle(DS.Colors.textSecondary)
                }
                Button { model?.router.push(.settingsSection(.currency)) } label: {
                    SettingsLine(symbol: "banknote", title: "Currency", subtitle: CurrencyInfo(currency).name) {
                        HStack(spacing: 8) {
                            CurrencyBadge(info: CurrencyInfo(currency), size: 30)
                            SettingsRowChevron()
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settingsCurrency")
            }
            SettingsGroup(title: "Language") {
                Button { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } } label: {
                    SettingsLine(symbol: "globe", title: "App language", subtitle: "Changed in iOS Settings", isFirst: true) {
                        HStack(spacing: 6) {
                            Text(Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "")
                                .font(DS.Text.button).foregroundStyle(.white)
                            SettingsRowChevron()
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Footnote(text: unitSystem == .metric
                     ? "Consumption is shown as L/100 km. Switching to miles changes it to mpg everywhere."
                     : "Consumption is shown as mpg (US). Your records stay stored in metric.")
        }
        // onAppear, not task: coming back from the currency list must show the new choice.
        .onAppear {
            guard let preferences = model?.dependencies.preferences else { return }
            unitSystem = preferences.unitSystem
            currency = preferences.defaultCurrency
        }
        .onChange(of: unitSystem) { _, value in model?.dependencies.preferences.unitSystem = value }
    }
}

// MARK: - Notifications (Figma 47)

private struct NotificationSettingsView: View {
    @Environment(\.appModel) private var model
    @Environment(\.openURL) private var openURL
    @State private var enabled = true
    @State private var system: NotificationAuthorization?

    var body: some View {
        SubscreenScaffold(title: "Notifications") {
            SettingsGroup(title: "What to send") {
                SettingsLine(symbol: "bell", title: "Reminders", subtitle: "Insurance, service, inspection, documents", isFirst: true) {
                    Toggle("", isOn: $enabled).labelsHidden().tint(DS.Colors.accent)
                }
            }
            Footnote(text: "Date reminders notify ahead of time. Mileage reminders show in the app as you log the odometer — iOS can't trigger on distance.")
            if system == .denied {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle").foregroundStyle(DS.Colors.warning)
                    Text("Notifications are off for Car Manager in iOS Settings.")
                        .font(DS.Text.caption).foregroundStyle(.white.opacity(0.85))
                    Spacer(minLength: 8)
                    Button("Open") { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.Colors.accent)
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 20).fill(DS.Colors.warning.opacity(0.1)))
            }
        }
        .task {
            enabled = model?.dependencies.preferences.notificationsEnabled ?? true
            system = await model?.dependencies.notifications.authorizationStatus()
        }
        .onChange(of: enabled) { _, value in
            model?.dependencies.preferences.notificationsEnabled = value
            guard value, system == .notDetermined, let notifications = model?.dependencies.notifications else { return }
            Task {
                _ = try? await notifications.requestAuthorization()
                system = await notifications.authorizationStatus()
            }
        }
    }
}

// MARK: - Account

private struct AccountSettingsView: View {
    @Environment(\.appModel) private var model
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var error: String?
    @State private var editingName = false
    @State private var draftName = ""

    private var profile: UserProfile? { model?.auth.state.profile }

    var body: some View {
        SubscreenScaffold(title: "Account") {
            VStack(spacing: 6) {
                Text(initials)
                    .font(DS.Text.avatar).foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(DS.Gradients.accentButton))
                    .padding(.bottom, 6)
                Text(profile?.displayName ?? "Driver").font(DS.Text.identityName).foregroundStyle(.white)
                if profile?.hasPrivateRelayEmail == true {
                    Text("Private email via Apple").font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                } else if let email = profile?.email {
                    Text(email).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                }
                Label("Signed in with Apple", systemImage: "apple.logo")
                    .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .dsSurface()

            SettingsGroup(title: nil) {
                Button {
                    draftName = profile?.displayName ?? ""
                    editingName = true
                } label: {
                    SettingsLine(symbol: "pencil", title: "Display name", subtitle: "Shown in greetings and your profile", isFirst: true) {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("accountEditName")
                Button { confirmingSignOut = true } label: {
                    SettingsLine(symbol: "rectangle.portrait.and.arrow.right", title: "Sign out") { EmptyView() }
                }
                .buttonStyle(.plain)
                Button { confirmingDelete = true } label: {
                    SettingsLine(symbol: "trash", title: "Delete account", subtitle: "Erases all your data, including iCloud") { EmptyView() }
                        .foregroundStyle(DS.Colors.danger)
                }
                .buttonStyle(.plain)
            }
            if let error { Text(error).font(DS.Text.caption).foregroundStyle(DS.Colors.danger) }
            Footnote(text: "Your records sync through your own iCloud account. Signing out keeps them in iCloud.")
            LegalLinks()
        }
        .alert("Display name", isPresented: $editingName) {
            TextField("Your name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = draftName
                Task {
                    do { try await model?.auth.updateDisplayName(name) } catch { self.error = UserMessage.text(for: error) }
                }
            }
        } message: {
            Text("Only used to show your name in the app.")
        }
        .confirmDialog(isPresented: $confirmingSignOut, symbol: "rectangle.portrait.and.arrow.right", title: "Sign out?",
                       message: "You'll need Sign in with Apple to come back in.", confirmTitle: "Sign out") {
            Task { do { try await model?.auth.signOut() } catch { self.error = UserMessage.text(for: error) } }
        }
        .confirmDialog(isPresented: $confirmingDelete, symbol: "trash", title: "Delete account?",
                       message: "Every car, record, document and AI chat is erased — here, in iCloud and on your other devices. This can't be undone.", confirmTitle: "Delete") {
            Task {
                guard let model else { return }
                let d = model.dependencies
                do {
                    try await model.auth.deleteAccount(DeleteAccount(
                        auth: d.auth, vehicles: d.vehicles, documents: d.documents, conversations: d.conversations,
                        inbox: d.inbox, scans: d.scans, files: d.files, notifications: d.notifications, preferences: d.preferences
                    ))
                    await model.vehicles.refresh()
                } catch {
                    self.error = UserMessage.text(for: error)
                }
            }
        }
    }

    private var initials: String {
        let parts = (profile?.displayName ?? "").split(separator: " ").prefix(2)
        let letters = parts.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "" : letters.uppercased()
    }
}

// MARK: - Subscription (Figma 49)

struct SubscriptionSettingsView: View {
    @Environment(\.appModel) private var model
    @State private var message: String?

    var body: some View {
        SubscreenScaffold(title: "Subscription") {
            statusCard
            SettingsGroup(title: nil) {
                Button { Task { await model?.entitlements.openManageSubscriptions() } } label: {
                    SettingsLine(symbol: "creditcard", title: "Manage in App Store", subtitle: "Change or cancel the plan", isFirst: true) {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subscriptionManage")
                Button(action: restore) {
                    SettingsLine(symbol: "arrow.down.circle", title: "Restore purchases", subtitle: "Signed in with Apple") {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                Button { model?.router.present(.paywall(.settingsUpgrade)) } label: {
                    SettingsLine(symbol: "info.circle", title: "What Premium includes", subtitle: "Scans, unlimited AI, more vehicles") {
                        SettingsRowChevron()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("subscriptionUpgrade")
            }
            if let message { Footnote(text: message) }
            Footnote(text: "Billing is handled by Apple. We never see your card details.")
            LegalLinks()
        }
    }

    private var statusCard: some View {
        let entitlement = model?.entitlements.entitlement ?? .free
        let premium = model?.entitlements.isPremium ?? false
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "crown").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Circle().fill(Color.white.opacity(0.18)))
                Spacer()
                Text(premium ? "ACTIVE" : "FREE").font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.white)
                    .padding(.horizontal, 10).frame(height: 22).background(Capsule().fill(Color.white.opacity(0.2)))
            }
            .padding(.bottom, 12)
            Text(premium ? "Premium" : "Free plan").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            Text(detail(entitlement, premium: premium)).font(DS.Text.subheadlineRegular).foregroundStyle(.white.opacity(0.8))
            if !premium {
                Button { model?.router.present(.paywall(.settingsUpgrade)) } label: {
                    Text("Go Premium").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x0A121F))
                        .padding(.horizontal, 24).frame(height: 38).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(premium ? AnyShapeStyle(DS.Gradients.aiCard) : AnyShapeStyle(DS.Gradients.vehicleCard)))
    }

    private func detail(_ entitlement: Entitlement, premium: Bool) -> String {
        guard premium else { return "One vehicle, \(FeatureGating.freeDailyAIRequests) AI questions a day." }
        guard let expires = entitlement.expiresAt else { return "Active" }
        let date = expires.formatted(date: .abbreviated, time: .omitted)
        return entitlement.willAutoRenew ? "Renews \(date)" : "Ends \(date)"
    }

    private func restore() {
        Task {
            do {
                switch try await model?.entitlements.restore() {
                case .restored: message = "Purchases restored."
                default: message = "Nothing to restore for this Apple ID."
                }
            } catch {
                message = UserMessage.text(for: error)
            }
        }
    }
}

// MARK: - Vehicles

struct ManageVehiclesView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        SubscreenScaffold(title: "Vehicles") {
            SettingsGroup(title: nil) {
                ForEach(Array((model?.vehicles.summaries ?? []).enumerated()), id: \.element.id) { index, summary in
                    Button { model?.router.push(.vehicleDetail(summary.id), in: .profile) } label: {
                        SettingsLine(symbol: "car", title: summary.displayName,
                                     subtitle: summary.isDefault ? "Default" : nil, isFirst: index == 0) { SettingsRowChevron() }
                    }
                    .buttonStyle(.plain)
                }
            }
            SaveButton(title: "Add vehicle", symbol: "plus") { model?.router.present(.vehicleEditor(.create)) }
        }
    }
}

struct DefaultVehicleView: View {
    @Environment(\.appModel) private var model

    var body: some View {
        SubscreenScaffold(title: "Default vehicle") {
            SettingsGroup(title: nil) {
                ForEach(Array((model?.vehicles.summaries ?? []).enumerated()), id: \.element.id) { index, summary in
                    Button { Task { await model?.vehicles.select(summary.id) } } label: {
                        SettingsLine(symbol: "car", title: summary.displayName, isFirst: index == 0) {
                            if summary.isDefault { Image(systemName: "checkmark").foregroundStyle(DS.Colors.accent) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Support, legal, about

struct SupportSettingsView: View {
    var body: some View { LegalSettingsView(title: "Support") }
}

struct LegalSettingsView: View {
    var title = "Legal"
    @Environment(\.appModel) private var model

    var body: some View {
        SubscreenScaffold(title: title) {
            SettingsGroup(title: nil) {
                Button { model?.router.present(.legal(.privacyPolicy)) } label: {
                    SettingsLine(symbol: "hand.raised", title: "Privacy Policy", isFirst: true) { SettingsRowChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("legalPrivacy")
                Button { model?.router.present(.legal(.termsOfUse)) } label: {
                    SettingsLine(symbol: "doc.text", title: "Terms of Use") { SettingsRowChevron() }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("legalTerms")
            }
            Footnote(text: "Version \(Bundle.main.appVersionString)")
        }
    }
}

struct AboutView: View {
    var body: some View { LegalSettingsView(title: "About") }
}

// MARK: - Currency

/// Name, symbol and code for one currency, in the user's language.
struct CurrencyInfo: Identifiable, Hashable {
    let code: CurrencyCode
    var id: String { code.iso4217 }

    init(_ code: CurrencyCode) { self.code = code }

    var name: String {
        Locale.current.localizedString(forCurrencyCode: code.iso4217)?.capitalizedFirst ?? code.iso4217
    }

    /// "€", "zł", "₴", "$" — the symbol people in that currency's own country write, else the code.
    var symbol: String { Self.symbols[code.iso4217] ?? code.iso4217 }

    /// Built once: for each currency, the shortest symbol any locale using it prints.
    private static let symbols: [String: String] = {
        var best: [String: String] = [:]
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            guard let code = locale.currency?.identifier else { continue }
            formatter.locale = locale
            guard let symbol = formatter.currencySymbol, !symbol.isEmpty, symbol != code,
                  symbol.count <= 3, !symbol.contains(where: \.isLetter) || symbol.count <= 2 || symbol == "zł"
            else { continue }
            if let current = best[code], current.count <= symbol.count { continue }
            best[code] = symbol
        }
        return best
    }()

    /// The currencies people here most likely use, first.
    static let popular: [CurrencyCode] = ["EUR", "USD", "GBP", "PLN", "UAH", "CHF", "SEK", "NOK", "DKK", "CZK"].map(CurrencyCode.init)

    static let all: [CurrencyInfo] = Locale.commonISOCurrencyCodes
        .map { CurrencyInfo(CurrencyCode($0)) }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// The currency symbol in a soft accent disc.
struct CurrencyBadge: View {
    let info: CurrencyInfo
    var size: CGFloat = 40
    var selected = false

    var body: some View {
        Text(info.symbol)
            .font(.system(size: size * (info.symbol.count > 1 ? 0.34 : 0.46), weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            .foregroundStyle(selected ? .white : DS.Colors.accent)
            .frame(width: size, height: size)
            .background(Circle().fill(selected ? AnyShapeStyle(DS.Gradients.accentButton) : AnyShapeStyle(DS.Colors.accent.opacity(0.15))))
    }
}

/// Choose the currency new vehicles keep their money in.
struct CurrencyPickerView: View {
    @Environment(\.appModel) private var model
    @State private var selected = CurrencyCode.eur
    @State private var query = ""
    /// The currency waiting for the user to confirm the warning.
    @State private var pending: CurrencyCode?

    private var popular: [CurrencyInfo] { CurrencyInfo.popular.map(CurrencyInfo.init) }

    private var results: [CurrencyInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return CurrencyInfo.all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.code.iso4217.localizedCaseInsensitiveContains(q) || $0.symbol == q
        }
    }

    var body: some View {
        SubscreenScaffold(title: "Currency") {
            hero
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundStyle(DS.Colors.textSecondary)
                TextField("", text: $query, prompt: Text("Search currencies").foregroundStyle(DS.Colors.textSecondary))
                    .font(DS.Text.subheadlineRegular).foregroundStyle(.white).tint(DS.Colors.accent)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(height: 44)
            .dsGlass(radius: 22)

            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                list("Popular", popular)
                list("All currencies", CurrencyInfo.all.filter { !CurrencyInfo.popular.contains($0.code) })
            } else if results.isEmpty {
                Text("No currency matches “\(query)”.").font(DS.Text.subheadlineRegular).foregroundStyle(DS.Colors.textSecondary)
            } else {
                list(nil, results)
            }
            Footnote(text: "Used for cars you add from now on. A car keeps the currency it was created with, so its history never gets converted at a made-up rate.")
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { selected = model?.dependencies.preferences.defaultCurrency ?? .eur }
        .confirmDialog(
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            symbol: "arrow.left.arrow.right.circle",
            title: "Switch to \(pending.map { CurrencyInfo($0).name } ?? "")?",
            message: pending.map(warning) ?? "",
            confirmTitle: "Use \(pending?.iso4217 ?? "")",
            tone: .accent
        ) {
            if let pending { apply(pending) }
        }
    }

    private var hero: some View {
        let info = CurrencyInfo(selected)
        return HStack(spacing: 16) {
            CurrencyBadge(info: info, size: 56, selected: true)
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Selected")
                Text(info.name).font(DS.Text.section).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.8)
                Text(sample(info)).font(DS.Text.caption).foregroundStyle(DS.Colors.onCardSecondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).fill(DS.Gradients.vehicleCard))
        .overlay(RoundedRectangle(cornerRadius: DS.Layout.surfaceRadius).strokeBorder(DS.Colors.hairline))
    }

    /// "1 284,50 € · EUR" — how amounts will look.
    private func sample(_ info: CurrencyInfo) -> String {
        DisplayFormat().money(Decimal(string: "1284.50")!, info.code, fractionDigits: 2) + " · " + info.code.iso4217
    }

    @ViewBuilder
    private func list(_ title: String?, _ items: [CurrencyInfo]) -> some View {
        VStack(spacing: 8) {
            if let title { Eyebrow(text: title) }
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, info in
                    Button { choose(info.code) } label: {
                        HStack(spacing: 12) {
                            CurrencyBadge(info: info, size: 36)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(info.name).font(DS.Text.rowTitle).foregroundStyle(DS.Colors.textPrimary).lineLimit(1)
                                Text(info.code.iso4217).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                            }
                            Spacer(minLength: 8)
                            if info.code == selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 20)).foregroundStyle(DS.Colors.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 60)
                        .overlay(alignment: .top) { if index > 0 { SettingsRowSeparator() } }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(info.code == selected ? .isSelected : [])
                    .accessibilityLabel("\(info.name), \(info.code.iso4217)")
                }
            }
            .dsSurface()
        }
    }

    /// Cars already in the garage. Each keeps the currency it was created with.
    private var existingCars: [VehicleSummary] {
        model?.vehicles.summaries ?? []
    }

    /// Asks first when there are cars whose history is in another currency — the change does not
    /// touch them, and that is exactly what people expect it to do.
    private func choose(_ code: CurrencyCode) {
        guard code != selected else { return }
        if existingCars.isEmpty { apply(code) } else { pending = code }
    }

    private func apply(_ code: CurrencyCode) {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.snappy) { selected = code }
        model?.dependencies.preferences.defaultCurrency = code
    }

    /// Plain words on what happens and what does not.
    private func warning(for code: CurrencyCode) -> String {
        let new = CurrencyInfo(code)
        let names = existingCars.map(\.displayName)
        let cars = names.count <= 2 ? names.joined(separator: " and ") : "your \(names.count) cars"
        return """
        Only cars you add from now on will use \(new.name). \(cars.prefix(1).uppercased() + cars.dropFirst()) keep \(names.count == 1 ? "its" : "their") current currency, so \(names.count == 1 ? "its" : "their") history and statistics stay exactly as they are.

        Amounts are never converted: a car's totals only count records in that car's currency.
        """
    }
}

/// "Terms of Use · Privacy Policy" — the two links every account and purchase screen carries.
struct LegalLinks: View {
    @Environment(\.appModel) private var model

    var body: some View {
        HStack(spacing: 6) {
            Button("Terms of Use") { model?.router.present(.legal(.termsOfUse)) }
                .accessibilityIdentifier("legalLinkTerms")
            Text("·").foregroundStyle(DS.Colors.textSecondary)
            Button("Privacy Policy") { model?.router.present(.legal(.privacyPolicy)) }
                .accessibilityIdentifier("legalLinkPrivacy")
        }
        .font(DS.Text.caption.weight(.semibold))
        .foregroundStyle(DS.Colors.accent)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
