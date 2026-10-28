import Foundation

/// Client for the `car-receipt` Supabase Edge Function: a receipt photo (plus the text the
/// device already recognised) in, structured fields out — with amounts converted into the
/// car's currency at a real published rate.
///
/// Every field it produces is UNACCEPTED: nothing is saved until a person reviews it.
public struct CarReceiptService: Sendable {
    private struct Request: Encodable {
        let images: [String]
        let ocrText: String?
        let targetCurrency: String
        let vehicle: AIChatVehicle?
        let language: String
        let today: String
    }

    struct Response: Decodable {
        let status: String
        let receipt: Receipt?
        let warnings: [String]?
    }

    struct Receipt: Decodable {
        struct Value<T: Decodable>: Decodable { let value: T?; let confidence: Double? }
        struct Original: Decodable {
            let currency: String?
            let currencyConfidence: Double?
            let total: Double?
            let totalConfidence: Double?
            let fuelAmount: Double?
            let pricePerUnit: Double?
            let serviceItems: [Item]?
        }
        struct Target: Decodable {
            let currency: String
            let total: Double?
            let fuelAmount: Double?
            let pricePerUnit: Double?
            let serviceItems: [Item]?
        }
        struct Item: Decodable { let name: String; let type: String?; let price: Double? }
        struct Conversion: Decodable {
            let status: String
            let from: String?
            let to: String?
            let rate: Double?
            let rateDate: String?
            let source: String?
        }
        struct Fuel: Decodable { let quantity: Double?; let unit: String?; let fuelType: String?; let confidence: Double? }

        let kind: String?
        let merchant: Value<String>?
        let date: Value<String>?
        let original: Original
        let inTargetCurrency: Target
        let conversion: Conversion
        let fuel: Fuel?
        let expenseCategory: String?
        let odometerKm: Value<Double>?
    }

    private let url: URL
    private let publishableKey: String
    private let session: URLSession
    private let timeout: TimeInterval
    private let accessToken: @Sendable () async -> String?

    public init(
        configuration: AIServiceConfiguration, session: URLSession = .shared, timeout: TimeInterval = 75,
        accessToken: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.url = configuration.functionURL.deletingLastPathComponent().appending(path: "car-receipt")
        self.publishableKey = configuration.publishableKey
        self.session = session
        self.timeout = timeout
        self.accessToken = accessToken
    }

    func analyze(
        image: Data, ocrText: String?, targetCurrency: CurrencyCode, vehicle: AIChatVehicle?,
        language: String, today: Date, calendar: Calendar
    ) async throws -> Response {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        if let token = await accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Request(
            images: [image.base64EncodedString()],
            ocrText: ocrText.flatMap { $0.isEmpty ? nil : String($0.prefix(8_000)) },
            targetCurrency: targetCurrency.iso4217, vehicle: vehicle, language: language,
            today: Self.isoDay(today, calendar: calendar)
        ))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw DomainError.ai(.cancelled)
        } catch let error as URLError {
            throw AIChatService.map(error)
        }
        guard let http = response as? HTTPURLResponse else { throw DomainError.ai(.structuredOutputInvalid) }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            print("[CarReceiptService] HTTP \(http.statusCode)")
            #endif
            throw http.statusCode == 413 ? DomainError.document(.fileTooLarge(maxBytes: 2_000_000)) : AIChatService.map(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DomainError.ai(.structuredOutputInvalid)
        }
    }

    static func isoDay(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    // MARK: - Mapping to the domain

    /// Turns the function's answer into a draft for review. Throws `.notAReceipt` for a photo
    /// of something else. Amounts in the draft are in `target` — the car's currency.
    static func draft(from response: Response, target: CurrencyCode, calendar: Calendar) throws -> ReceiptDraft {
        guard response.status != "not_a_receipt", let r = response.receipt else { throw DomainError.ai(.notAReceipt) }

        var draft = ReceiptDraft()
        draft.suggestedRecordKind = switch r.kind {
        case "fuel": .fuel
        case "service": .service
        default: .expense
        }

        if let name = r.merchant?.value.map(shortMerchant), !name.isEmpty {
            draft.vendor = FieldSuggestion(value: name, confidence: r.merchant?.confidence ?? 0)
        }
        if let iso = r.date?.value, let date = parseDay(iso, calendar: calendar) {
            draft.date = FieldSuggestion(value: date, confidence: r.date?.confidence ?? 0)
        }

        // Which amount the record should carry: a fuel entry is the fuel line, not the coffee.
        let isFuel = draft.suggestedRecordKind == .fuel
        var printedAmount = isFuel ? (r.original.fuelAmount ?? r.original.total) : r.original.total
        var targetAmount = isFuel ? (r.inTargetCurrency.fuelAmount ?? r.inTargetCurrency.total) : r.inTargetCurrency.total
        // Models sometimes put the litres where the fuel amount belongs. Litres × price is
        // printed on every fuel receipt, so when the given amount disagrees with it, the
        // product wins — as long as it fits inside the receipt total.
        if isFuel, let liters = r.fuel?.quantity, let price = r.original.pricePerUnit, liters > 0, price > 0 {
            let product = liters * price
            let fitsTotal = r.original.total.map { product <= $0 * 1.01 } ?? true
            if fitsTotal, let given = printedAmount, abs(given - product) / product > 0.02 {
                printedAmount = product
                // Convert with the published rate itself, not a ratio of rounded amounts.
                if r.conversion.status == "same_currency" { targetAmount = product }
                else if let rate = r.conversion.rate { targetAmount = product * rate }
                else { targetAmount = nil }
            }
        }
        let printedCurrency = r.original.currency.map(CurrencyCode.init)

        if let printedAmount, let printedCurrency {
            draft.originalTotal = Money(decimal(printedAmount, scale: 2), printedCurrency)
        }
        let status = CurrencyConversion.Status(rawValue: camel(r.conversion.status)) ?? .unknownCurrency
        draft.conversion = CurrencyConversion(
            status: status, from: printedCurrency, to: target,
            rate: r.conversion.rate.map { decimal($0, scale: 6) },
            rateDate: r.conversion.rateDate, source: r.conversion.source
        )
        if let targetAmount {
            // A converted figure is as sure as the reading under it; the rate itself is exact.
            let confidence = min(r.original.totalConfidence ?? 0, r.original.currencyConfidence ?? 1)
            draft.total = FieldSuggestion(value: Money(decimal(targetAmount, scale: 2), target), confidence: confidence)
        }

        if let fuel = r.fuel, let liters = fuel.quantity, fuel.unit != "kWh" {
            draft.fuelVolume = FieldSuggestion(value: Volume(liters: liters), confidence: fuel.confidence ?? 0)
        }
        if let km = r.odometerKm?.value, km > 0 {
            draft.odometer = FieldSuggestion(value: Odometer(kilometers: km), confidence: r.odometerKm?.confidence ?? 0)
        }
        if let raw = r.expenseCategory, let category = ExpenseCategory(rawValue: raw) {
            draft.expenseCategory = FieldSuggestion(value: category, confidence: 0.7)
        }
        // Jobs and parts belong to workshop invoices only — not the coffee on a fuel receipt.
        draft.serviceItems = (draft.suggestedRecordKind == .service ? (r.inTargetCurrency.serviceItems ?? []) : []).map { item in
            ServiceItem(
                type: ServiceType(rawValue: item.type ?? "") ?? .other, name: item.name,
                partCost: item.price.map { Money(decimal($0, scale: 2), target) }
            )
        }

        var warnings = Set((response.warnings ?? []).compactMap(ReceiptWarning.init(rawValue:)))
        // Repaired above from litres × price: the numbers agree now, so don't alarm anyone.
        if isFuel, let liters = r.fuel?.quantity, let price = r.original.pricePerUnit, let amount = printedAmount,
           abs(liters * price - amount) / amount <= 0.02 {
            warnings.remove(.mathMismatch)
        }
        if response.status == "unreadable" { warnings.insert(.unreadable) }
        draft.warnings = warnings
        return draft
    }

    /// "ORLEN S.A. Stacja Paliw nr 512 ul. Krakowska 10, Warszawa" → "ORLEN S.A. Stacja Paliw nr 512":
    /// the name, without the street address that receipts print under it.
    static func shortMerchant(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let addressStarts = [" ul.", " ul ", " al.", " pl.", " street", " st.", " str.", " ave", ","]
        for marker in addressStarts {
            if let range = name.range(of: marker, options: .caseInsensitive), range.lowerBound > name.startIndex {
                name = String(name[..<range.lowerBound])
            }
        }
        return String(name.prefix(60)).trimmingCharacters(in: .whitespaces)
    }

    private static func camel(_ snake: String) -> String {
        let parts = snake.split(separator: "_")
        return parts.enumerated().map { $0.offset == 0 ? String($0.element) : $0.element.capitalized }.joined()
    }

    private static func decimal(_ value: Double, scale: Int) -> Decimal {
        Decimal(string: String(format: "%.\(scale)f", value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
    }

    private static func parseDay(_ iso: String, calendar: Calendar) -> Date? {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
