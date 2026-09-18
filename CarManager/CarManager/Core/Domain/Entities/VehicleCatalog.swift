import Foundation

/// Reference data for choosing a brand and model from a list, the way classifieds sites do.
///
/// It is suggestions, not a constraint: a vehicle's `brand`/`model` stay free strings, so a car
/// the catalog does not know can still be saved. Stored on device; see
/// `tools/vehicle-catalog/build_catalog.py` for where it comes from.
public struct VehicleCatalog: Sendable, Equatable, Codable {
    public let source: Source
    public let brands: [Brand]

    public init(source: Source, brands: [Brand]) {
        self.source = source
        self.brands = brands
    }

    /// Attribution the data's licence requires the app to show.
    public struct Source: Sendable, Equatable, Codable {
        public let name: String
        public let url: String
        public let upstream: String
        public let license: String

        public init(name: String, url: String, upstream: String, license: String) {
            self.name = name; self.url = url; self.upstream = upstream; self.license = license
        }
    }

    public struct Brand: Sendable, Equatable, Codable, Identifiable {
        public var id: String { name }
        public let name: String
        public let popular: Bool
        /// Other names people search by: "VW", "Шкода", "БМВ".
        public let aliases: [String]
        public let models: [Model]

        /// Every name this brand can be found by.
        public var searchNames: [String] { [name] + aliases }

        public init(name: String, popular: Bool = false, aliases: [String] = [], models: [Model]) {
            self.name = name; self.popular = popular; self.aliases = aliases; self.models = models
        }
    }

    public struct Model: Sendable, Equatable, Codable, Identifiable {
        public var id: String { name }
        public let name: String
        /// First and last production year. `to == nil` means still in production; `from == nil`
        /// means the source does not know.
        public let from: Int?
        public let to: Int?

        public init(name: String, from: Int? = nil, to: Int? = nil) {
            self.name = name; self.from = from; self.to = to
        }

        /// The model years worth offering, newest first. `nil` when the source has no start year.
        public func productionYears(currentYear: Int) -> [Int]? {
            guard let from else { return nil }
            let last = min(to ?? currentYear + 1, currentYear + 1)
            guard from <= last else { return nil }
            return Array((from...last).reversed())
        }
    }

    public func brand(named name: String) -> Brand? {
        let key = CatalogSearch.key(name)
        return brands.first { $0.searchNames.contains { CatalogSearch.key($0) == key } }
    }
}

extension VehicleCatalog.Brand {
    public func model(named name: String) -> VehicleCatalog.Model? {
        let key = CatalogSearch.key(name)
        return models.first { CatalogSearch.key($0.name) == key }
    }
}

/// Search the way people type into a classifieds filter: case, accents and punctuation do not
/// matter ("skoda" finds Škoda, "id3" finds ID.3, "c class" finds C-Class), Cyrillic is
/// transliterated ("Форд" finds Ford), and names that START with the query rank above names
/// that merely contain it. Transliteration alone misses spellings like "Тойота" (→ "tojota");
/// the catalog's curated brand aliases cover those.
public enum CatalogSearch {
    public static func key(_ text: String) -> String {
        (text.applyingTransform(.toLatin, reverse: false) ?? text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map(String.init)
            .joined()
    }

    public static func filter<Item>(_ items: [Item], query: String, name: (Item) -> String) -> [Item] {
        filter(items, query: query, names: { [name($0)] })
    }

    /// An item matches when ANY of its names does; its best match decides its rank.
    public static func filter<Item>(
        _ items: [Item], query: String, names: (Item) -> [String]
    ) -> [Item] {
        let needle = key(query)
        guard !needle.isEmpty else { return items }
        var prefixed: [Item] = []
        var contained: [Item] = []
        for item in items {
            let haystacks = names(item).map(key)
            if haystacks.contains(where: { $0.hasPrefix(needle) }) {
                prefixed.append(item)
            } else if haystacks.contains(where: { $0.contains(needle) }) {
                contained.append(item)
            }
        }
        return prefixed + contained
    }

    /// True when `query` names something not in `names` — the picker then offers it as a
    /// custom entry instead of forcing a wrong choice.
    public static func isNew(_ query: String, among names: [String]) -> Bool {
        let needle = key(query)
        return !needle.isEmpty && !names.contains { key($0) == needle }
    }
}
