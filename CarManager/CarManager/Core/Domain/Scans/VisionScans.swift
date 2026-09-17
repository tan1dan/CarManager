import Foundation

public enum DisclaimerKind: String, Codable, Sendable {
    case notProfessionalDiagnostics
    case costEstimateOnly
}

/// Non-optional on every AI vision result — a result without a disclaimer is unrepresentable.
public struct AIDisclaimer: Hashable, Codable, Sendable {
    public let kind: DisclaimerKind
    public let textKey: String
    public let version: Int

    public init(kind: DisclaimerKind, textKey: String, version: Int = 1) {
        self.kind = kind; self.textKey = textKey; self.version = version
    }

    public static let dashboard = AIDisclaimer(
        kind: .notProfessionalDiagnostics, textKey: "disclaimer.dashboard"
    )
    public static let damage = AIDisclaimer(
        kind: .costEstimateOnly, textKey: "disclaimer.damage"
    )
}

public enum FindingSeverity: String, Codable, Sendable {
    case informational, soon, urgent, stopDriving
}

/// `.unknown` exists so the failure mode on unparseable output is "we don't know",
/// never "safe to drive".
public enum DrivingSafetyAssessment: String, Codable, Sendable {
    case likelySafe, cautionAdvised, doNotDrive, unknown
}

public struct DashboardFinding: Hashable, Sendable {
    public var warningName: String
    public var likelyCauses: [String]
    public var severity: FindingSeverity
    public var recommendedAction: String
    public var drivingSafety: DrivingSafetyAssessment
    public var confidence: Double

    public init(
        warningName: String, likelyCauses: [String] = [], severity: FindingSeverity = .informational,
        recommendedAction: String = "", drivingSafety: DrivingSafetyAssessment = .unknown,
        confidence: Double = 0
    ) {
        self.warningName = warningName; self.likelyCauses = likelyCauses; self.severity = severity
        self.recommendedAction = recommendedAction; self.drivingSafety = drivingSafety
        self.confidence = confidence
    }
}

public struct DashboardScan: Identifiable, Hashable, Sendable {
    public let id: DashboardScanID
    public let vehicleID: VehicleID?
    public let imageRef: FileRef
    public var findings: [DashboardFinding]
    public let disclaimer: AIDisclaimer
    public let createdAt: Date

    public init(
        id: DashboardScanID = DashboardScanID(), vehicleID: VehicleID?, imageRef: FileRef,
        findings: [DashboardFinding], disclaimer: AIDisclaimer = .dashboard, createdAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.imageRef = imageRef
        self.findings = findings; self.disclaimer = disclaimer; self.createdAt = createdAt
    }
}

public enum DamageSeverity: String, Codable, Sendable {
    case cosmetic, moderate, structural, unknown
}

public enum EstimateBasis: String, Codable, Sendable {
    case aiEstimate, regionalAverage
}

/// A RANGE. There is deliberately no `estimatedCost: Money` anywhere in the model, so a
/// guaranteed price cannot be expressed.
public struct CostEstimateRange: Hashable, Sendable {
    public let low: Money
    public let high: Money
    public let basis: EstimateBasis
    public let confidence: Double

    public init(low: Money, high: Money, basis: EstimateBasis = .aiEstimate, confidence: Double = 0) {
        self.low = low; self.high = high; self.basis = basis; self.confidence = confidence
    }
}

public struct DamageFinding: Hashable, Sendable {
    public var damageType: String
    public var severity: DamageSeverity
    public var suggestedRepair: String
    public var cosmeticRepairPossible: Bool?
    public var estimatedCost: CostEstimateRange?

    public init(
        damageType: String, severity: DamageSeverity = .unknown, suggestedRepair: String = "",
        cosmeticRepairPossible: Bool? = nil, estimatedCost: CostEstimateRange? = nil
    ) {
        self.damageType = damageType; self.severity = severity
        self.suggestedRepair = suggestedRepair
        self.cosmeticRepairPossible = cosmeticRepairPossible; self.estimatedCost = estimatedCost
    }
}

public struct DamageAnalysis: Identifiable, Hashable, Sendable {
    public let id: DamageAnalysisID
    public let vehicleID: VehicleID
    public let imageRefs: [FileRef]
    public var findings: [DamageFinding]
    public let disclaimer: AIDisclaimer
    public let createdAt: Date

    public init(
        id: DamageAnalysisID = DamageAnalysisID(), vehicleID: VehicleID, imageRefs: [FileRef],
        findings: [DamageFinding], disclaimer: AIDisclaimer = .damage, createdAt: Date
    ) {
        self.id = id; self.vehicleID = vehicleID; self.imageRefs = imageRefs
        self.findings = findings; self.disclaimer = disclaimer; self.createdAt = createdAt
    }
}

/// Shared capture → processing → result shape for the two vision flows.
public enum VisionScanState<Result: Sendable & Hashable>: Hashable, Sendable {
    case capturing
    case processing
    case result(Result)
    case failed(message: String, retryable: Bool)
}
