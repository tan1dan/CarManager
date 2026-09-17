import Foundation

public struct CurrencyCode: Hashable, Codable, Sendable, CustomStringConvertible {
    public let iso4217: String
    public init(_ iso4217: String) { self.iso4217 = iso4217.uppercased() }
    public var description: String { iso4217 }

    public static let eur = CurrencyCode("EUR")
    public static let usd = CurrencyCode("USD")
    public static let sek = CurrencyCode("SEK")
}

/// Money is always Decimal + currency. Never Double.
public struct Money: Hashable, Codable, Sendable {
    public let amount: Decimal
    public let currency: CurrencyCode

    public init(_ amount: Decimal, _ currency: CurrencyCode) {
        self.amount = amount
        self.currency = currency
    }

    public static func zero(_ currency: CurrencyCode) -> Money { Money(0, currency) }

    /// Adding across currencies is a programmer error — analytics groups by currency instead.
    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Cannot add \(lhs.currency) to \(rhs.currency)")
        return Money(lhs.amount + rhs.amount, lhs.currency)
    }
}
