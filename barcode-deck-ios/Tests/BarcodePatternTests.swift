import XCTest
@testable import BarcodeDeck

final class BarcodePatternTests: XCTestCase {

    private func bools(_ s: String) -> [Bool] { s.map { $0 == "1" } }

    // MARK: - ITF

    func testITF14Has135ModulesAndCorrectGuards() throws {
        let m = try XCTUnwrap(BarcodePattern.itfModules("12345678901231"))
        XCTAssertEqual(135, m.count)
        XCTAssertEqual(bools("1010"), Array(m[0..<4]))
        XCTAssertEqual(bools("11101"), Array(m[130..<135]))
    }

    func testITFRejectsOddDigitCountAndNonDigits() {
        XCTAssertNil(BarcodePattern.itfModules("12345"))
        XCTAssertNil(BarcodePattern.itfModules("1234A670"))
    }

    func testITF14WithBadCheckDigitRejected() {
        XCTAssertNil(BarcodePattern.itfModules("12345678901238"))
    }

    func testPlainITFEncodesWithoutChecksumValidation() {
        XCTAssertNotNil(BarcodePattern.itfModules("12345671"))
    }

    func testScannedITFRoutesToTheITFRenderer() throws {
        let result = BarcodePattern.presentationBarcode(value: "12345678901231", symbology: "ITF-14")
        guard case .linear(let modules, let quiet, let nominal) = result else {
            return XCTFail("expected linear, got \(String(describing: result))")
        }
        XCTAssertEqual(BarcodePattern.itfQuietModules, quiet)
        XCTAssertEqual(BarcodePattern.itfNominalModuleWidthMM, nominal, accuracy: 1e-9)
        XCTAssertEqual(135, modules.count)
    }

    // MARK: - EAN-8

    func testEAN8Has67ModulesAndCorrectGuards() throws {
        let m = try XCTUnwrap(BarcodePattern.ean8Modules("24050012"))
        XCTAssertEqual(67, m.count)
        XCTAssertEqual(bools("101"), Array(m[0..<3]))
        XCTAssertEqual(bools("01010"), Array(m[31..<36]))
        XCTAssertEqual(bools("101"), Array(m[64..<67]))
        // First digit 2 (L code), last digit 2 (R code).
        XCTAssertEqual(bools("0010011"), Array(m[3..<10]))
        XCTAssertEqual(bools("1101100"), Array(m[57..<64]))
    }

    func testEAN8BadCheckDigitRejected() {
        XCTAssertNil(BarcodePattern.ean8Modules("24050018"))
    }

    // MARK: - QR

    func testQRMatrixIsSquare() throws {
        let (image, moduleCount) = try XCTUnwrap(BarcodePattern.qrCode(for: "HELLO"))
        XCTAssertGreaterThanOrEqual(moduleCount, 21)
        XCTAssertEqual(moduleCount, image.width)
        XCTAssertEqual(image.width, image.height)
    }

    func testQRRejectsEmptyAndOversizedValues() {
        XCTAssertNil(BarcodePattern.qrCode(for: ""))
        XCTAssertNil(BarcodePattern.qrCode(for: String(repeating: "x", count: 5000)))
    }

    func testQRCardStaysQREvenWhenTheValueLooksLikeEAN13() {
        let result = BarcodePattern.presentationBarcode(
            value: "4006381333931", symbology: "QR Code")
        guard case .qr = result else {
            return XCTFail("expected qr, got \(String(describing: result))")
        }
    }

    // MARK: - Fallbacks for scanned-but-unencodable types

    func testScannedCodabarFallsBackToCode128Bars() throws {
        let result = BarcodePattern.presentationBarcode(value: "A123456789", symbology: "Codabar")
        guard case .linear(let modules, _, _) = result else {
            return XCTFail("expected linear, got \(String(describing: result))")
        }
        XCTAssertEqual(145, modules.count)
    }

    func testScannedEAN8RendersAsEAN8() throws {
        let result = BarcodePattern.presentationBarcode(value: "24050012", symbology: "EAN-8")
        guard case .linear(_, let quiet, let nominal) = result else {
            return XCTFail("expected linear, got \(String(describing: result))")
        }
        XCTAssertEqual(BarcodePattern.ean8QuietModules, quiet)
        XCTAssertEqual(BarcodePattern.nominalModuleWidthMM, nominal, accuracy: 1e-9)
    }

    func testEAN8WithBadCheckDigitFallsBackToCode128() {
        XCTAssertNotNil(BarcodePattern.presentationBarcode(value: "24050018", symbology: "EAN-8"))
    }

    // MARK: - HTTP URL detection (presentation "open link" button)

    func testHTTPURLDetected() {
        XCTAssertEqual(
            "https://example.com",
            BarcodeValidation.asHttpURL("https://example.com")?.absoluteString
        )
    }

    func testHTTPURLDetectedCaseInsensitivelyAfterTrimming() {
        XCTAssertEqual(
            "HTTP://example.com/x",
            BarcodeValidation.asHttpURL("  HTTP://example.com/x ")?.absoluteString
        )
    }

    func testNonHTTPSchemesNeverOpen() {
        XCTAssertNil(BarcodeValidation.asHttpURL("ftp://example.com"))
        XCTAssertNil(BarcodeValidation.asHttpURL("javascript:alert(1)"))
        XCTAssertNil(BarcodeValidation.asHttpURL("mailto:a@b.c"))
        XCTAssertNil(BarcodeValidation.asHttpURL("intent://x"))
    }

    func testPlainTextIsNotAURL() {
        XCTAssertNil(BarcodeValidation.asHttpURL("https.example.com"))
    }

    // MARK: - Binary (base64) payloads

    func testBase64PayloadEncodesAndRoundTrips() throws {
        let bytes = Data([0x00, 0x01, 0x02, 0xFF, 0xFE, 0x41])
        let value = BarcodePattern.base64Prefix + bytes.base64EncodedString()
        XCTAssertNotNil(BarcodePattern.qrCode(for: value))
        XCTAssertEqual(try XCTUnwrap(BarcodePattern.decodeBase64Payload(value)), bytes)
    }

    func testMalformedBase64Rejected() {
        XCTAssertNil(BarcodePattern.qrCode(for: "base64,%%%"))
        XCTAssertNil(BarcodePattern.decodeBase64Payload("base64,%%%"))
        XCTAssertNil(BarcodePattern.decodeBase64Payload("base64,"))
        XCTAssertNil(BarcodePattern.decodeBase64Payload("just text"))
        XCTAssertEqual(
            "“base64,” values must continue with valid base64.",
            BarcodeValidation.manualTypeError(type: "QR Code", value: "base64,%%%")
        )
    }

    func testValidBase64PayloadPassesManualValidation() {
        XCTAssertNil(
            BarcodeValidation.manualTypeError(
                type: "QR Code", value: BarcodePattern.base64Prefix + "AAECAw=="
            )
        )
    }

    // MARK: - Manual entry

    func testManualITFRejectsOddDigits() {
        XCTAssertEqual(
            "ITF needs an even number of digits (currently 5).",
            BarcodeValidation.manualTypeError(type: "ITF", value: "12345")
        )
    }

    func testManualITFRejectsLetters() {
        XCTAssertEqual(
            "ITF uses digits only.",
            BarcodeValidation.manualTypeError(type: "ITF", value: "1234A678")
        )
    }

    func testManualITF14WithBadCheckDigitIsAHardError() {
        let error = BarcodeValidation.manualTypeError(type: "ITF", value: "12345678901238")
        XCTAssertNotNil(error)
        XCTAssertTrue(error?.contains("check digit") == true)
    }

    func testManualITFAcceptsEvenDigits() {
        XCTAssertNil(BarcodeValidation.manualTypeError(type: "ITF", value: "12345670"))
    }

    func testManualQRCodeAcceptsAnything() {
        XCTAssertNil(
            BarcodeValidation.manualTypeError(type: "QR Code", value: "https://example.com/🎉")
        )
    }

    func testAutoResolves14DigitsToITF14() {
        XCTAssertEqual("ITF-14", BarcodeValidation.resolveAutoSymbology("12345678901231"))
    }

    func testAutoResolves13DigitsToEAN13() {
        XCTAssertEqual("EAN-13", BarcodeValidation.resolveAutoSymbology("5901234123457"))
    }
}
