import SwiftUI

// Building blocks shared by every styled screen. Each mirrors one recurring element of the
// Figma file, so a screen reads as a list of design parts rather than raw modifiers.

// MARK: - Headers

/// A pushed screen's header: round back button, 20 pt title, optional round action
/// (Figma: Fuel, Documents, Notifications …).
struct PushedHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            CircleBackButton(action: onBack)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DS.Layout.gutter)
        .padding(.top, 16)
    }
}

extension PushedHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, onBack: @escaping () -> Void) {
        self.init(title: title, subtitle: subtitle, onBack: onBack) { EmptyView() }
    }
}

/// The round 40 pt glass button used for "+", share and similar header actions.
struct CircleIconButton: View {
    let symbol: String
    var filled = false
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background {
                    if filled { Circle().fill(DS.Gradients.accentButton) }
                    else { Circle().fill(Color.white.opacity(0.051)) }
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A tab-level screen title: optional eyebrow, 30 pt bold, optional trailing control.
struct LargeTitleHeader<Trailing: View>: View {
    var eyebrow: String?
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(DS.Text.subheadline)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                Text(title)
                    .font(DS.Text.title)
                    .tracking(DS.Text.titleTracking)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, DS.Layout.headerGutter)
        .padding(.top, 16)
    }
}

/// Cancel · Title · Save — the top row of every editor sheet (Figma "Add Fuel").
struct EditorTopBar: View {
    let title: String
    var leading = String(localized: "Cancel")
    var trailing = String(localized: "Save")
    var trailingEnabled = true
    let onLeading: () -> Void
    let onTrailing: () -> Void

    var body: some View {
        ZStack {
            Text(title)
                .font(DS.Text.rowTitle)
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(leading, action: onLeading)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Colors.onCardSecondary)
                    .accessibilityIdentifier("editorCancel")
                Spacer()
                Button(trailing, action: onTrailing)
                    .font(DS.Text.rowTitle)
                    .foregroundStyle(trailingEnabled ? DS.Colors.accent : DS.Colors.textSecondary)
                    .disabled(!trailingEnabled)
                    .accessibilityIdentifier("editorSave")
            }
        }
        .tracking(DS.Text.defaultTracking)
        .padding(.horizontal, DS.Layout.gutter)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Captions, chips, banners

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(DS.Text.eyebrowSmall)
            .tracking(DS.Text.eyebrowSmallTracking)
            .foregroundStyle(Color.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum Tone: Sendable {
    case accent, success, warning, danger, neutral

    var color: Color {
        switch self {
        case .accent: DS.Colors.accent
        case .success: DS.Colors.success
        case .warning: DS.Colors.warning
        case .danger: DS.Colors.danger
        case .neutral: DS.Colors.textSecondary
        }
    }
}

struct Chip: View {
    let text: String
    var tone: Tone = .neutral
    var body: some View {
        Text(text)
            .font(DS.Text.chip)
            .foregroundStyle(tone == .neutral ? Color.white.opacity(0.8) : tone.color)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(tone == .neutral ? Color.white.opacity(0.09) : tone.color.opacity(0.16)))
    }
}

/// A tinted note with an icon: AI warnings, reminder explanations, disclaimers.
struct InfoBanner: View {
    let symbol: String
    let text: String
    var tone: Tone = .accent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 20)
            Text(text)
                .font(DS.Text.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tone == .neutral ? Color.white.opacity(0.031) : tone.color.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(tone == .neutral ? Color.white.opacity(0.051) : tone.color.opacity(0.25)))
        )
    }
}

/// Soft disc, title, explanation and one action (Figma "Empty states").
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(width: 88, height: 88)
                .background(Circle().fill(Color.white.opacity(0.04)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.06)))
                .padding(.bottom, 24)
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                AccentCapsuleButton(title: actionTitle, action: action)
                    .padding(.top, 24)
            }
        }
        .frame(maxWidth: 300)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// Two- or three-way pill switch (Figma "6 months · Year · All time", "By date · By mileage").
struct SegmentedPill<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(.snappy) { selection = value } } label: {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(selection == value ? 1 : 0.5))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background {
                            if selection == value { Capsule().fill(DS.Gradients.accentButton) }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.039)).overlay(Capsule().strokeBorder(DS.Colors.hairline)))
    }
}

// MARK: - Forms

/// The rounded group of 54 pt label/value rows used by every editor.
struct FormSurface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .dsSurface()
    }
}

/// A row that opens a choice (shows a chevron).
struct FormChoiceRow: View {
    let label: String
    let value: String
    var placeholder = String(localized: "Select")
    var isFirst = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                FormLabel(text: label)
                Spacer(minLength: 12)
                Text(value.isEmpty ? placeholder : value)
                    .font(value.isEmpty ? DS.Text.subheadlineRegular : DS.Text.button)
                    .foregroundStyle(value.isEmpty ? DS.Colors.onCardTertiary : .white)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.onCardTertiary)
            }
            .formRowFrame(isFirst: isFirst)
        }
        .buttonStyle(.plain)
    }
}

/// A row with an inline text field.
struct FormTextRow: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var unit: String?
    var keyboard: UIKeyboardType = .default
    var isFirst = false

    var body: some View {
        HStack(spacing: 12) {
            FormLabel(text: label)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .font(DS.Text.button)
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .tint(DS.Colors.accent)
            if let unit {
                Text(unit).font(DS.Text.button).foregroundStyle(DS.Colors.onCardTertiary)
            }
        }
        .formRowFrame(isFirst: isFirst)
    }
}

struct FormToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var isFirst = false

    var body: some View {
        HStack {
            FormLabel(text: label)
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden().tint(DS.Colors.accent)
        }
        .formRowFrame(isFirst: isFirst)
    }
}

struct FormDateRow: View {
    let label: String
    @Binding var date: Date
    var range: ClosedRange<Date>? = nil
    var isFirst = false

    var body: some View {
        HStack {
            FormLabel(text: label)
            Spacer()
            Group {
                if let range {
                    DatePicker("", selection: $date, in: range, displayedComponents: .date)
                } else {
                    DatePicker("", selection: $date, displayedComponents: .date)
                }
            }
            .labelsHidden()
            .tint(DS.Colors.accent)
        }
        .formRowFrame(isFirst: isFirst)
    }
}

/// A choice row that opens a menu in place (Figma "Category ›", "Repeat ›").
struct FormMenuRow<Value: Hashable>: View {
    let label: String
    let options: [(Value, String)]
    @Binding var selection: Value
    var isFirst = false

    var body: some View {
        Menu {
            Picker(label, selection: $selection) {
                ForEach(options, id: \.0) { value, title in Text(title).tag(value) }
            }
        } label: {
            HStack(spacing: 8) {
                FormLabel(text: label)
                Spacer(minLength: 12)
                Text(options.first { $0.0 == selection }?.1 ?? "")
                    .font(DS.Text.button)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.Colors.onCardTertiary)
            }
            .formRowFrame(isFirst: isFirst)
        }
        .buttonStyle(.plain)
    }
}

/// A read-only label/value row (the vehicle an editor is bound to).
struct FormValueRow: View {
    let label: String
    let value: String
    var isFirst = false

    var body: some View {
        HStack(spacing: 8) {
            FormLabel(text: label)
            Spacer(minLength: 12)
            Text(value).font(DS.Text.button).foregroundStyle(.white).lineLimit(1)
        }
        .formRowFrame(isFirst: isFirst)
    }
}

/// A toggleable capsule (Figma "INCLUDE" chips on Add Service).
struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Color.white.opacity(0.6))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(isSelected ? AnyShapeStyle(DS.Colors.accent) : AnyShapeStyle(Color.white.opacity(0.06))))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Lays children out left to right and wraps onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            let gap = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += gap + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

private struct FormLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(DS.Text.subheadlineRegular)
            .foregroundStyle(DS.Colors.onCardTertiary)
            .fixedSize()
    }
}

private extension View {
    /// 54 pt row with the hairline above every row but the first.
    func formRowFrame(isFirst: Bool) -> some View {
        self
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .contentShape(.rect)
            .overlay(alignment: .top) {
                if !isFirst {
                    Rectangle().fill(Color.white.opacity(0.051)).frame(height: 1).padding(.horizontal, 16)
                }
            }
    }
}

/// The big amount at the top of an editor (Figma "TOTAL COST €84.20"). Editable in place.
struct HeroAmountField: View {
    let caption: String
    let currencySymbol: String
    @Binding var amount: String
    var meta: String?

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption.uppercased())
                .font(DS.Text.eyebrow)
                .tracking(DS.Text.eyebrowTracking)
                .foregroundStyle(Color.white.opacity(0.4))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(currencySymbol)
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(amount.isEmpty ? Color.white.opacity(0.3) : .white)
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 52, weight: .bold))
                    .tracking(-1.3)
                    .foregroundStyle(.white)
                    .tint(DS.Colors.accent)
                    .focused($focused)
                    .accessibilityLabel(caption)
            }
            .minimumScaleFactor(0.5)
            if let meta {
                Text(meta).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsSurface()
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }
}

// MARK: - List rows

/// The standard 72 pt list row: icon disc, title, subtitle, trailing value, optional chevron.
struct RecordRow: View {
    let symbol: String
    var iconStyle: RowIconStyle = .neutral
    let title: String
    var subtitle: String?
    var value: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(iconStyle.foreground)
                .frame(width: 44, height: 44)
                .background(Circle().fill(iconStyle.background))
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(DS.Text.rowTitle)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Text.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            if showsChevron { SettingsRowChevron() }
        }
        .tracking(DS.Text.defaultTracking)
        .padding(14)
        .contentShape(.rect)
    }
}

/// A surface holding rows separated by hairlines.
struct RowGroup<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item)
                if index < items.count - 1 { SettingsRowSeparator() }
            }
        }
        .dsSurface()
    }
}

// MARK: - Screen chrome

extension View {
    /// Dark background, hidden system bar — the frame every styled screen uses.
    func dsScreen() -> some View {
        self
            .background(DS.Colors.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            // Room for the floating tab bar under the last row of any scrolling screen.
            .contentMargins(.bottom, DS.Layout.tabBarReservedHeight, for: .scrollContent)
    }
}

// MARK: - Destructive confirmation (Figma 40 · Vehicle · Delete confirm)

struct ConfirmDialog: ViewModifier {
    @Binding var isPresented: Bool
    let symbol: String
    let title: String
    let message: String
    let confirmTitle: String
    /// `.danger` for destructive actions; `.accent` for an informed choice that loses nothing.
    var tone: Tone = .danger
    let onConfirm: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                ZStack {
                    Color(hex: 0x05080B).opacity(0.72)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented = false }
                        .transition(.opacity)
                    VStack(spacing: 0) {
                        Image(systemName: symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(tone.color)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(tone.color.opacity(0.149)))
                            .padding(.bottom, 14)
                        Text(title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.bottom, 8)
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 20)
                        Button {
                            isPresented = false
                            onConfirm()
                        } label: {
                            Text(confirmTitle)
                                .font(DS.Text.rowTitle)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Capsule().fill(tone == .danger ? AnyShapeStyle(DS.Colors.danger) : AnyShapeStyle(DS.Gradients.accentButton)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("confirmDestructive")
                        Button("Cancel") { isPresented = false }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .frame(minHeight: 44)
                    }
                    .padding(20)
                    .frame(width: 300)
                    .background(RoundedRectangle(cornerRadius: 28).fill(Color(hex: 0x1A2029)))
                    .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(DS.Colors.hairline))
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .accessibilityAddTraits(.isModal)
            }
        }
        .animation(.snappy(duration: 0.25), value: isPresented)
    }
}

extension View {
    func confirmDialog(
        isPresented: Binding<Bool>, symbol: String = "exclamationmark.shield", title: String,
        message: String, confirmTitle: String, tone: Tone = .danger, onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(ConfirmDialog(isPresented: isPresented, symbol: symbol, title: title,
                               message: message, confirmTitle: confirmTitle, tone: tone, onConfirm: onConfirm))
    }
}
