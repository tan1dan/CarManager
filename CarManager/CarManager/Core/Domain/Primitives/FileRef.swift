import Foundation

/// A pointer into FileStorage. Domain models never carry binary data.
/// The path is RELATIVE — container URLs change between launches and devices.
public struct FileRef: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let relativePath: String
    public let checksum: String

    public init(id: UUID = UUID(), relativePath: String, checksum: String = "") {
        self.id = id
        self.relativePath = relativePath
        self.checksum = checksum
    }
}

public enum FileKind: String, Codable, Sendable {
    case vehiclePhoto, receipt, document, thumbnail, scan
}

public enum FileAvailability: Hashable, Sendable {
    case local
    case downloading(progress: Double)
    case remote
}
