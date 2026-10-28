import Testing
import Foundation
@testable import CarManager

@Suite("Receipt reading via car-receipt", .serialized)
struct CarReceiptServiceTests {
    private let host = "receipt-ref.supabase.co"
    private let clock = FixedClock()      // 2025-10-09 UTC

    private func makeService() -> CarReceiptService {
        StubURLProtocol.reset(host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return CarReceiptService(
            configuration: AIServiceConfiguration(functionURL: URL(string: "https://\(host)/functions/v1/car-assistant")!,
                                                  publishableKey: "sb_publishable_test"),
            session: URLSession(configuration: config), timeout: 5
        )
    }

    private func respond(_ status: Int, _ body: String) {
        StubURLProtocol.setHandler({ _ in (status, Data(body.utf8)) }, host: host)
    }

    private func analyze(_ service: CarReceiptService, target: CurrencyCode = .eur) async throws -> ReceiptDraft {
        let response = try await service.analyze(image: Data([1, 2]), ocrText: "ORLEN", targetCurrency: target,
                                                 vehicle: nil, language: "en", today: clock.now, calendar: clock.calendar)
        return try CarReceiptService.draft(from: response, target: target, calendar: clock.calendar)
    }

    /// A PLN fuel receipt with a coffee on it, converted to EUR at the ECB rate.
    private let plnFuel = #"""
    {"status":"ok","warnings":["foreign_currency"],"receipt":{
      "kind":"fuel",
      "merchant":{"value":"ORLEN Stacja 512","confidence":0.9},
      "date":{"value":"2025-10-08","confidence":0.95},
      "original":{"currency":"PLN","currencyConfidence":0.99,"total":322.6,"totalConfidence":0.97,
                  "fuelAmount":313.6,"pricePerUnit":6.49,"serviceItems":[]},
      "inTargetCurrency":{"currency":"EUR","total":74.6,"fuelAmount":72.52,"pricePerUnit":1.501,"serviceItems":[]},
      "conversion":{"status":"converted","from":"PLN","to":"EUR","rate":0.23124,"rateDate":"2025-10-08","source":"ECB (frankfurter.app)"},
      "fuel":{"quantity":48.32,"unit":"L","fuelType":"diesel","confidence":0.9},
      "expenseCategory":"fuel","odometerKm":null}}
    """#

    @Test("Posts the photo, device OCR, the car's currency and today's date to car-receipt")
    func requestShape() async throws {
        let service = makeService()
        respond(200, plnFuel)
        _ = try await analyze(service)
        let request = try #require(StubURLProtocol.requests(host: host).first)
        #expect(request.url?.absoluteString == "https://\(host)/functions/v1/car-receipt")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["targetCurrency"] as? String == "EUR")
        #expect(json["ocrText"] as? String == "ORLEN")
        #expect(json["today"] as? String == "2025-10-09")
        #expect((json["images"] as? [String])?.count == 1)
    }

    @Test("Converted amounts, litres and the conversion record")
    func convertedFields() async throws {
        let service = makeService()
        respond(200, plnFuel)
        let draft = try await analyze(service)
        #expect(draft.suggestedRecordKind == .fuel)
        #expect(draft.total.value == Money(Decimal(string: "72.52")!, .eur))        // fuel line, not the coffee
        #expect(draft.originalTotal == Money(Decimal(string: "313.60")!, CurrencyCode("PLN")))
        #expect(draft.conversion?.status == .converted)
        #expect(draft.conversion?.rate == Decimal(string: "0.231240"))
        #expect(draft.fuelVolume.value?.liters == 48.32)
        #expect(draft.vendor.value == "ORLEN Stacja 512")
        #expect(clock.calendar.component(.day, from: try #require(draft.date.value)) == 8)
        #expect(draft.warnings.contains(.foreignCurrency))
        // Still unreviewed: nothing can be saved from this as-is.
        #expect(!draft.total.isAccepted && !draft.date.isAccepted)
        #expect(!draft.hasRequiredAcceptedFields)
    }

    @Test("Without a rate the total stays empty for the user to enter; the printed amount is kept")
    func rateUnavailable() async throws {
        let service = makeService()
        respond(200, #"""
        {"status":"ok","warnings":["foreign_currency"],"receipt":{"kind":"expense",
          "merchant":{"value":"Parking Kyiv","confidence":0.8},"date":{"value":"2025-10-01","confidence":0.9},
          "original":{"currency":"UAH","currencyConfidence":0.9,"total":120,"totalConfidence":0.9,"fuelAmount":null,"pricePerUnit":null,"serviceItems":[]},
          "inTargetCurrency":{"currency":"EUR","total":null,"fuelAmount":null,"pricePerUnit":null,"serviceItems":[]},
          "conversion":{"status":"rate_unavailable","from":"UAH","to":"EUR"},
          "fuel":null,"expenseCategory":"parking","odometerKm":null}}
        """#)
        let draft = try await analyze(service)
        #expect(draft.total.value == nil)
        #expect(draft.conversion?.status == .rateUnavailable)
        #expect(draft.originalTotal?.currency == CurrencyCode("UAH"))
        #expect(draft.expenseCategory.value == .parking)
    }

    @Test("A workshop invoice brings its jobs and the printed mileage")
    func serviceInvoice() async throws {
        let service = makeService()
        respond(200, #"""
        {"status":"ok","warnings":[],"receipt":{"kind":"service",
          "merchant":{"value":"AutoSerwis","confidence":0.9},"date":{"value":"2025-09-20","confidence":0.9},
          "original":{"currency":"EUR","currencyConfidence":1,"total":410,"totalConfidence":0.95,"fuelAmount":null,"pricePerUnit":null,
                      "serviceItems":[{"name":"Front brake pads","type":"brakes","price":290},{"name":"Labour","type":"other","price":120}]},
          "inTargetCurrency":{"currency":"EUR","total":410,"fuelAmount":null,"pricePerUnit":null,
                      "serviceItems":[{"name":"Front brake pads","type":"brakes","price":290},{"name":"Labour","type":"other","price":120}]},
          "conversion":{"status":"same_currency"},
          "fuel":null,"expenseCategory":"maintenance","odometerKm":{"value":32880,"confidence":0.8}}}
        """#)
        let draft = try await analyze(service)
        #expect(draft.suggestedRecordKind == .service)
        #expect(draft.serviceItems.map(\.type) == [.brakes, .other])
        #expect(draft.serviceItems.first?.partCost == Money(290, .eur))
        #expect(draft.odometer.value?.kilometers == 32_880)
        #expect(draft.conversion?.status == .sameCurrency)
    }

    /// The answer the deployed function actually gave for a PLN Orlen receipt: litres in the
    /// fuel-amount slot, the coffee as a "service item", the address in the merchant name.
    @Test("Real-world misreads are repaired: litres as amount, coffee as a job, address in the name")
    func liveMisreads() async throws {
        let service = makeService()
        respond(200, #"""
        {"status":"ok","receipt":{"kind":"fuel","merchant":{"value":"ORLEN S.A. Stacja Paliw nr 512 ul. Krakowska 10, Warszawa","confidence":0.9},"date":{"value":"2025-10-08","confidence":0.9},"original":{"currency":"PLN","currencyConfidence":0.9,"total":322.6,"totalConfidence":0.95,"fuelAmount":48.32,"pricePerUnit":6.49,"serviceItems":[{"name":"KAWA DUZA","type":"other","price":9}]},"inTargetCurrency":{"currency":"EUR","total":75.89,"fuelAmount":11.37,"pricePerUnit":1.527,"serviceItems":[{"name":"KAWA DUZA","type":"other","price":2.12}]},"conversion":{"status":"converted","from":"PLN","to":"EUR","rate":0.23525,"rateDate":"2025-10-08","source":"ECB (frankfurter.app)"},"fuel":{"quantity":48.32,"unit":"L","fuelType":"diesel","confidence":0.95},"expenseCategory":"fuel","odometerKm":null},"warnings":["math_mismatch","foreign_currency"]}
        """#)
        let draft = try await analyze(service)
        #expect(draft.originalTotal == Money(Decimal(string: "313.60")!, CurrencyCode("PLN")))  // 48.32 × 6.49
        #expect(draft.total.value == Money(Decimal(string: "73.77")!, .eur))                    // at 0.23525
        #expect(draft.serviceItems.isEmpty)
        #expect(draft.vendor.value == "ORLEN S.A. Stacja Paliw nr 512")
        #expect(!draft.warnings.contains(.mathMismatch))   // repaired, so not shown
    }

    @Test("A photo of something else is refused, not turned into a record")
    func notAReceipt() async throws {
        let service = makeService()
        respond(200, #"{"status":"not_a_receipt","receipt":null,"warnings":[]}"#)
        await #expect(throws: DomainError.ai(.notAReceipt)) { _ = try await analyze(service) }
    }

    @MainActor
    @Test("Offline or a failing server falls back to reading on the device; 'not a receipt' does not")
    func fallback() async throws {
        let d = makeDependencies(clock: clock)
        let car = try await CreateVehicle(vehicles: d.vehicles, odometer: d.odometer, reminders: d.reminders, clock: clock)(
            VehicleDraft(brand: "Audi", model: "A4"), vehicleLimit: nil
        ).vehicle.id
        let provider = HybridVisionAnalysisProvider(vehicles: d.vehicles, odometer: d.odometer, remote: nil,
                                                    receipts: makeService(), clock: clock, language: "en")

        respond(503, #"{"error":"down"}"#)
        let result = try await provider.analyze(.receipt(image: Data([1]), ocrText: "Car Wash\nTOTAL 18,00 €\n08.10.2025", vehicleID: car))
        guard case .receipt(let draft) = result else { Issue.record("expected a receipt"); return }
        #expect(draft.total.value?.amount == 18)
        #expect(draft.warnings.contains(.readOnDevice))

        respond(200, #"{"status":"not_a_receipt","receipt":null,"warnings":[]}"#)
        await #expect(throws: DomainError.ai(.notAReceipt)) {
            _ = try await provider.analyze(.receipt(image: Data([1]), ocrText: "TOTAL 5,00", vehicleID: car))
        }
    }
}
