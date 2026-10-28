import Testing
import Foundation
@testable import CarManager

/// Answers every request made through its session with whatever `handler` returns, and keeps
/// the requests so a test can inspect them. No real network, no OpenAI key.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    // Keyed by host, so suites that run in parallel each get their own stub.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]
    static let defaultHost = "example-ref.supabase.co"

    static func setHandler(_ handler: Handler?, host: String = defaultHost) {
        lock.withLock { handlers[host] = handler }
    }
    static func requests(host: String = defaultHost) -> [URLRequest] { lock.withLock { recorded[host] ?? [] } }
    static func reset(host: String = defaultHost) { lock.withLock { recorded[host] = [] } }

    /// The chat suite's original API, on the default host.
    static var handler: Handler? {
        get { lock.withLock { handlers[defaultHost] } }
        set { setHandler(newValue) }
    }
    static var requests: [URLRequest] {
        get { requests() }
        set { lock.withLock { recorded[defaultHost] = newValue } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves the body into a stream; keep it readable for assertions.
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            captured.httpBody = data
        }
        let host = request.url?.host() ?? ""
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded[host, default: []].append(captured)
            return Self.handlers[host]
        }
        do {
            guard let handler else { throw URLError(.unknown) }
            let (status, data) = try handler(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("AI chat service", .serialized)
struct AIChatServiceTests {
    private let configuration = AIServiceConfiguration(
        functionURL: URL(string: "https://example-ref.supabase.co/functions/v1/car-assistant")!,
        publishableKey: "sb_publishable_test"
    )

    private func makeService(token: String? = nil) -> AIChatService {
        StubURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return AIChatService(configuration: configuration, session: URLSession(configuration: config), timeout: 5,
                             accessToken: { token })
    }

    private func respond(_ status: Int, _ json: String) {
        StubURLProtocol.handler = { _ in (status, Data(json.utf8)) }
    }

    @Test("POSTs JSON with the trimmed message to the function URL")
    func requestShape() async throws {
        let service = makeService()
        respond(200, #"{"answer":"Check the battery."}"#)
        _ = try await service.sendMessage("  My car engine cranks but won't start \n")

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://example-ref.supabase.co/functions/v1/car-assistant")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["message"] as? String == "My car engine cranks but won't start")
        #expect((json["history"] as? [Any])?.isEmpty == true)
        // "No specific car" is sent explicitly, not left out.
        #expect(json.keys.contains("vehicle") && json["vehicle"] is NSNull)
    }

    @Test("Earlier turns travel as history, oldest first, with roles")
    func historyInBody() async throws {
        let service = makeService()
        respond(200, #"{"answer":"ok"}"#)
        _ = try await service.sendMessage("Is it safe to drive?", history: [
            AIChatTurn(role: .user, content: "Brakes squeal"), AIChatTurn(role: .assistant, content: "Likely worn pads.")
        ])
        let body = try #require(StubURLProtocol.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let history = try #require(json["history"] as? [[String: String]])
        #expect(history == [["role": "user", "content": "Brakes squeal"], ["role": "assistant", "content": "Likely worn pads."]])
    }

    @Test("The chosen car travels as make, model, year, fuel and mileage only")
    func vehicleInBody() async throws {
        let service = makeService()
        respond(200, #"{"answer":"ok"}"#)
        _ = try await service.sendMessage("Hi", history: [], vehicle: AIChatVehicle(
            make: "Audi", model: "A4", year: 2021, fuelType: "diesel", mileageKm: 82_540
        ))
        let body = try #require(StubURLProtocol.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let vehicle = try #require(json["vehicle"] as? [String: Any])
        #expect(Set(vehicle.keys) == ["make", "model", "year", "fuelType", "mileageKm"])
        #expect(vehicle["make"] as? String == "Audi" && vehicle["mileageKm"] as? Int == 82_540)
    }

    @Test("History is capped by count and characters, dropping the oldest")
    func historyBounds() {
        let many = (0..<30).map { AIChatTurn(role: $0.isMultiple(of: 2) ? .user : .assistant, content: "m\($0)") }
        let bounded = AIChatService.bounded(many)
        #expect(bounded.count == AIChatService.historyLimit)
        #expect(bounded.last?.content == "m29")

        let long = (0..<10).map { _ in AIChatTurn(role: .user, content: String(repeating: "a", count: 4_000)) }
        #expect(AIChatService.bounded(long).count == 6)   // 6 × 4000 = 24 000
    }

    @Test("Sends the user's access token as a bearer token when there is one")
    func bearerToken() async throws {
        let service = makeService(token: "user-jwt")
        respond(200, #"{"answer":"ok"}"#)
        _ = try await service.sendMessage("Hi")
        #expect(StubURLProtocol.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt")
    }

    @Test("Decodes the answer")
    func decodesAnswer() async throws {
        let service = makeService()
        respond(200, #"{"answer":"There are several possible causes..."}"#)
        #expect(try await service.sendMessage("Why?") == "There are several possible causes...")
    }

    @Test("HTTP errors map to user-meaningful cases", arguments: [
        (400, AIError.invalidRequest), (401, .unauthorized), (403, .unauthorized), (429, .rateLimited),
        (500, .serverError(status: 500)), (502, .serverError(status: 502)), (503, .serverError(status: 503))
    ])
    func httpErrors(_ input: (status: Int, expected: AIError)) async {
        let service = makeService()
        respond(input.status, #"{"error":"nope"}"#)
        await #expect(throws: DomainError.ai(input.expected)) { try await service.sendMessage("Hello") }
    }

    @Test("A malformed or empty answer is an invalid response, not a crash", arguments: [
        #"{"reply":"wrong key"}"#, "not json", #"{"answer":"   "}"#
    ])
    func malformed(_ body: String) async {
        let service = makeService()
        respond(200, body)
        await #expect(throws: DomainError.ai(.structuredOutputInvalid)) { try await service.sendMessage("Hello") }
    }

    @Test("Network failures map to offline and timeout", arguments: [
        (URLError.Code.notConnectedToInternet, AIError.offline), (.timedOut, .timedOut)
    ])
    func networkFailures(_ input: (code: URLError.Code, expected: AIError)) async {
        let service = makeService()
        StubURLProtocol.handler = { _ in throw URLError(input.code) }
        await #expect(throws: DomainError.ai(input.expected)) { try await service.sendMessage("Hello") }
    }

    @Test("Empty and over-long messages never reach the network")
    func validation() async {
        let service = makeService()
        respond(200, #"{"answer":"x"}"#)
        await #expect(throws: DomainError.self) { try await service.sendMessage("   \n ") }
        await #expect(throws: DomainError.ai(.messageTooLong(maxCharacters: 4_000))) {
            try await service.sendMessage(String(repeating: "a", count: 4_001))
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}

/// A scripted `AIChatServiceProtocol`: records what it was asked and fails on demand.
actor ScriptedChatService: AIChatServiceProtocol {
    private(set) var received: [String] = []
    var failNext: DomainError?
    var delay: Duration = .zero

    func failOnce(with error: DomainError) { failNext = error }
    func setDelay(_ delay: Duration) { self.delay = delay }

    private(set) var histories: [[AIChatTurn]] = []
    private(set) var vehicles: [AIChatVehicle?] = []

    func sendMessage(_ message: String, history: [AIChatTurn], vehicle: AIChatVehicle?) async throws -> String {
        received.append(message)
        histories.append(history)
        vehicles.append(vehicle)
        if delay > .zero { try await Task.sleep(for: delay) }
        if let error = failNext { failNext = nil; throw error }
        return "Answer to: \(message)"
    }
}

@Suite("AI chat view model")
@MainActor
struct AIChatViewModelTests {
    private let clock = FixedClock()

    private func make(
        _ service: ScriptedChatService, dependencies existing: AppDependencies? = nil,
        conversationID: ConversationID? = nil, vehicleID: VehicleID? = nil, options: [AIChatViewModel.VehicleOption] = []
    ) -> (AIChatViewModel, AppDependencies) {
        let dependencies = existing ?? AppDependencies.testing(preferences: InMemoryPreferences(onboardingCompletedVersion: 1), clock: clock) {
            $0.ai = SupabaseAIProvider(service: service)
        }
        let app = AppModel(dependencies: dependencies)
        let viewModel = AIChatViewModel(
            conversationID: conversationID, vehicleID: vehicleID, vehicleOptions: options,
            askAI: AskAI(conversations: dependencies.conversations, provider: dependencies.ai,
                         buildContext: BuildAIContext(vehicles: dependencies.vehicles, odometer: dependencies.odometer,
                                                      fuel: dependencies.fuel, services: dependencies.services,
                                                      expenses: dependencies.expenses, clock: clock),
                         clock: clock),
            loadConversation: LoadConversation(conversations: dependencies.conversations),
            featureGate: app.featureGate, consumeQuota: {}, router: app.router, clock: clock
        )
        return (viewModel, dependencies)
    }

    private func settle(_ viewModel: AIChatViewModel) async throws {
        for _ in 0..<100 where viewModel.isStreaming { try await Task.sleep(for: .milliseconds(10)) }
    }

    @Test("Blank messages are not sent")
    func blankIsIgnored() async throws {
        let service = ScriptedChatService()
        let (viewModel, _) = make(service)
        viewModel.composerText = "   \n "
        #expect(!viewModel.canSend)
        viewModel.send()
        #expect(!viewModel.isStreaming)
        #expect(await service.received.isEmpty)
    }

    @Test("Sending shows loading, then the question and the answer in order")
    func successfulExchange() async throws {
        let service = ScriptedChatService()
        await service.setDelay(.milliseconds(100))
        let (viewModel, _) = make(service)
        viewModel.composerText = "  Engine cranks but won't start  "
        viewModel.send()
        #expect(viewModel.isStreaming)
        #expect(viewModel.composerText.isEmpty)

        try await settle(viewModel)
        #expect(!viewModel.isStreaming)
        #expect(viewModel.messages.map(\.role) == [.user, .assistant])
        #expect(viewModel.messages.first?.text == "Engine cranks but won't start")
        #expect(viewModel.messages.last?.text == "Answer to: Engine cranks but won't start")
        #expect(viewModel.errorMessage == nil)
        // Only the current message goes to the backend.
        #expect(await service.received == ["Engine cranks but won't start"])
    }

    @Test("A failed answer can be retried without duplicating the question")
    func retryDoesNotDuplicate() async throws {
        let service = ScriptedChatService()
        await service.failOnce(with: .ai(.serverError(status: 502)))
        let (viewModel, dependencies) = make(service)
        viewModel.composerText = "Brakes squeal"
        viewModel.send()
        try await settle(viewModel)

        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.failedQuestion == "Brakes squeal")
        #expect(viewModel.messages.map(\.role) == [.user])

        viewModel.retry()
        try await settle(viewModel)
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.failedQuestion == nil)
        #expect(viewModel.messages.map(\.role) == [.user, .assistant])
        #expect(await service.received == ["Brakes squeal", "Brakes squeal"])

        // Persisted once, too.
        let summary = try #require(try await dependencies.conversations.summaries(vehicleID: nil).first)
        let stored = try #require(try await dependencies.conversations.conversation(id: summary.id))
        #expect(stored.messages.filter { $0.role == .user }.count == 1)
    }

    @Test("A follow-up carries the earlier question and answer")
    func followUpCarriesHistory() async throws {
        let service = ScriptedChatService()
        let (viewModel, _) = make(service)
        viewModel.composerText = "Brakes squeal"
        viewModel.send()
        try await settle(viewModel)
        viewModel.composerText = "Is it safe?"
        viewModel.send()
        try await settle(viewModel)

        let histories = await service.histories
        #expect(histories.first == [])
        #expect(histories.last == [
            AIChatTurn(role: .user, content: "Brakes squeal"),
            AIChatTurn(role: .assistant, content: "Answer to: Brakes squeal")
        ])
    }

    private func audi(_ d: AppDependencies) async throws -> VehicleID {
        try await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock)(
            VehicleDraft(brand: "Audi", model: "A4", year: 2021, fuelType: .diesel, initialOdometer: Odometer(kilometers: 82_540)),
            vehicleLimit: nil
        ).vehicle.id
    }

    @Test("The chosen garage car is sent with every question; 'Another car' sends none")
    func chosenVehicleIsSent() async throws {
        let service = ScriptedChatService()
        let (first, dependencies) = make(service)
        let id = try await audi(dependencies)

        let (viewModel, _) = make(service, dependencies: dependencies, vehicleID: id, options: [.init(id: id, name: "Audi A4")])
        #expect(viewModel.vehicleTitle == "Audi A4" && viewModel.canChangeVehicle)
        viewModel.composerText = "Brakes squeal"
        viewModel.send()
        try await settle(viewModel)
        #expect(!viewModel.canChangeVehicle)

        _ = first
        let (general, _) = make(service, dependencies: dependencies, vehicleID: id, options: [.init(id: id, name: "Audi A4")])
        general.vehicleID = nil
        #expect(general.vehicleTitle == "Another car")
        general.composerText = "What does ABS mean?"
        general.send()
        try await settle(general)

        let vehicles = await service.vehicles
        #expect(vehicles.first == AIChatVehicle(make: "Audi", model: "A4", year: 2021, fuelType: "diesel", mileageKm: 82_540))
        #expect(vehicles.last == .some(nil))
    }

    @Test("A reopened conversation keeps the car it was started with")
    func reopenedConversationKeepsVehicle() async throws {
        let service = ScriptedChatService()
        let (starter, dependencies) = make(service)
        let id = try await audi(dependencies)
        _ = starter
        let (viewModel, _) = make(service, dependencies: dependencies, vehicleID: id, options: [.init(id: id, name: "Audi A4")])
        viewModel.composerText = "Brakes squeal"
        viewModel.send()
        try await settle(viewModel)

        // Reopened while "Another car" is the current selection elsewhere in the app.
        let conversation = try #require(try await dependencies.conversations.summaries(vehicleID: nil).first)
        let (reopened, _) = make(service, dependencies: dependencies, conversationID: conversation.id,
                                 vehicleID: nil, options: [.init(id: id, name: "Audi A4")])
        await reopened.load()
        #expect(reopened.vehicleTitle == "Audi A4" && !reopened.canChangeVehicle)
        reopened.composerText = "Is it safe?"
        reopened.send()
        try await settle(reopened)
        #expect(await service.vehicles.last??.model == "A4")
    }

    @Test("An over-long message is refused before sending")
    func tooLong() async throws {
        let service = ScriptedChatService()
        let (viewModel, _) = make(service)
        viewModel.composerText = String(repeating: "a", count: 4_001)
        #expect(!viewModel.canSend)
        viewModel.send()
        #expect(viewModel.errorMessage != nil)
        #expect(await service.received.isEmpty)
    }
}
