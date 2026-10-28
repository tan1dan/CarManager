import Foundation

/// Client for the `car-vision` Supabase Edge Function: dashboard warning lights and body
/// damage from photos. Images are already downscaled and stripped of EXIF/GPS by
/// `ImagePreprocessing` before they get here.
public struct CarVisionService: Sendable {
    public enum Kind: String, Encodable, Sendable { case dashboard, damage }

    private struct Request: Encodable {
        let kind: Kind
        let images: [String]
        let vehicle: AIChatVehicle?
        let currency: String
        let language: String
    }

    // Decoded leniently: an unexpected enum value becomes the cautious default, never a crash.
    struct Response: Decodable {
        let summary: String?
        let findings: [Finding]
    }

    struct Finding: Decodable {
        // Dashboard
        let warningName: String?
        let likelyCauses: [String]?
        let severity: String?
        let recommendedAction: String?
        let drivingSafety: String?
        let confidence: Double?
        // Damage
        let damageType: String?
        let suggestedRepair: String?
        let cosmeticRepairPossible: Bool?
        let estimatedCost: Cost?
    }

    struct Cost: Decodable {
        let low: Double
        let high: Double
        let currency: String?
        let confidence: Double?
    }

    private let url: URL
    private let publishableKey: String
    private let session: URLSession
    private let timeout: TimeInterval
    private let accessToken: @Sendable () async -> String?

    public init(
        configuration: AIServiceConfiguration, session: URLSession = .shared, timeout: TimeInterval = 75,
        accessToken: @escaping @Sendable () async -> String? = { nil }
    ) {
        // Same project, sibling function: …/functions/v1/car-vision
        self.url = configuration.functionURL.deletingLastPathComponent().appending(path: "car-vision")
        self.publishableKey = configuration.publishableKey
        self.session = session
        self.timeout = timeout
        self.accessToken = accessToken
    }

    func analyze(
        kind: Kind, images: [Data], vehicle: AIChatVehicle?, currency: CurrencyCode, language: String
    ) async throws -> Response {
        guard !images.isEmpty else { throw DomainError.ai(.invalidRequest) }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(publishableKey, forHTTPHeaderField: "apikey")
        if let token = await accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Request(
            kind: kind, images: images.map { $0.base64EncodedString() },
            vehicle: vehicle, currency: currency.iso4217, language: language
        ))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw DomainError.ai(.cancelled)
        } catch let error as URLError {
            throw AIChatService.map(error)
        }
        guard let http = response as? HTTPURLResponse else { throw DomainError.ai(.structuredOutputInvalid) }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            print("[CarVisionService] HTTP \(http.statusCode)")
            #endif
            throw http.statusCode == 413 ? DomainError.document(.fileTooLarge(maxBytes: 2_000_000)) : AIChatService.map(status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DomainError.ai(.structuredOutputInvalid)
        }
    }

    // MARK: - Mapping to the domain

    static func dashboardFindings(_ response: Response) -> [DashboardFinding] {
        response.findings.compactMap { f in
            guard let name = f.warningName?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
            return DashboardFinding(
                warningName: name,
                likelyCauses: f.likelyCauses ?? [],
                // Unknown values fall to the cautious side: "soon" and "unknown", never "safe".
                severity: f.severity.flatMap(FindingSeverity.init(rawValue:)) ?? .soon,
                recommendedAction: f.recommendedAction ?? "",
                drivingSafety: f.drivingSafety.flatMap(DrivingSafetyAssessment.init(rawValue:)) ?? .unknown,
                confidence: min(max(f.confidence ?? 0, 0), 1)
            )
        }
    }

    static func damageFindings(_ response: Response, currency: CurrencyCode) -> [DamageFinding] {
        response.findings.compactMap { f in
            guard let type = f.damageType?.trimmingCharacters(in: .whitespaces), !type.isEmpty else { return nil }
            var cost: CostEstimateRange?
            if let c = f.estimatedCost, c.low >= 0, c.low < c.high {
                let code = c.currency.map(CurrencyCode.init) ?? currency
                cost = CostEstimateRange(
                    low: Money(Decimal(c.low.rounded()), code), high: Money(Decimal(c.high.rounded()), code),
                    basis: .aiEstimate, confidence: min(max(c.confidence ?? 0, 0), 1)
                )
            }
            return DamageFinding(
                damageType: type,
                severity: f.severity.flatMap(DamageSeverity.init(rawValue:)) ?? .unknown,
                suggestedRepair: f.suggestedRepair ?? "",
                cosmeticRepairPossible: f.cosmeticRepairPossible,
                estimatedCost: cost
            )
        }
    }
}
