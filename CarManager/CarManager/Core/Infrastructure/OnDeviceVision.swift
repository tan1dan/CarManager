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
/// body damage need a vision model behind our proxy; until it exists this says so plainly
/// instead of inventing findings.
public struct OnDeviceVisionAnalysisProvider: VisionAnalysisProvider {
    private let vehicles: any VehicleRepository
    private let clock: any ClockProviding

    public init(vehicles: any VehicleRepository, clock: any ClockProviding) {
        self.vehicles = vehicles
        self.clock = clock
    }

    public func analyze(_ request: VisionAnalysisRequest) async throws -> VisionAnalysisResult {
        switch request {
        case .receipt(_, let ocrText, let vehicleID):
            guard let text = ocrText, !text.isEmpty else { throw DomainError.ai(.noTextRecognized) }
            let currency = (try? await vehicles.vehicle(id: vehicleID))?.primaryCurrency ?? .eur
            return .receipt(ReceiptTextParser.parse(text, fallbackCurrency: currency, now: clock.now, calendar: clock.calendar))
        case .dashboard, .damage:
            throw DomainError.ai(.providerUnavailable)
        }
    }
}
