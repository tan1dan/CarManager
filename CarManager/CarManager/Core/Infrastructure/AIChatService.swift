import Foundation

/// Where the assistant lives. Read from Info.plist (`CarManager-Info.plist`), never hard-coded
/// in Swift, so a staging build can point elsewhere without a code change.
///
/// `SupabaseURL` — e.g. `https://<project-ref>.supabase.co`
/// `SupabasePublishableKey` — the project's publishable (anon) key. It identifies the project
/// to Supabase's gateway; it is NOT a secret and NOT the OpenAI key, which stays server-side.
public struct AIServiceConfiguration: Sendable, Equatable {
    public let functionURL: URL
    public let publishableKey: String

    public static let functionName = "car-assistant"

    public init(functionURL: URL, publishableKey: String) {
        self.functionURL = functionURL
        self.publishableKey = publishableKey
    }

    /// `nil` when either value is missing or still a placeholder — the caller then wires a
    /// provider that says "not configured" rather than inventing answers.
    public static func fromBundle(_ bundle: Bundle = .main) -> AIServiceConfiguration? {
        guard let base = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)?.trimmingCharacters(in: .whitespaces),
              !base.isEmpty, !key.isEmpty, !base.contains("<"), !key.contains("<"),
              let url = URL(string: base), url.scheme == "https", url.host != nil
        else { return nil }
        return AIServiceConfiguration(
            functionURL: url.appending(path: "functions/v1/\(functionName)"),
            publishableKey: key
        )
    }
}

/// One question plus the earlier turns of the same conversation in, one answer out.
/// No streaming, no images.
public protocol AIChatServiceProtocol: Sendable {
    /// `vehicle == nil` means "another car": the assistant answers in general terms.
    func sendMessage(_ message: String, history: [AIChatTurn], vehicle: AIChatVehicle?) async throws -> String
}

public extension AIChatServiceProtocol {
    func sendMessage(_ message: String) async throws -> String { try await sendMessage(message, history: [], vehicle: nil) }
    func sendMessage(_ message: String, history: [AIChatTurn]) async throws -> String {
        try await sendMessage(message, history: history, vehicle: nil)
    }
}

/// The car a conversation is about, as the function receives it. Built from
/// `AIVehicleContext.VehicleFacts`, which has no field for a VIN, a plate or notes.
public struct AIChatVehicle: Encodable, Sendable, Equatable {
    public let make: String
    public let model: String
    public let year: Int?
    public let fuelType: String
    public let mileageKm: Int?

    public init(make: String, model: String, year: Int?, fuelType: String, mileageKm: Int?) {
        self.make = make; self.model = model; self.year = year; self.fuelType = fuelType; self.mileageKm = mileageKm
    }

    public init(_ facts: AIVehicleContext.VehicleFacts) {
        self.init(make: facts.brand, model: facts.model, year: facts.year, fuelType: facts.fuelType,
                  mileageKm: facts.currentOdometerKm.map { Int($0.rounded()) })
    }
}

/// One earlier message, as the `car-assistant` function receives it.
public struct AIChatTurn: Encodable, Sendable, Equatable {
    public enum Role: String, Encodable, Sendable { case user, assistant }
    public let role: Role
    public let content: String
    public init(role: Role, content: String) { self.role = role; self.content = content }
}

public struct AIChatService: AIChatServiceProtocol {
    /// The backend rejects anything outside 1…4000 characters; checking first saves a round trip.
    public static let maxMessageLength = 4_000
    /// Mirrors the function's limits; the server trims again, this just avoids sending waste.
    public static let historyLimit = 20
    public static let historyCharacterBudget = 24_000

    private struct Request: Encodable {
        let message: String
        let history: [AIChatTurn]
        /// Always present — `null` tells the function "no specific car".
        let vehicle: AIChatVehicle?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            try container.encode(history, forKey: .history)
            try container.encode(vehicle, forKey: .vehicle)
        }
        private enum CodingKeys: String, CodingKey { case message, history, vehicle }
    }
    private struct Response: Decodable { let answer: String }
    private struct ErrorBody: Decodable { let error: String?; let message: String? }

    private let configuration: AIServiceConfiguration
    private let session: URLSession
    private let timeout: TimeInterval
    /// The signed-in user's Supabase access token, once the backend requires one (see ADR-017).
    /// Until then requests carry the publishable key only.
    private let accessToken: @Sendable () async -> String?

    public init(
        configuration: AIServiceConfiguration, session: URLSession = .shared, timeout: TimeInterval = 60,
        accessToken: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.configuration = configuration
        self.session = session
        self.timeout = timeout
        self.accessToken = accessToken
    }

    public func sendMessage(_ message: String, history: [AIChatTurn], vehicle: AIChatVehicle?) async throws -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DomainError.validation(.emptyField(.title)) }
        guard text.count <= Self.maxMessageLength else {
            throw DomainError.ai(.messageTooLong(maxCharacters: Self.maxMessageLength))
        }

        var request = URLRequest(url: configuration.functionURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        if let token = await accessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(Request(message: text, history: Self.bounded(history), vehicle: vehicle))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw DomainError.ai(.cancelled)
        } catch let error as URLError {
            throw Self.map(error)
        }

        guard let http = response as? HTTPURLResponse else { throw DomainError.ai(.structuredOutputInvalid) }
        guard (200..<300).contains(http.statusCode) else {
            #if DEBUG
            // Development aid only: status and the server's short error text. Never headers —
            // they carry the key.
            let detail = (try? JSONDecoder().decode(ErrorBody.self, from: data)).flatMap { $0.error ?? $0.message } ?? ""
            print("[AIChatService] HTTP \(http.statusCode) \(detail.prefix(200))")
            #endif
            throw Self.map(status: http.statusCode)
        }
        guard let answer = try? JSONDecoder().decode(Response.self, from: data).answer
                .trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty
        else { throw DomainError.ai(.structuredOutputInvalid) }
        return answer
    }

    /// The newest turns that fit both the count and the character budget, oldest first.
    static func bounded(_ history: [AIChatTurn]) -> [AIChatTurn] {
        var kept: [AIChatTurn] = [], total = 0
        for turn in history.suffix(historyLimit).reversed() {
            let content = String(turn.content.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxMessageLength))
            guard !content.isEmpty else { continue }
            total += content.count
            if total > historyCharacterBudget { break }
            kept.insert(AIChatTurn(role: turn.role, content: content), at: 0)
        }
        return kept
    }

    static func map(status: Int) -> DomainError {
        switch status {
        case 400, 413, 422: .ai(.invalidRequest)
        case 401, 403: .ai(.unauthorized)
        case 408: .ai(.timedOut)
        case 429: .ai(.rateLimited)
        case 504: .ai(.timedOut)
        default: .ai(.serverError(status: status))
        }
    }

    static func map(_ error: URLError) -> DomainError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            .ai(.offline)
        case .timedOut: .ai(.timedOut)
        case .cancelled: .ai(.cancelled)
        default: .ai(.transport("URLError \(error.code.rawValue)"))
        }
    }
}

/// Adapts the single-message service to the app's `AIProvider` port, so `AskAI` — persistence
/// in iCloud, quota, cancellation — works unchanged.
///
/// The newest user message is the question; everything before it in the conversation is sent
/// as `history`, so follow-ups are understood. The answer arrives whole, as one `.completed` event.
public struct SupabaseAIProvider: AIProvider {
    private let service: any AIChatServiceProtocol

    public init(service: any AIChatServiceProtocol) { self.service = service }

    public func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let index = request.messages.lastIndex(where: { $0.role == .user }) else {
                        throw DomainError.ai(.invalidRequest)
                    }
                    let answer = try await service.sendMessage(
                        request.messages[index].text, history: Self.history(request.messages[..<index]),
                        vehicle: request.context.map { AIChatVehicle($0.vehicle) }
                    )
                    try Task.checkCancellation()
                    continuation.yield(.completed(text: answer))
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: DomainError.ai(.cancelled))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Earlier turns only: app notices and failed answers are not part of what was said.
    static func history(_ messages: ArraySlice<AIMessage>) -> [AIChatTurn] {
        messages.compactMap { message in
            guard message.failureDescription == nil else { return nil }
            switch message.role {
            case .user: return AIChatTurn(role: .user, content: message.text)
            case .assistant: return AIChatTurn(role: .assistant, content: message.text)
            case .systemNotice: return nil
            }
        }
    }
}

/// Wired when the build has no endpoint configured: every question fails with a clear
/// "not configured" instead of a made-up answer.
public struct UnconfiguredAIProvider: AIProvider {
    public init() {}
    public func stream(_ request: AIChatRequest) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: DomainError.ai(.notConfigured)) }
    }
}
