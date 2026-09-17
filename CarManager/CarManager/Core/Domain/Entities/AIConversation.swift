import Foundation

public enum AIMessageRole: String, Codable, Sendable {
    case user, assistant, systemNotice
}

public struct AIMessage: Identifiable, Hashable, Sendable {
    public let id: MessageID
    public let role: AIMessageRole
    public var text: String
    public var attachments: [FileRef]
    /// True when a stream was cancelled mid-flight. Partial answers are kept, never discarded.
    public var isPartial: Bool
    public var failureDescription: String?
    public let createdAt: Date

    public init(
        id: MessageID = MessageID(), role: AIMessageRole, text: String,
        attachments: [FileRef] = [], isPartial: Bool = false,
        failureDescription: String? = nil, createdAt: Date
    ) {
        self.id = id; self.role = role; self.text = text; self.attachments = attachments
        self.isPartial = isPartial; self.failureDescription = failureDescription
        self.createdAt = createdAt
    }
}

public struct AIConversation: Identifiable, Hashable, Sendable {
    public let id: ConversationID
    public var vehicleID: VehicleID?
    public var title: String
    public var messages: [AIMessage]
    public var contextVersion: Int
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ConversationID = ConversationID(), vehicleID: VehicleID? = nil, title: String,
        messages: [AIMessage] = [], contextVersion: Int = 1, createdAt: Date, updatedAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.title = title; self.messages = messages
        self.contextVersion = contextVersion; self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

public struct ConversationSummary: Identifiable, Hashable, Sendable {
    public let id: ConversationID
    public let title: String
    public let updatedAt: Date
    public let messageCount: Int

    public init(id: ConversationID, title: String, updatedAt: Date, messageCount: Int) {
        self.id = id; self.title = title; self.updatedAt = updatedAt; self.messageCount = messageCount
    }
}

public enum InsightSeverity: String, Codable, Sendable {
    case info, attention, warning
}

/// A metric the StatisticsEngine actually produced. Insights citing an unknown metric
/// are rejected before persistence — grounding is a filter, not a prompt instruction.
public enum MetricID: String, Codable, Sendable, CaseIterable {
    case averageConsumptionL100km, consumptionDeltaPercent, costPerKm,
         totalSpendPeriod, fuelSpendPeriod, maintenanceSpendPeriod, repairSpendPeriod,
         averageFuelPrice, monthOverMonthSpendDelta, distanceDrivenPeriod,
         daysUntilNextService, distanceUntilNextService, expiringDocumentCount
}

public struct MetricReference: Hashable, Codable, Sendable {
    public let metricID: MetricID
    public let value: Double
    public init(metricID: MetricID, value: Double) { self.metricID = metricID; self.value = value }
}

public struct AIInsight: Identifiable, Hashable, Sendable {
    public let id: InsightID
    public let vehicleID: VehicleID
    public var headline: String
    public var body: String
    public var severity: InsightSeverity
    public var supportingMetrics: [MetricReference]
    public var generatedAt: Date
    public var validUntil: Date
    public var dismissedAt: Date?

    public init(
        id: InsightID = InsightID(), vehicleID: VehicleID, headline: String, body: String,
        severity: InsightSeverity = .info, supportingMetrics: [MetricReference] = [],
        generatedAt: Date, validUntil: Date, dismissedAt: Date? = nil
    ) {
        self.id = id; self.vehicleID = vehicleID; self.headline = headline; self.body = body
        self.severity = severity; self.supportingMetrics = supportingMetrics
        self.generatedAt = generatedAt; self.validUntil = validUntil; self.dismissedAt = dismissedAt
    }
}
