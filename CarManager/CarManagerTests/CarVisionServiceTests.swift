import Testing
import Foundation
@testable import CarManager

@Suite("Car vision service", .serialized)
struct CarVisionServiceTests {
    private let configuration = AIServiceConfiguration(
        functionURL: URL(string: "https://vision-ref.supabase.co/functions/v1/car-assistant")!,
        publishableKey: "sb_publishable_test"
    )

    private func makeService() -> CarVisionService {
        StubURLProtocol.reset(host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return CarVisionService(configuration: configuration, session: URLSession(configuration: config), timeout: 5)
    }

    private let host = "vision-ref.supabase.co"

    private func respond(_ status: Int, _ json: String) {
        StubURLProtocol.setHandler({ _ in (status, Data(json.utf8)) }, host: host)
    }

    @Test("Posts kind, base64 images, car facts, currency and language to car-vision")
    func requestShape() async throws {
        let service = makeService()
        respond(200, #"{"summary":"ok","findings":[]}"#)
        _ = try await service.analyze(
            kind: .damage, images: [Data([1, 2, 3])],
            vehicle: AIChatVehicle(make: "Porsche", model: "Macan", year: 2023, fuelType: "diesel", mileageKm: 30_200),
            currency: CurrencyCode("PLN"), language: "ru"
        )
        let request = try #require(StubURLProtocol.requests(host: host).first)
        #expect(request.url?.absoluteString == "https://vision-ref.supabase.co/functions/v1/car-vision")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "apikey") == "sb_publishable_test")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["kind"] as? String == "damage")
        #expect(json["images"] as? [String] == [Data([1, 2, 3]).base64EncodedString()])
        #expect(json["currency"] as? String == "PLN")
        #expect(json["language"] as? String == "ru")
        #expect((json["vehicle"] as? [String: Any])?["model"] as? String == "Macan")
    }

    @Test("Dashboard findings map to the domain; unknown values stay cautious")
    func dashboardMapping() async throws {
        let service = makeService()
        respond(200, #"""
        {"summary":"2 lights","findings":[
          {"warningName":"Oil pressure","likelyCauses":["Low oil"],"severity":"stopDriving","recommendedAction":"Stop now","drivingSafety":"doNotDrive","confidence":0.9},
          {"warningName":"Mystery","likelyCauses":[],"severity":"weird","recommendedAction":"","drivingSafety":"fine","confidence":7}
        ]}
        """#)
        let response = try await service.analyze(kind: .dashboard, images: [Data([1])], vehicle: nil, currency: .eur, language: "en")
        let findings = CarVisionService.dashboardFindings(response)
        #expect(findings.count == 2)
        #expect(findings[0].severity == .stopDriving && findings[0].drivingSafety == .doNotDrive)
        #expect(findings[1].severity == .soon)              // unknown severity → not "informational"
        #expect(findings[1].drivingSafety == .unknown)      // never "safe" by default
        #expect(findings[1].confidence == 1)
        #expect(response.summary == "2 lights")
    }

    @Test("Damage findings keep a cost RANGE only when it is a valid one")
    func damageMapping() async throws {
        let service = makeService()
        respond(200, #"""
        {"summary":"Rear bumper","findings":[
          {"damageType":"Scratch","severity":"moderate","suggestedRepair":"Repaint","cosmeticRepairPossible":false,"estimatedCost":{"low":200,"high":450,"currency":"EUR","confidence":0.6}},
          {"damageType":"Dent","severity":"cosmetic","suggestedRepair":"PDR","cosmeticRepairPossible":true,"estimatedCost":{"low":300,"high":100,"currency":"EUR","confidence":0.5}},
          {"damageType":"","severity":"unknown","suggestedRepair":"","cosmeticRepairPossible":null,"estimatedCost":null}
        ]}
        """#)
        let response = try await service.analyze(kind: .damage, images: [Data([1])], vehicle: nil, currency: .eur, language: "en")
        let findings = CarVisionService.damageFindings(response, currency: .eur)
        #expect(findings.count == 2)                        // nameless finding dropped
        #expect(findings[0].estimatedCost?.low == Money(200, .eur))
        #expect(findings[0].estimatedCost?.high == Money(450, .eur))
        #expect(findings[1].estimatedCost == nil)           // low > high is rejected
        #expect(findings[1].cosmeticRepairPossible == true)
    }

    @Test("HTTP and network errors map like the chat's", arguments: [
        (429, DomainError.ai(.rateLimited)), (502, .ai(.serverError(status: 502))), (401, .ai(.unauthorized))
    ])
    func errors(_ input: (status: Int, expected: DomainError)) async {
        let service = makeService()
        respond(input.status, #"{"error":"x"}"#)
        await #expect(throws: input.expected) {
            _ = try await service.analyze(kind: .dashboard, images: [Data([1])], vehicle: nil, currency: .eur, language: "en")
        }
    }

    @Test("A malformed body is an invalid response")
    func malformed() async {
        let service = makeService()
        respond(200, "not json")
        await #expect(throws: DomainError.ai(.structuredOutputInvalid)) {
            _ = try await service.analyze(kind: .dashboard, images: [Data([1])], vehicle: nil, currency: .eur, language: "en")
        }
    }
}
