import Testing
import Foundation
@testable import CarManager

@Suite("Receipt text parser")
struct ReceiptTextParserTests {
    private let clock = FixedClock()      // 2025-10-09 UTC

    private func parse(_ text: String) -> ReceiptDraft {
        ReceiptTextParser.parse(text, fallbackCurrency: .sek, now: clock.now, calendar: clock.calendar)
    }

    @Test("A fuel receipt yields station, total, date and litres — all unaccepted")
    func fuelReceipt() {
        let draft = parse("""
        ORLEN Stacja nr 512
        ul. Krakowska 10
        ON Verva 48,32 L x 6,49
        SUMA PLN 313,60
        2025-10-08 14:22
        """)
        #expect(draft.suggestedRecordKind == .fuel)
        #expect(draft.vendor.value == "ORLEN Stacja nr 512")
        #expect(draft.total.value == Money(Decimal(string: "313.60")!, CurrencyCode("PLN")))
        #expect(draft.fuelVolume.value?.liters == 48.32)
        #expect(clock.calendar.component(.day, from: draft.date.value!) == 8)
        #expect(!draft.total.isAccepted && !draft.date.isAccepted && !draft.vendor.isAccepted)
    }

    @Test("The TOTAL line wins over larger numbers elsewhere")
    func totalLine() {
        let draft = parse("Car Wash Deluxe\nCard no 1234,56\nTOTAL 18,00 €\n09.10.2025")
        #expect(draft.total.value?.amount == 18)
        #expect(draft.total.value?.currency == .eur)
        #expect(draft.expenseCategory.value == .carWash)
        #expect(draft.total.confidence > 0.8)
    }

    @Test("Without a total keyword the largest amount is a low-confidence guess")
    func fallbackTotal() {
        let draft = parse("Parking Centrum\n2,50\n12,00")
        #expect(draft.total.value?.amount == 12)
        #expect(draft.total.confidence < 0.5)
        #expect(draft.total.value?.currency == .sek)   // nothing on the receipt says otherwise
    }

    @Test("Future and impossible dates are ignored")
    func dates() {
        #expect(parse("Shop\nTOTAL 5,00\n31.02.2025").date.value == nil)
        #expect(parse("Shop\nTOTAL 5,00\n01.01.2030").date.value == nil)
    }

    @Test("Thousands separators are read correctly")
    func thousands() {
        #expect(ReceiptTextParser.amounts(in: "Razem 1 284,50") == [Decimal(string: "1284.50")!])
        #expect(ReceiptTextParser.amounts(in: "Total 1.284,50") == [Decimal(string: "1284.50")!])
    }
}
