import Foundation

/// The single place numbers, money and dates are turned into text. Formatters and views
/// call these instead of building their own `NumberFormatter`s.
struct DisplayFormat: Sendable {
    let locale: Locale
    let calendar: Calendar
    let unitSystem: UnitSystem

    init(locale: Locale = .current, calendar: Calendar = .current, unitSystem: UnitSystem = .metric) {
        self.locale = locale
        self.calendar = calendar
        self.unitSystem = unitSystem
    }

    // MARK: Money

    func money(_ amount: Decimal, _ currency: CurrencyCode, fractionDigits: Int? = nil) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.iso4217
        let whole = amount == amount.rounded(scale: 0)
        let digits = fractionDigits ?? (whole ? 0 : 2)
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(currency.iso4217) \(amount)"
    }

    func money(_ value: Money, fractionDigits: Int? = 2) -> String {
        money(value.amount, value.currency, fractionDigits: fractionDigits)
    }

    func currencySymbol(_ currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = currency.iso4217
        return formatter.currencySymbol ?? currency.iso4217
    }

    // MARK: Numbers

    /// "+12%", "−8%" — a real minus sign, as the design uses.
    func percentChange(_ change: Double) -> String {
        let value = Int((change * 100).rounded())
        return value > 0 ? "+\(value)%" : value < 0 ? "−\(abs(value))%" : "0%"
    }

    func decimal(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    func integer(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(locale))
    }

    // MARK: Units

    var distanceUnit: String { unitSystem == .metric ? "km" : "mi" }
    var consumptionUnit: String { unitSystem == .metric ? "L/100km" : "mpg" }

    func distance(_ distance: Distance) -> String {
        integer(unitSystem == .metric ? distance.kilometers : distance.miles) + " " + distanceUnit
    }

    func odometer(_ odometer: Odometer) -> String { distance(odometer.value) }

    /// L/100 km, or mpg (US) for imperial — the same physical figure, inverted.
    func consumption(_ litersPer100km: Double) -> String {
        unitSystem == .metric ? decimal(litersPer100km) : decimal(235.215 / litersPer100km)
    }

    func volume(_ volume: Volume) -> String {
        unitSystem == .metric ? integer(volume.liters) + " L" : decimal(volume.liters / 3.785411784) + " gal"
    }

    // MARK: Dates

    func shortDate(_ date: Date, relativeTo now: Date) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.abbreviated).day()
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }

    func longDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated).year())
    }

    /// "Oct", or "O" when `narrow`.
    func month(_ date: Date, narrow: Bool = false) -> String {
        date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(narrow ? .narrow : .abbreviated))
    }
}

extension Decimal {
    func rounded(scale: Int) -> Decimal {
        var input = self, output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}

extension ExpenseCategory {
    var displayName: String {
        switch self {
        case .fuel: "Fuel"
        case .maintenance: "Service"
        case .repairs: "Repairs"
        case .insurance: "Insurance"
        case .parking: "Parking"
        case .carWash: "Car wash"
        case .tires: "Tyres"
        case .taxes: "Taxes"
        case .accessories: "Accessories"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .fuel: "fuelpump"
        case .maintenance: "wrench.adjustable"
        case .repairs: "hammer"
        case .insurance: "checkmark.shield"
        case .parking: "parkingsign"
        case .carWash: "drop"
        case .tires: "circle.circle"
        case .taxes: "building.columns"
        case .accessories: "bag"
        case .other: "dollarsign.square"
        }
    }
}

extension ServiceType {
    var displayName: String {
        switch self {
        case .oilChange: "Oil change"
        case .filters: "Filters"
        case .brakes: "Brakes"
        case .tires: "Tyres"
        case .battery: "Battery"
        case .suspension: "Suspension"
        case .engine: "Engine"
        case .electrical: "Electrical"
        case .other: "Other"
        }
    }
}

extension ReminderKind {
    var displayName: String {
        switch self {
        case .oilChange: "Oil change"
        case .filterReplacement: "Filters"
        case .tireChange: "Tyre swap"
        case .tirePressure: "Tyre pressure"
        case .technicalInspection: "Technical inspection"
        case .insurance: "Insurance"
        case .battery: "Battery"
        case .brakePads: "Brake pads"
        case .timingBelt: "Timing belt"
        case .vehicleTax: "Vehicle tax"
        case .custom: "Custom"
        }
    }

    var symbolName: String {
        switch self {
        case .oilChange: "drop"
        case .filterReplacement: "aqi.medium"
        case .tireChange, .tirePressure: "circle.circle"
        case .technicalInspection: "calendar"
        case .insurance: "checkmark.shield"
        case .battery: "minus.plus.batteryblock"
        case .brakePads: "exclamationmark.brakesignal"
        case .timingBelt: "gearshape.2"
        case .vehicleTax: "building.columns"
        case .custom: "bell"
        }
    }

    /// Kinds that are naturally tracked by distance rather than by date.
    var prefersMileage: Bool {
        switch self {
        case .oilChange, .filterReplacement, .brakePads, .timingBelt: true
        default: false
        }
    }
}

extension DocumentType {
    var displayName: String {
        switch self {
        case .insurance: "Insurance"
        case .registration: "Registration"
        case .technicalInspection: "Tech. inspection"
        case .warranty: "Warranty"
        case .driverLicense: "Driver licence"
        case .serviceDocument: "Service document"
        case .purchaseInvoice: "Purchase invoice"
        case .manual: "Manual"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .insurance: "checkmark.shield"
        case .registration: "doc.text"
        case .technicalInspection: "calendar"
        case .warranty: "seal"
        case .driverLicense: "person.text.rectangle"
        case .serviceDocument: "wrench.adjustable"
        case .purchaseInvoice: "dollarsign.square"
        case .manual: "book.closed"
        case .other: "doc"
        }
    }

    /// The reminder an expiry date turns into.
    var reminderKind: ReminderKind {
        switch self {
        case .insurance: .insurance
        case .technicalInspection: .technicalInspection
        default: .custom
        }
    }
}

extension DisplayFormat {
    /// "PDF · 240 KB".
    func fileSummary(mimeType: String, bytes: Int64) -> String {
        let kind = mimeType == "application/pdf" ? "PDF" : mimeType.hasPrefix("image/") ? "Photo" : "File"
        return kind + " · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
