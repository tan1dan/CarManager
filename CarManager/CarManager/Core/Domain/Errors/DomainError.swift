import Foundation

/// The umbrella error. Domain errors never reference SwiftUI; ErrorPresenter maps them
/// to presentation state in the Presentation layer.
///
/// NOTE: this stage uses plain `throws` rather than Swift 6 typed throws. Every throwing
/// API in the Domain/Application layers throws `DomainError` and nothing else, so tightening
/// to `throws(DomainError)` later is mechanical.
public enum DomainError: Error, Sendable, Equatable {
    case validation(ValidationError)
    case persistence(PersistenceError)
    case authentication(AuthenticationError)
    case subscription(SubscriptionError)
    case ai(AIError)
    case document(DocumentError)
    case permission(PermissionError)
    case cancelled
    case unexpected(description: String)
}

public enum FieldID: String, Sendable, Equatable {
    case brand, model, year, vin, licensePlate, odometer, volume, totalCost, pricePerUnit
    case title, cost, date, expirationDate, startDate, email, password, name, terms
    case serviceItems, interval, recurrence
}

public enum ValidationError: Error, Sendable, Equatable {
    case emptyField(FieldID)
    case negativeAmount(FieldID)
    case nonPositiveVolume
    case futureDate(FieldID)
    case expirationBeforeStart
    case odometerRegression(previous: Double, attempted: Double)
    case invalidVIN
    case invalidEmail
    case weakPassword
    case termsNotAccepted
    case noServiceItems
    case nonPositiveInterval
    case triggerMismatch
    case vehicleNotFound
}

public enum PersistenceError: Error, Sendable, Equatable {
    case notFound
    case writeFailed(String)
    case readFailed(String)
}

public enum AuthenticationError: Error, Sendable, Equatable {
    case invalidCredentials
    case emailAlreadyInUse
    case sessionExpired
    case providerFailed(String)
    case requiresReauthentication
    case networkUnavailable
}

public enum SubscriptionError: Error, Sendable, Equatable {
    case requiresPremium(PremiumFeature)
    case vehicleLimitReached
    case unverifiedTransaction
    case productsUnavailable
    case purchaseFailed(String)
}

public enum AIError: Error, Sendable, Equatable {
    case offline
    case quotaExceeded(resetAt: Date)
    case requiresPremium(PremiumFeature)
    case providerUnavailable
    case rateLimited
    case structuredOutputInvalid
    case contentFiltered
    case noTextRecognized
    case requiresDisclaimerAcknowledgement(DisclaimerKind)
    case cancelled
    case transport(String)
}

public enum DocumentError: Error, Sendable, Equatable {
    case unsupportedType
    case fileTooLarge(maxBytes: Int64)
    case fileWriteFailed
    case fileNotFound
    case exportFailed
}

public enum PermissionError: Error, Sendable, Equatable {
    case cameraDenied
    case photoLibraryDenied
    case notificationsDenied
    case iCloudUnavailable
}

/// Warnings are returned in a use case's OUTPUT, never thrown. A thrown error means
/// "the operation did not happen"; anything else is a warning.
public enum DomainWarning: Sendable, Equatable, Hashable {
    case odometerRegression(previous: Double, attempted: Double)
    case priceTotalMismatch(deviationPercent: Double)
    case notificationsNotAuthorized
    case itemCostsExceedTotal
    /// VIN is optional; when one is supplied but is not a 17-character ISO 3779 code we save
    /// the vehicle anyway and tell the user, rather than refusing the whole operation.
    case malformedVIN(length: Int)
}
