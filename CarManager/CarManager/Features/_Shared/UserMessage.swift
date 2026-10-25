import Foundation

/// Plain-English text for errors and warnings shown inline on styled screens. The keys from
/// `ErrorPresenter` stay the contract for localisation; this is their English rendering.
enum UserMessage {
    static func text(for error: any Error) -> String {
        guard let error = error as? DomainError else { return "Something went wrong. Please try again." }
        switch error {
        case .validation(let v): return text(for: v)
        case .persistence: return "Couldn't save. Please try again."
        case .subscription(.vehicleLimitReached): return "Your plan includes one vehicle."
        case .subscription: return "This needs Premium."
        case .ai(.offline): return "You're offline. AI needs a connection."
        case .ai(.quotaExceeded): return "You've used today's free questions."
        case .ai(.timedOut): return "The assistant took too long to answer. Try again."
        case .ai(.rateLimited): return "Too many questions right now. Wait a minute and try again."
        case .ai(.unauthorized): return "The assistant isn't available for this app version. Please update the app."
        case .ai(.invalidRequest): return "The assistant couldn't accept that message. Try rephrasing it."
        case .ai(.serverError): return "The assistant is having trouble right now. Try again in a moment."
        case .ai(.structuredOutputInvalid): return "The assistant sent an answer the app couldn't read. Try again."
        case .ai(.notConfigured): return "The AI assistant isn't set up in this build."
        case .ai(.messageTooLong(let max)): return "That message is too long — keep it under \(max) characters."
        case .ai(.transport): return "Couldn't reach the assistant. Check your connection and try again."
        case .ai(.noTextRecognized): return "No text found. Try again with the whole receipt in frame and good light."
        case .ai(.providerUnavailable): return "AI photo analysis isn't connected yet. It arrives with the AI service."
        case .ai(.requiresPremium): return "This needs Premium."
        case .ai: return "The assistant couldn't answer. Please try again."
        case .document(.unsupportedType): return "That file type isn't supported."
        case .document(.fileTooLarge): return "That file is too large (50 MB max)."
        case .document: return "Couldn't read the file. Please try again."
        case .cancelled: return "Cancelled."
        default: return "Something went wrong. Please try again."
        }
    }

    static func text(for error: ValidationError) -> String {
        switch error {
        case .emptyField(let field): "Enter \(name(field))."
        case .negativeAmount(let field): "\(name(field).capitalized) can't be negative."
        case .nonPositiveVolume: "Enter how much fuel went in."
        case .futureDate: "That date is in the future."
        case .expirationBeforeStart: "The expiry date is before the start date."
        case .odometerRegression: "That mileage is lower than the last reading."
        case .invalidVIN: "That VIN doesn't look right."
        case .noServiceItems: "Choose at least one service item."
        case .nonPositiveInterval: "The interval must be more than zero."
        case .triggerMismatch: "The reminder type and its trigger don't match."
        case .vehicleNotFound: "This vehicle no longer exists."
        case .invalidEmail, .weakPassword, .termsNotAccepted: "Check the details and try again."
        }
    }

    static func text(for warning: DomainWarning) -> String {
        switch warning {
        case .odometerRegression: "Saved — the mileage is lower than an earlier reading, check it when you can."
        case .priceTotalMismatch: "Saved — litres × price doesn't match the total exactly."
        case .notificationsNotAuthorized: "Saved — turn on notifications in Settings to be reminded."
        case .itemCostsExceedTotal: "Saved — item costs add up to more than the total."
        case .malformedVIN: "Saved — the VIN isn't 17 characters."
        }
    }

    private static func name(_ field: FieldID) -> String {
        switch field {
        case .totalCost: "the total cost"
        case .pricePerUnit: "the price per litre"
        case .licensePlate: "the licence plate"
        case .serviceItems: "a service item"
        case .expirationDate: "an expiry date"
        case .startDate: "a start date"
        default: "the \(field.rawValue)"
        }
    }
}

/// Parses what people type into number fields: "48,5", "48.5", "1 284,50", "€84.20".
enum NumberInput {
    static func decimal(_ text: String) -> Decimal? {
        var cleaned = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        // The last separator is the decimal one; any earlier ones are grouping.
        if let last = cleaned.lastIndex(where: { $0 == "," || $0 == "." }) {
            let head = cleaned[..<last].filter(\.isNumber)
            let tail = cleaned[cleaned.index(after: last)...].filter(\.isNumber)
            cleaned = tail.count == 3 && !head.isEmpty && cleaned.filter({ $0 == "," || $0 == "." }).count > 1
                ? head + tail
                : head + "." + tail
        }
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func double(_ text: String) -> Double? { decimal(text).map { NSDecimalNumber(decimal: $0).doubleValue } }
}
