import Foundation

/// Canonical unit: kilometres. Conversion to miles happens only in Presentation.
public struct Distance: Hashable, Codable, Sendable, Comparable {
    public let kilometers: Double
    public init(kilometers: Double) { self.kilometers = kilometers }
    public static func miles(_ value: Double) -> Distance { Distance(kilometers: value * 1.609344) }
    public var miles: Double { kilometers / 1.609344 }
    public static let zero = Distance(kilometers: 0)
    public static func < (lhs: Distance, rhs: Distance) -> Bool { lhs.kilometers < rhs.kilometers }
}

/// Canonical unit: litres (kWh for electric vehicles).
public struct Volume: Hashable, Codable, Sendable, Comparable {
    public let liters: Double
    public init(liters: Double) { self.liters = liters }
    public static func usGallons(_ v: Double) -> Volume { Volume(liters: v * 3.785411784) }
    public static let zero = Volume(liters: 0)
    public static func < (lhs: Volume, rhs: Volume) -> Bool { lhs.liters < rhs.liters }
}

public struct Odometer: Hashable, Codable, Sendable, Comparable {
    public let value: Distance
    public init(_ value: Distance) { self.value = value }
    public init(kilometers: Double) { self.value = Distance(kilometers: kilometers) }
    public var kilometers: Double { value.kilometers }
    public static func < (lhs: Odometer, rhs: Odometer) -> Bool { lhs.value < rhs.value }
}

public enum UnitSystem: String, CaseIterable, Codable, Sendable {
    case metric, imperial
}
