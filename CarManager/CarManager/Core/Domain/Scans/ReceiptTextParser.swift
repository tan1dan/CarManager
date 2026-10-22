import Foundation

/// Turns on-device OCR text into a `ReceiptDraft`. PURE, so every receipt layout we learn
/// about becomes a unit test.
///
/// It only proposes: every field comes back UNACCEPTED, with a confidence that reflects how
/// it was found (a "TOTAL" line beats "the largest number on the page"). Nothing it returns is
/// saved until a person has reviewed it.
public enum ReceiptTextParser {
    public static func parse(_ text: String, fallbackCurrency: CurrencyCode, now: Date, calendar: Calendar) -> ReceiptDraft {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let lowered = text.lowercased()

        var draft = ReceiptDraft()
        let currency = detectCurrency(lowered) ?? fallbackCurrency

        if let vendor = lines.first(where: isVendorCandidate) {
            draft.vendor = FieldSuggestion(value: vendor, confidence: 0.6)
        }
        if let (amount, confidence) = total(in: lines) {
            draft.total = FieldSuggestion(value: Money(amount, currency), confidence: confidence)
        }
        if let date = date(in: text, now: now, calendar: calendar) {
            draft.date = FieldSuggestion(value: date, confidence: 0.8)
        }

        if isFuelReceipt(lowered) {
            draft.suggestedRecordKind = .fuel
            draft.expenseCategory = FieldSuggestion(value: .fuel, confidence: 0.8)
            if let liters = volume(in: lowered) {
                draft.fuelVolume = FieldSuggestion(value: Volume(liters: liters), confidence: 0.7)
            }
        } else {
            let (category, confidence) = guessCategory(lowered)
            draft.expenseCategory = FieldSuggestion(value: category, confidence: confidence)
            draft.suggestedRecordKind = .expense
        }
        return draft
    }

    // MARK: - Fields

    static let totalKeywords = ["total", "suma", "razem", "summe", "gesamt", "amount due", "do zapłaty",
                                "do zaplaty", "итого", "к оплате", "totalt", "att betala", "montant"]

    /// The amount on a "TOTAL" line (or the line after it); otherwise the largest amount.
    static func total(in lines: [String]) -> (Decimal, Double)? {
        for (index, line) in lines.enumerated().reversed() {
            let lower = line.lowercased()
            guard totalKeywords.contains(where: lower.contains), !lower.contains("subtotal") else { continue }
            if let amount = amounts(in: line).last { return (amount, 0.85) }
            if index + 1 < lines.count, let amount = amounts(in: lines[index + 1]).last { return (amount, 0.75) }
        }
        return lines.flatMap(amounts).max().map { ($0, 0.4) }
    }

    /// "84.20", "84,20", "1 284,50", "1.284,50".
    static func amounts(in line: String) -> [Decimal] {
        let pattern = #"(?<![\d.,])(\d{1,3}(?:[ .\x{00A0}]\d{3})*|\d+)[.,](\d{2})(?![\d])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let whole = Range(match.range(at: 1), in: line), let cents = Range(match.range(at: 2), in: line) else { return nil }
            let digits = line[whole].filter(\.isNumber)
            return Decimal(string: "\(digits).\(line[cents])", locale: Locale(identifier: "en_US_POSIX"))
        }
    }

    /// The first plausible date that is not in the future.
    static func date(in text: String, now: Date, calendar: Calendar) -> Date? {
        let patterns: [(String, (Int, Int, Int))] = [
            (#"(\d{4})[-./](\d{1,2})[-./](\d{1,2})"#, (0, 1, 2)),   // 2026-10-12
            (#"(\d{1,2})[-./](\d{1,2})[-./](\d{4})"#, (2, 1, 0)),   // 12.10.2026
            (#"(\d{1,2})[-./](\d{1,2})[-./](\d{2})(?!\d)"#, (2, 1, 0)) // 12.10.26
        ]
        for (pattern, order) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let parts = (1...3).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
                guard parts.count == 3 else { continue }
                var year = parts[order.0]
                if year < 100 { year += 2000 }
                let (month, day) = (parts[order.1], parts[order.2])
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
                      // Rejects 31.02 rolling over into March.
                      calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day,
                      date <= now, date > calendar.date(byAdding: .year, value: -5, to: now) ?? .distantPast
                else { continue }
                return date
            }
        }
        return nil
    }

    static func detectCurrency(_ text: String) -> CurrencyCode? {
        if text.contains("€") || text.contains("eur") { return .eur }
        if text.contains("zł") || text.contains("pln") { return CurrencyCode("PLN") }
        if text.contains("sek") || text.contains(" kr") { return .sek }
        if text.contains("£") || text.contains("gbp") { return CurrencyCode("GBP") }
        if text.contains("$") || text.contains("usd") { return .usd }
        return nil
    }

    static let fuelKeywords = ["diesel", "benzyna", "pb95", "pb 95", "pb98", "unleaded", "petrol", "gasoline",
                               "super 95", "e10", "lpg", "v-power", "verva", "dynamic", "olej napędowy", "дизель", "бензин"]

    static func isFuelReceipt(_ text: String) -> Bool { fuelKeywords.contains(where: text.contains) }

    /// "48,32 L", "48.32 ltr".
    static func volume(in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,3}[.,]\d{1,3})\s*(?:l|ltr|litr|litre|liter)\b"#) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range].replacingOccurrences(of: ",", with: "."))
    }

    static func guessCategory(_ text: String) -> (ExpenseCategory, Double) {
        let rules: [([String], ExpenseCategory)] = [
            (["wash", "myjnia", "waschanlage", "мойка"], .carWash),
            (["parking", "parkowanie", "парковка"], .parking),
            (["insurance", "ubezpieczenie", "versicherung", "страхов"], .insurance),
            (["tyre", "tire", "opony", "reifen", "шин"], .tires),
            (["oil", "service", "serwis", "werkstatt", "сервис"], .maintenance)
        ]
        for (words, category) in rules where words.contains(where: text.contains) { return (category, 0.6) }
        return (.other, 0.3)
    }

    private static func isVendorCandidate(_ line: String) -> Bool {
        let letters = line.filter(\.isLetter).count
        return letters >= 3 && Double(letters) / Double(max(line.count, 1)) > 0.5
    }
}
