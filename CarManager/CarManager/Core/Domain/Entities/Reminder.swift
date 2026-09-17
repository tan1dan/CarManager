import Foundation

public enum ReminderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case oilChange, filterReplacement, tireChange, tirePressure, technicalInspection,
         insurance, battery, brakePads, timingBelt, vehicleTax, custom
    public var id: String { rawValue }

    /// Which service item types auto-complete this reminder.
    public var satisfyingServiceTypes: Set<ServiceType> {
        switch self {
        case .oilChange: [.oilChange]
        case .filterReplacement: [.filters]
        case .tireChange: [.tires]
        case .brakePads: [.brakes]
        case .battery: [.battery]
        case .timingBelt: [.engine]
        default: []
        }
    }
}

public struct DateTrigger: Hashable, Codable, Sendable {
    public var dueDate: Date
    public init(dueDate: Date) { self.dueDate = dueDate }
}

/// Carries a BASELINE as well as an interval — that is what makes the progress bar renderable.
public struct MileageTrigger: Hashable, Codable, Sendable {
    public var baselineOdometer: Odometer
    public var intervalDistance: Distance
    public init(baselineOdometer: Odometer, intervalDistance: Distance) {
        self.baselineOdometer = baselineOdometer
        self.intervalDistance = intervalDistance
    }
    public var dueOdometer: Odometer {
        Odometer(kilometers: baselineOdometer.kilometers + intervalDistance.kilometers)
    }
}

public enum ReminderTrigger: Hashable, Codable, Sendable {
    case date(DateTrigger)
    case mileage(MileageTrigger)
    case whicheverFirst(DateTrigger, MileageTrigger)
}

public enum RecurrenceRule: Hashable, Codable, Sendable {
    case none
    case everyMonths(Int)
    case everyYears(Int)
    case everyDistance(Distance)
    case both(months: Int, distance: Distance)
    /// "Tire swap · Apr / Nov" cannot be expressed as everyMonths(n).
    case seasonal(months: Set<Int>)
}

public struct ReminderLeadTime: Hashable, Codable, Sendable {
    public var days: Int?
    public var distance: Distance?
    public init(days: Int? = 14, distance: Distance? = Distance(kilometers: 1000)) {
        self.days = days; self.distance = distance
    }
}

public enum ReminderStatus: Hashable, Sendable {
    case upcoming(daysRemaining: Int?)
    case due
    case overdue(daysOverdue: Int?)
    /// No odometer reading yet — never report "overdue" for a mileage trigger we cannot evaluate.
    case indeterminate
}

public struct ReminderProgress: Hashable, Sendable {
    public let fraction: Double
    public let remainingDistance: Distance?
    public let remainingDays: Int?
    public init(fraction: Double, remainingDistance: Distance?, remainingDays: Int?) {
        self.fraction = min(max(fraction, 0), 1)
        self.remainingDistance = remainingDistance
        self.remainingDays = remainingDays
    }
}

public struct Reminder: Identifiable, Hashable, Sendable {
    public let id: ReminderID
    public let vehicleID: VehicleID
    public var title: String
    public var kind: ReminderKind
    public var trigger: ReminderTrigger
    public var recurrence: RecurrenceRule
    public var note: String?
    public var isActive: Bool
    public var lastCompletedAt: Date?
    public var lastCompletedOdometer: Odometer?
    public var leadTime: ReminderLeadTime
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ReminderID = ReminderID(), vehicleID: VehicleID, title: String, kind: ReminderKind,
        trigger: ReminderTrigger, recurrence: RecurrenceRule = .none, note: String? = nil,
        isActive: Bool = true, lastCompletedAt: Date? = nil, lastCompletedOdometer: Odometer? = nil,
        leadTime: ReminderLeadTime = ReminderLeadTime(), createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.title = title; self.kind = kind
        self.trigger = trigger; self.recurrence = recurrence; self.note = note
        self.isActive = isActive; self.lastCompletedAt = lastCompletedAt
        self.lastCompletedOdometer = lastCompletedOdometer; self.leadTime = leadTime
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct ReminderEvaluation: Identifiable, Hashable, Sendable {
    public var id: ReminderID { reminder.id }
    public let reminder: Reminder
    public let status: ReminderStatus
    public let progress: ReminderProgress?

    public init(reminder: Reminder, status: ReminderStatus, progress: ReminderProgress?) {
        self.reminder = reminder; self.status = status; self.progress = progress
    }
}
