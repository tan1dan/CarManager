import Foundation

public struct DateRange: Hashable, Codable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    public func contains(_ date: Date) -> Bool { date >= start && date <= end }
}

public enum AnalyticsPeriod: Hashable, Codable, Sendable, CaseIterable {
    case week, month, sixMonths, year, allTime

    public static var allCases: [AnalyticsPeriod] { [.week, .month, .sixMonths, .year, .allTime] }

    public var titleKey: String {
        switch self {
        case .week: "period.week"
        case .month: "period.month"
        case .sixMonths: "period.sixMonths"
        case .year: "period.year"
        case .allTime: "period.allTime"
        }
    }

    /// Pure and calendar-aware — the injected calendar makes this testable.
    public func range(now: Date, calendar: Calendar) -> DateRange {
        switch self {
        case .week:
            DateRange(start: calendar.date(byAdding: .day, value: -7, to: now) ?? now, end: now)
        case .month:
            DateRange(start: calendar.date(byAdding: .month, value: -1, to: now) ?? now, end: now)
        case .sixMonths:
            DateRange(start: calendar.date(byAdding: .month, value: -6, to: now) ?? now, end: now)
        case .year:
            DateRange(start: calendar.date(byAdding: .year, value: -1, to: now) ?? now, end: now)
        case .allTime:
            DateRange(start: .distantPast, end: now)
        }
    }
}
