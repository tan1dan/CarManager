import Foundation

/// Provenance of a record. `.automatic` is the reserved extension point for OBD-II / imports.
public enum RecordSource: Hashable, Codable, Sendable {
    case manual
    case receiptScan(ReceiptScanID)
    case imported
    case automatic(providerID: String)
}
