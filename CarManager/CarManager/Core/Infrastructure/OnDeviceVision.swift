import Foundation
import UIKit
import Vision

/// On-device OCR with the Vision framework. Nothing leaves the phone.
public struct VisionTextRecognizer: TextRecognizing {
    public init() {}

    public func recognizeText(in image: Data) async throws -> String {
        guard let cgImage = UIImage(data: image)?.cgImage else { throw DomainError.ai(.noTextRecognized) }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: DomainError.ai(.transport(error.localizedDescription))); return }
                let lines = (request.results as? [VNRecognizedTextObservation] ?? [])
                    // Top to bottom, as printed (Vision's origin is bottom-left).
                    .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                    .compactMap { $0.topCandidates(1).first?.string }
                if lines.isEmpty { continuation.resume(throwing: DomainError.ai(.noTextRecognized)) }
                else { continuation.resume(returning: lines.joined(separator: "\n")) }
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            do {
                try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
            } catch {
                continuation.resume(throwing: DomainError.ai(.transport(error.localizedDescription)))
            }
        }
    }
}

/// Downscales, bakes in the orientation and re-encodes as JPEG. Re-encoding through UIImage
/// drops EXIF, including GPS — so an image never carries the user's location anywhere.
public struct JPEGImagePreprocessor: ImagePreprocessing {
    private let maxDimension: CGFloat

    public init(maxDimension: CGFloat = 2_048) { self.maxDimension = maxDimension }

    public func prepareForUpload(_ image: Data) async throws -> Data {
        guard let source = UIImage(data: image) else { throw DomainError.document(.unsupportedType) }
        let scale = min(1, maxDimension / max(source.size.width, source.size.height))
        let size = CGSize(width: (source.size.width * scale).rounded(), height: (source.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.82) else { throw DomainError.document(.fileWriteFailed) }
        return data
    }
}

/// Receipts are read on the device: Vision OCR plus `ReceiptTextParser`. Dashboard lights and
/// body damage go to the `car-vision` Edge Function; without it (no endpoint configured) they
/// fail plainly instead of inventing findings.
public struct HybridVisionAnalysisProvider: VisionAnalysisProvider {
    private let vehicles: any VehicleRepository
    private let odometer: any OdometerRepository
    private let remote: CarVisionService?
    private let receipts: CarReceiptService?
    private let clock: any ClockProviding
    private let language: String

    public init(
        vehicles: any VehicleRepository, odometer: any OdometerRepository, remote: CarVisionService?,
        receipts: CarReceiptService? = nil,
        clock: any ClockProviding, language: String = Bundle.main.preferredLocalizations.first ?? "en"
    ) {
        self.vehicles = vehicles
        self.odometer = odometer
        self.remote = remote
        self.receipts = receipts
        self.clock = clock
        self.language = language
    }

    public func analyze(_ request: VisionAnalysisRequest) async throws -> VisionAnalysisResult {
        switch request {
        case .receipt(let image, let ocrText, let vehicleID):
            let (vehicle, currency) = await facts(vehicleID)
            if let receipts {
                do {
                    let response = try await receipts.analyze(
                        image: image, ocrText: ocrText, targetCurrency: currency, vehicle: vehicle,
                        language: language, today: clock.now, calendar: clock.calendar
                    )
                    return .receipt(try CarReceiptService.draft(from: response, target: currency, calendar: clock.calendar))
                } catch let error as DomainError where Self.canReadOnDevice(after: error) {
                    // No connection or the service is down: fall back to the on-device reader.
                }
            }
            guard let text = ocrText, !text.isEmpty else { throw DomainError.ai(.noTextRecognized) }
            var draft = ReceiptTextParser.parse(text, fallbackCurrency: currency, now: clock.now, calendar: clock.calendar)
            if receipts != nil { draft.warnings.insert(.readOnDevice) }
            return .receipt(draft)

        case .dashboard(let image, let vehicleID):
            guard let remote else { throw DomainError.ai(.notConfigured) }
            let (vehicle, currency) = await facts(vehicleID)
            let response = try await remote.analyze(kind: .dashboard, images: [image], vehicle: vehicle,
                                                    currency: currency, language: language)
            return .dashboard(CarVisionService.dashboardFindings(response), summary: response.summary)

        case .damage(let images, let vehicleID):
            guard let remote else { throw DomainError.ai(.notConfigured) }
            let (vehicle, currency) = await facts(vehicleID)
            let response = try await remote.analyze(kind: .damage, images: Array(images.prefix(3)), vehicle: vehicle,
                                                    currency: currency, language: language)
            return .damage(CarVisionService.damageFindings(response, currency: currency), summary: response.summary)
        }
    }

    /// Only transport problems fall back. "Not a receipt" or a rejected request must not be
    /// papered over by a weaker reader.
    static func canReadOnDevice(after error: DomainError) -> Bool {
        switch error {
        case .ai(.offline), .ai(.timedOut), .ai(.serverError), .ai(.rateLimited), .ai(.transport), .ai(.structuredOutputInvalid):
            true
        default:
            false
        }
    }

    /// Make, model, year, fuel and mileage — never the VIN or plate — plus the car's currency.
    private func facts(_ vehicleID: VehicleID?) async -> (AIChatVehicle?, CurrencyCode) {
        guard let vehicleID, let vehicle = try? await vehicles.vehicle(id: vehicleID) else { return (nil, .eur) }
        let km = (try? await odometer.current(vehicleID: vehicleID))?.value.kilometers
        return (AIChatVehicle(make: vehicle.brand, model: vehicle.model, year: vehicle.year,
                              fuelType: vehicle.fuelType.rawValue, mileageKm: km.map { Int($0.rounded()) }),
                vehicle.primaryCurrency)
    }
}
