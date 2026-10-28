import SwiftUI
import Observation

/// One row of scan history, display-ready.
struct ScanHistoryRow: Equatable, Sendable, Identifiable {
    var id: UUID
    var symbol: String
    var tone: Tone
    var title: String
    var subtitle: String
    var route: AppRoute
    var item: ScanHistoryItem
}

struct ScanHistoryFormatter: Sendable {
    let format: DisplayFormat
    let now: Date

    func rows(_ items: [ScanHistoryItem]) -> [ScanHistoryRow] { items.map(row) }

    func row(_ item: ScanHistoryItem) -> ScanHistoryRow {
        let when = format.shortDate(item.createdAt, relativeTo: now)
        switch item {
        case .dashboard(let scan):
            let names = scan.findings.map(\.warningName)
            let title = names.isEmpty ? "No warning lights found"
                : names.count <= 2 ? names.joined(separator: ", ") : "\(names[0]) + \(names.count - 1) more"
            return ScanHistoryRow(
                id: item.id, symbol: "gauge.with.dots.needle.33percent", tone: Self.tone(scan.findings),
                title: title, subtitle: "Dashboard scan · \(when)", route: .dashboardScanResult(scan.id), item: item
            )
        case .damage(let analysis):
            let title = analysis.findings.first.map { first in
                analysis.findings.count > 1 ? "\(first.damageType) + \(analysis.findings.count - 1) more" : first.damageType
            } ?? "No damage found"
            return ScanHistoryRow(
                id: item.id, symbol: "car.side", tone: Self.tone(analysis.findings),
                title: title, subtitle: "Damage analysis · \(when)", route: .damageAnalysisResult(analysis.id), item: item
            )
        }
    }

    static func tone(_ findings: [DashboardFinding]) -> Tone {
        if findings.contains(where: { $0.severity == .urgent || $0.severity == .stopDriving }) { return .danger }
        if findings.contains(where: { $0.severity == .soon }) { return .warning }
        return findings.isEmpty ? .neutral : .success
    }

    static func tone(_ findings: [DamageFinding]) -> Tone {
        if findings.contains(where: { $0.severity == .structural }) { return .danger }
        if findings.contains(where: { $0.severity == .moderate || $0.severity == .unknown }) { return .warning }
        return findings.isEmpty ? .neutral : .success
    }
}

@MainActor
@Observable
final class ScanHistoryViewModel {
    private(set) var state: ViewState<[ScanHistoryRow]> = .idle

    private let list: ListScanHistory
    private let delete: DeleteScan
    private let formatter: ScanHistoryFormatter
    private let limit: Int?

    init(list: ListScanHistory, delete: DeleteScan, formatter: ScanHistoryFormatter, limit: Int? = nil) {
        self.list = list
        self.delete = delete
        self.formatter = formatter
        self.limit = limit
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            let rows = formatter.rows(try await list(limit: limit))
            state = rows.isEmpty ? .empty : .loaded(rows)
        } catch {
            state = .failed(ErrorPresenter.present(error))
        }
    }

    func remove(_ row: ScanHistoryRow) async {
        try? await delete(row.item)
        await load()
    }
}

extension ScanHistoryViewModel {
    static func make(_ model: AppModel, limit: Int? = nil) -> ScanHistoryViewModel {
        let d = model.dependencies
        return ScanHistoryViewModel(
            list: ListScanHistory(scans: d.scans),
            delete: DeleteScan(scans: d.scans, files: d.files),
            formatter: ScanHistoryFormatter(format: DisplayFormat(calendar: d.clock.calendar), now: d.clock.now),
            limit: limit
        )
    }
}

/// A scan row: tinted icon, what was found, kind and date.
struct ScanHistoryRowView: View {
    let row: ScanHistoryRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(row.tone == .neutral ? .white : row.tone.color)
                .frame(width: 44, height: 44)
                .background(Circle().fill(row.tone == .neutral ? Color.white.opacity(0.051) : row.tone.color.opacity(0.16)))
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title).font(DS.Text.rowTitle).foregroundStyle(DS.Colors.textPrimary).lineLimit(1)
                Text(row.subtitle).font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            SettingsRowChevron()
        }
        .padding(14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Every saved scan, newest first. Press and hold to delete.
struct ScanHistoryView: View {
    @Environment(\.appModel) private var model
    @State private var viewModel: ScanHistoryViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Layout.sectionSpacing) {
                PushedHeader(title: "Scans", onBack: { model?.router.pop() })
                content.padding(.horizontal, DS.Layout.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .dsScreen()
        .onAppear {
            guard let model else { return }
            if viewModel == nil { viewModel = .make(model) }
            Task { await viewModel?.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel?.state {
        case .loaded(let rows):
            RowGroup(items: rows) { row in
                Button { model?.router.push(row.route) } label: { ScanHistoryRowView(row: row) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Task { await viewModel?.remove(row) }
                        }
                    }
            }
            Text("Results sync through iCloud; the photos stay on this iPhone. Press and hold a scan to delete it.")
                .font(DS.Text.caption).foregroundStyle(DS.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .empty:
            EmptyStateView(symbol: "viewfinder", title: "No scans yet",
                           message: "Dashboard scans and damage analyses you make are kept here.")
        case .failed(let error):
            EmptyStateView(symbol: "exclamationmark.triangle", title: "Couldn't load scans",
                           message: UserMessage.text(for: DomainError.unexpected(description: error.messageKey)))
        default:
            ProgressView().tint(DS.Colors.textSecondary).padding(.top, 80)
        }
    }
}
