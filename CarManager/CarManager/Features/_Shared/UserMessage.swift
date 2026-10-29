import Foundation

/// Plain-English text for errors and warnings shown inline on styled screens. The keys from
/// `ErrorPresenter` stay the contract for localisation; this is their English rendering.
enum UserMessage {
    static func text(for error: any Error) -> String {
        guard let error = error as? DomainError else { return String(localized: "Something went wrong. Please try again.") }
        switch error {
        case .validation(let v): return text(for: v)
        case .persistence: return String(localized: "Couldn't save. Please try again.")
        case .subscription(.vehicleLimitReached): return String(localized: "Your plan includes one vehicle.")
        case .subscription(.productsUnavailable): return String(localized: "Subscriptions couldn't be loaded. Check your connection and try again.")
        case .subscription(.unverifiedTransaction): return String(localized: "The App Store couldn't verify this purchase. Try Restore purchases.")
        case .subscription(.purchaseFailed): return String(localized: "The purchase didn't go through. You haven't been charged — please try again.")
        case .subscription(.restoreFailed): return String(localized: "Purchases couldn't be restored. Check your connection and try again.")
        case .subscription: return String(localized: "This needs Premium.")
        case .ai(.offline): return String(localized: "You're offline. AI needs a connection.")
        case .ai(.quotaExceeded): return String(localized: "You've used today's free questions.")
        case .ai(.timedOut): return String(localized: "The assistant took too long to answer. Try again.")
        case .ai(.rateLimited): return String(localized: "Too many questions right now. Wait a minute and try again.")
        case .ai(.unauthorized): return String(localized: "The assistant isn't available for this app version. Please update the app.")
        case .ai(.invalidRequest): return String(localized: "The assistant couldn't accept that message. Try rephrasing it.")
        case .ai(.serverError): return String(localized: "The assistant is having trouble right now. Try again in a moment.")
        case .ai(.structuredOutputInvalid): return String(localized: "The assistant sent an answer the app couldn't read. Try again.")
        case .ai(.notConfigured): return String(localized: "The AI assistant isn't set up in this build.")
        case .ai(.messageTooLong(let max)): return String(localized: "That message is too long — keep it under \(max) characters.")
        case .ai(.transport): return String(localized: "Couldn't reach the assistant. Check your connection and try again.")
        case .ai(.notAReceipt): return String(localized: "That doesn't look like a receipt. Try again with the whole receipt in frame.")
        case .ai(.noTextRecognized): return String(localized: "No text found. Try again with the whole receipt in frame and good light.")
        case .ai(.providerUnavailable): return String(localized: "AI photo analysis isn't connected yet. It arrives with the AI service.")
        case .ai(.requiresPremium): return String(localized: "This needs Premium.")
        case .ai: return String(localized: "The assistant couldn't answer. Please try again.")
        case .document(.unsupportedType): return String(localized: "That file type isn't supported.")
        case .document(.fileTooLarge): return String(localized: "That file is too large (50 MB max).")
        case .document: return String(localized: "Couldn't read the file. Please try again.")
        case .cancelled: return String(localized: "Cancelled.")
        default: return String(localized: "Something went wrong. Please try again.")
        }
    }

    static func text(for error: ValidationError) -> String {
        switch error {
        case .emptyField(let field): String(localized: "Enter \(name(field)).")
        case .negativeAmount(let field): String(localized: "\(name(field).capitalized) can't be negative.")
        case .nonPositiveVolume: String(localized: "Enter how much fuel went in.")
        case .futureDate: String(localized: "That date is in the future.")
        case .expirationBeforeStart: String(localized: "The expiry date is before the start date.")
        case .odometerRegression: String(localized: "That mileage is lower than the last reading.")
        case .invalidVIN: String(localized: "That VIN doesn't look right.")
        case .noServiceItems: String(localized: "Choose at least one service item.")
        case .nonPositiveInterval: String(localized: "The interval must be more than zero.")
        case .triggerMismatch: String(localized: "The reminder type and its trigger don't match.")
        case .vehicleNotFound: String(localized: "This vehicle no longer exists.")
        case .invalidEmail, .weakPassword, .termsNotAccepted: String(localized: "Check the details and try again.")
        }
    }

    static func text(for warning: DomainWarning) -> String {
        switch warning {
        case .odometerRegression: String(localized: "Saved — the mileage is lower than an earlier reading, check it when you can.")
        case .priceTotalMismatch: String(localized: "Saved — litres × price doesn't match the total exactly.")
        case .notificationsNotAuthorized: String(localized: "Saved — turn on notifications in Settings to be reminded.")
        case .itemCostsExceedTotal: String(localized: "Saved — item costs add up to more than the total.")
        case .malformedVIN: String(localized: "Saved — the VIN isn't 17 characters.")
        }
    }

    private static func name(_ field: FieldID) -> String {
        switch field {
        case .totalCost: String(localized: "the total cost")
        case .pricePerUnit: String(localized: "the price per litre")
        case .licensePlate: String(localized: "the licence plate")
        case .serviceItems: String(localized: "a service item")
        case .expirationDate: String(localized: "an expiry date")
        case .startDate: String(localized: "a start date")
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
