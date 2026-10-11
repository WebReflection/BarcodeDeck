import Foundation
import Testing
@testable import BarcodeDeck

/// Storage canonicalization: valid 12-digit UPC-A values are stored as their
/// 0-padded EAN-13 equivalent, so decks match across platforms and imports
/// de-duplicate. (Vision already reports scanned UPC-A padded; Android's ML
/// Kit does not, hence the normalization on both platforms.)
@Suite struct CanonicalStorageTests {

    private let upca = "400236325890"      // 12 digits, valid check digit
    private let padded = "0400236325890"   // its EAN-13 twin

    @Test func padsScannedUpcaValuesToEan13() {
        #expect(BarcodeValidation.canonicalize(upca, "UPC-A") == (padded, "EAN-13"))
    }

    @Test func padsAutoDetectedUpcaValuesToEan13() {
        #expect(BarcodeValidation.canonicalize(upca, nil) == (padded, "EAN-13"))
    }

    @Test func leavesExplicitCode128ChoiceUntouched() {
        #expect(BarcodeValidation.canonicalize(upca, "Code 128") == (upca, "Code 128"))
    }

    @Test func leavesNonUpcaValuesUntouched() {
        #expect(BarcodeValidation.canonicalize("5901234123457", "EAN-13") == ("5901234123457", "EAN-13"))
        #expect(BarcodeValidation.canonicalize("GMMNDR78E17Q", nil) == ("GMMNDR78E17Q", nil))
    }

    @Test func doesNotPadValuesWithBrokenCheckDigit() {
        #expect(BarcodeValidation.canonicalize("400236325891", "UPC-A") == ("400236325891", "UPC-A"))
    }

    @Test func canonicalKeyMatchesBothSpellingsOfSameCard() {
        #expect(BarcodeValidation.canonicalKey(upca) == BarcodeValidation.canonicalKey(padded))
        #expect(BarcodeValidation.canonicalKey(upca) == padded)
        #expect(BarcodeValidation.canonicalKey("GMMNDR78E17Q") == "GMMNDR78E17Q")
    }

    private func exportWithCard(name: String, value: String, symbology: String?) -> CardTransfer.Export {
        CardTransfer.Export(
            exportedAt: Date(timeIntervalSince1970: 0),
            cards: [CardTransfer.CardData(
                name: name, description: nil,
                barcodeValue: value, symbology: symbology,
                createdAt: Date(timeIntervalSince1970: 0)
            )]
        )
    }

    @Test func importTreatsUpcaValueAndPaddedTwinAsSameCard() {
        let plan = CardTransfer.planImport(
            exportWithCard(name: "Same card", value: padded, symbology: "EAN-13"),
            existingValues: [upca]
        )
        #expect(plan.toImport.isEmpty)
        #expect(plan.skipped == 1)
    }

    @Test func importStoresUpcaValuesPaddedAsEan13() {
        let plan = CardTransfer.planImport(
            exportWithCard(name: "Android scan", value: upca, symbology: "UPC-A"),
            existingValues: []
        )
        #expect(plan.toImport.count == 1)
        #expect(plan.toImport[0].barcodeValue == padded)
        #expect(plan.toImport[0].symbology == "EAN-13")
    }

    @Test func importKeepsExplicitCode128Spelling() {
        let plan = CardTransfer.planImport(
            exportWithCard(name: "Deliberate", value: upca, symbology: "Code 128"),
            existingValues: []
        )
        #expect(plan.toImport.count == 1)
        #expect(plan.toImport[0].barcodeValue == upca)
        #expect(plan.toImport[0].symbology == "Code 128")
    }
}
