import Foundation

/// The single mapping point from domain errors to presentation state.
/// The Domain never knows a localisation string and never knows what an alert is.
public enum ErrorPresenter {
    public static func present(_ error: Error) -> ErrorPresentation {
        guard let domainError = error as? DomainError else {
            return ErrorPresentation(
                titleKey: "error.unexpected.title",
                messageKey: "error.unexpected.message",
                actions: [.dismiss, .contactSupport]
            )
        }
        return present(domainError)
    }

    public static func present(_ error: DomainError) -> ErrorPresentation {
        switch error {
        case .validation(let validation):
            return presentValidation(validation)

        case .persistence:
            return ErrorPresentation(
                titleKey: "error.persistence.title", messageKey: "error.persistence.message",
                style: .alert, actions: [.retry, .contactSupport]
            )

        case .authentication(let auth):
            return ErrorPresentation(
                titleKey: "error.auth.title", messageKey: "error.auth.\(String(describing: auth))",
                style: .inline, actions: [.retry]
            )

        case .subscription(let subscription):
            // A paywall is not an error surface — it routes, it does not alert.
            switch subscription {
            case .requiresPremium(let feature):
                return ErrorPresentation(
                    titleKey: "error.premium.title", messageKey: "error.premium.message",
                    style: .inline, actions: [.upgrade(.feature(feature))]
                )
            case .vehicleLimitReached:
                return ErrorPresentation(
                    titleKey: "error.vehicleLimit.title", messageKey: "error.vehicleLimit.message",
                    style: .inline, actions: [.upgrade(.vehicleLimit)]
                )
            default:
                return ErrorPresentation(
                    titleKey: "error.subscription.title", messageKey: "error.subscription.message",
                    style: .alert, actions: [.retry]
                )
            }

        case .ai(let aiError):
            return presentAI(aiError)

        case .document:
            return ErrorPresentation(
                titleKey: "error.document.title", messageKey: "error.document.message",
                style: .alert, actions: [.retry]
            )

        case .permission(let permission):
            return ErrorPresentation(
                titleKey: "error.permission.title",
                messageKey: "error.permission.\(String(describing: permission))",
                style: .alert, actions: [.openSettings, .dismiss]
            )

        case .cancelled:
            // User intent, not a failure. Swallowed.
            return ErrorPresentation(
                titleKey: "", messageKey: "", style: .toast, actions: []
            )

        case .unexpected:
            return ErrorPresentation(
                titleKey: "error.unexpected.title", messageKey: "error.unexpected.message",
                style: .alert, actions: [.dismiss, .contactSupport]
            )
        }
    }

    private static func presentValidation(_ error: ValidationError) -> ErrorPresentation {
        let field: FieldID? = switch error {
        case .emptyField(let f), .negativeAmount(let f), .futureDate(let f): f
        case .nonPositiveVolume: .volume
        case .invalidVIN: .vin
        case .invalidEmail: .email
        case .weakPassword: .password
        case .termsNotAccepted: .terms
        case .noServiceItems: .serviceItems
        case .nonPositiveInterval, .triggerMismatch: .interval
        case .expirationBeforeStart: .expirationDate
        case .odometerRegression: .odometer
        case .vehicleNotFound: nil
        }
        return ErrorPresentation(
            titleKey: "error.validation.title",
            messageKey: "error.validation.\(String(describing: error))",
            style: field.map { .fieldLevel($0) } ?? .inline,
            actions: []
        )
    }

    private static func presentAI(_ error: AIError) -> ErrorPresentation {
        switch error {
        case .quotaExceeded(let resetAt):
            ErrorPresentation(
                titleKey: "error.ai.quota.title", messageKey: "error.ai.quota.message",
                style: .inline, actions: [.upgrade(.aiQuota(resetAt: resetAt))]
            )
        case .requiresPremium(let feature):
            ErrorPresentation(
                titleKey: "error.premium.title", messageKey: "error.premium.message",
                style: .inline, actions: [.upgrade(.feature(feature))]
            )
        case .offline:
            ErrorPresentation(
                titleKey: "error.ai.offline.title", messageKey: "error.ai.offline.message",
                style: .inline, actions: [.retry]
            )
        case .cancelled:
            ErrorPresentation(titleKey: "", messageKey: "", style: .toast, actions: [])
        case .structuredOutputInvalid:
            ErrorPresentation(
                titleKey: "error.ai.parse.title", messageKey: "error.ai.parse.message",
                style: .inline, actions: [.retry, .dismiss]
            )
        default:
            ErrorPresentation(
                titleKey: "error.ai.title", messageKey: "error.ai.message",
                style: .inline, actions: [.retry]
            )
        }
    }
}
