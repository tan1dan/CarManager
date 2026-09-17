import Foundation

public enum AIPurpose: String, Sendable {
    case chat, insights
}

public struct AIChatRequest: Sendable {
    public let messages: [AIMessage]
    /// A bounded, deterministic snapshot — never raw database rows.
    public let context: AIVehicleContext?
    public let purpose: AIPurpose

    public init(messages: [AIMessage], context: AIVehicleContext?, purpose: AIPurpose = .chat) {
        self.messages = messages; self.context = context; self.purpose = purpose
    }
}

public enum AIStreamEvent: Sendable {
    case delta(String)
    case completed(text: String)
}

/// The provider abstraction. Swapping providers is a one-line change in the composition root.
public protocol AIProvider: Sendable {
    func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIStreamEvent, Error>
}

public enum VisionAnalysisRequest: Sendable {
    case receipt(image: Data, ocrText: String?, vehicleID: VehicleID)
    case dashboard(image: Data, vehicleID: VehicleID?)
    case damage(images: [Data], vehicleID: VehicleID)
}

public enum VisionAnalysisResult: Sendable {
    case receipt(ReceiptDraft)
    case dashboard([DashboardFinding])
    case damage([DamageFinding])
}

/// One provider, three request types — receipt/dashboard/damage share transport, auth,
/// quota, retry and error handling. Three protocols would triple the mock surface for nothing.
public protocol VisionAnalysisProvider: Sendable {
    func analyze(_ request: VisionAnalysisRequest) async throws -> VisionAnalysisResult
}

public protocol TextRecognizing: Sendable {
    func recognizeText(in image: Data) async throws -> String
}

public protocol ImagePreprocessing: Sendable {
    /// Downscales, normalises orientation and STRIPS EXIF/GPS before anything leaves the device.
    func prepareForUpload(_ image: Data) async throws -> Data
}

/// The bounded AI context. Note what it CANNOT carry: no VIN, no licence plate, no notes.
/// Redaction is structural, not conditional.
public struct AIVehicleContext: Sendable, Hashable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let vehicle: VehicleFacts
    public let coverage: DataCoverage

    public init(schemaVersion: Int = 1, generatedAt: Date, vehicle: VehicleFacts, coverage: DataCoverage) {
        self.schemaVersion = schemaVersion; self.generatedAt = generatedAt
        self.vehicle = vehicle; self.coverage = coverage
    }

    public struct VehicleFacts: Sendable, Hashable {
        public let brand: String
        public let model: String
        public let year: Int?
        public let fuelType: String
        public let currentOdometerKm: Double?
        // Deliberately absent: vin, licensePlate, color, purchasePrice, notes.

        public init(brand: String, model: String, year: Int?, fuelType: String, currentOdometerKm: Double?) {
            self.brand = brand; self.model = model; self.year = year
            self.fuelType = fuelType; self.currentOdometerKm = currentOdometerKm
        }
    }

    /// Tells the model exactly how much data exists, so it can decline rather than invent.
    public struct DataCoverage: Sendable, Hashable {
        public let fuelEntryCount: Int
        public let serviceRecordCount: Int
        public let expenseCount: Int
        public let hasSufficientDataForConsumption: Bool

        public init(fuelEntryCount: Int, serviceRecordCount: Int, expenseCount: Int, hasSufficientDataForConsumption: Bool) {
            self.fuelEntryCount = fuelEntryCount; self.serviceRecordCount = serviceRecordCount
            self.expenseCount = expenseCount
            self.hasSufficientDataForConsumption = hasSufficientDataForConsumption
        }
    }
}
