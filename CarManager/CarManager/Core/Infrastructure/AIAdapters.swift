import Foundation

/// Scripted provider used by previews, tests and offline development.
///
/// The production implementation (`BackendAIProvider`) will talk to our proxy over SSE.
/// The model-provider API key lives on that backend and never in the client — swapping
/// implementations is a one-line change in `AppDependencies`.
public struct MockAIProvider: AIProvider {
    private let reply: String
    private let chunkDelay: Duration

    public init(reply: String = "This is a placeholder answer from the mock AI provider.",
                chunkDelay: Duration = .milliseconds(40)) {
        self.reply = reply
        self.chunkDelay = chunkDelay
    }

    public func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var accumulated = ""
                for word in reply.split(separator: " ") {
                    try Task.checkCancellation()
                    try? await Task.sleep(for: chunkDelay)
                    let chunk = accumulated.isEmpty ? String(word) : " \(word)"
                    accumulated += chunk
                    continuation.yield(.delta(chunk))
                }
                continuation.yield(.completed(text: accumulated))
                continuation.finish()
            }
            // Cancelling the consuming Task cancels the underlying work.
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// One provider, three request types — receipt / dashboard / damage share transport, auth,
/// quota, retry and error handling.
public struct StubVisionAnalysisProvider: VisionAnalysisProvider {
    public init() {}

    public func analyze(_ request: VisionAnalysisRequest) async throws -> VisionAnalysisResult {
        try? await Task.sleep(for: .milliseconds(600))
        switch request {
        case .receipt:
            // Every field arrives UNACCEPTED. Nothing is trusted until a human reviews it.
            var draft = ReceiptDraft(suggestedRecordKind: .expense)
            draft.vendor = FieldSuggestion(value: "Placeholder Vendor", confidence: 0.8)
            draft.date = FieldSuggestion(value: Date(), confidence: 0.7)
            draft.total = FieldSuggestion(value: Money(42, .eur), confidence: 0.9)
            draft.expenseCategory = FieldSuggestion(value: .other, confidence: 0.5)
            return .receipt(draft)

        case .dashboard:
            return .dashboard([
                DashboardFinding(
                    warningName: "Placeholder warning",
                    likelyCauses: ["Placeholder cause"],
                    severity: .informational,
                    recommendedAction: "Placeholder action",
                    // The failure mode is "we don't know", never "safe to drive".
                    drivingSafety: .unknown,
                    confidence: 0.5
                )
            ])

        case .damage:
            return .damage([
                DamageFinding(
                    damageType: "Placeholder damage",
                    severity: .unknown,
                    suggestedRepair: "Placeholder repair",
                    cosmeticRepairPossible: nil,
                    // A RANGE, never a guaranteed price.
                    estimatedCost: CostEstimateRange(low: Money(100, .eur), high: Money(400, .eur))
                )
            ])
        }
    }
}

/// PLACEHOLDER for the on-device Vision framework text recogniser.
public struct StubTextRecognizer: TextRecognizing {
    public init() {}
    public func recognizeText(in image: Data) async throws -> String {
        "placeholder recognised text"
    }
}

/// PLACEHOLDER. The real implementation downscales, normalises orientation and — critically —
/// STRIPS EXIF/GPS before any image leaves the device.
public struct StubImagePreprocessor: ImagePreprocessing {
    public init() {}
    public func prepareForUpload(_ image: Data) async throws -> Data { image }
}

public struct StubDocumentExporter: DocumentExporting {
    public init() {}
    public func exportPDF(vehicleID: VehicleID, period: AnalyticsPeriod) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).pdf")
        try? Data().write(to: url)
        return url
    }
}
