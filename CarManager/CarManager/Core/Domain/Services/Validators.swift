import Foundation

public enum VehicleValidator {
    /// VIN is optional. Blank or whitespace-only input is treated as "not entered" and a
    /// malformed VIN is reported as a warning, so neither can block saving a vehicle.
    public static func normalizedVIN(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else { return nil }
        return trimmed.uppercased()
    }

    @discardableResult
    public static func validate(_ draft: VehicleDraft, now: Date, calendar: Calendar) throws -> [DomainWarning] {
        if draft.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DomainError.validation(.emptyField(.brand))
        }
        if draft.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DomainError.validation(.emptyField(.model))
        }
        if let year = draft.year {
            let currentYear = calendar.component(.year, from: now)
            guard (1885...(currentYear + 2)).contains(year) else {
                throw DomainError.validation(.emptyField(.year))
            }
        }
        if draft.initialOdometer.kilometers < 0 {
            throw DomainError.validation(.negativeAmount(.odometer))
        }

        var warnings: [DomainWarning] = []
        if let vin = normalizedVIN(draft.vin), vin.count != 17 {
            warnings.append(.malformedVIN(length: vin.count))
        }
        return warnings
    }
}

public enum FuelEntryValidator {
    /// Deviation between volume × price and the printed total is a WARNING, not an error —
    /// receipts round, and refusing to save a fill-up over a cent would be absurd.
    public static let allowedDeviation = 0.02

    public static func validate(_ draft: FuelEntryDraft, now: Date) throws -> [DomainWarning] {
        guard draft.volume.liters > 0 else { throw DomainError.validation(.nonPositiveVolume) }
        guard draft.totalCost.amount >= 0 else {
            throw DomainError.validation(.negativeAmount(.totalCost))
        }
        guard draft.date <= now.addingTimeInterval(86_400) else {
            throw DomainError.validation(.futureDate(.date))
        }

        var warnings: [DomainWarning] = []
        if let price = draft.pricePerUnit {
            let computed = (price.amount as NSDecimalNumber).doubleValue * draft.volume.liters
            let stated = (draft.totalCost.amount as NSDecimalNumber).doubleValue
            if stated > 0 {
                let deviation = abs(computed - stated) / stated
                if deviation > allowedDeviation {
                    warnings.append(.priceTotalMismatch(deviationPercent: deviation * 100))
                }
            }
        }
        return warnings
    }
}

public enum ServiceRecordValidator {
    public static func validate(items: [ServiceItem], totalCost: Money) throws {
        guard !items.isEmpty else { throw DomainError.validation(.noServiceItems) }
        guard totalCost.amount >= 0 else { throw DomainError.validation(.negativeAmount(.cost)) }
    }
}

public enum AuthValidator {
    public static func validateSignIn(email: String, password: String) throws {
        guard email.contains("@"), email.count >= 5 else {
            throw DomainError.validation(.invalidEmail)
        }
        guard password.count >= 6 else { throw DomainError.validation(.weakPassword) }
    }

    public static func validateSignUp(_ registration: AuthRegistration) throws {
        guard !registration.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw DomainError.validation(.emptyField(.name))
        }
        try validateSignIn(email: registration.email, password: registration.password)
        guard registration.acceptedTerms else { throw DomainError.validation(.termsNotAccepted) }
    }
}

public enum DocumentExpiryEvaluator {
    public static func status(
        for document: DocumentMetadata, now: Date, calendar: Calendar, leadDays: Int = 30
    ) -> DocumentExpiryStatus {
        // A missing expiry date is `.noExpiry`, NEVER `.expired`.
        guard let expiration = document.expirationDate else { return .noExpiry }
        let days = calendar.dateComponents([.day], from: now, to: expiration).day ?? 0
        if days < 0 { return .expired(daysAgo: -days) }
        if days <= leadDays { return .expiringSoon(daysRemaining: days) }
        return .valid
    }
}
