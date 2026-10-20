import XCTest
@testable import BarcodeDeck

final class ReadVerifierTests: XCTestCase {

    func testConfirmsAfterRequiredConsecutiveIdenticalReads() {
        var verifier = ReadVerifier(requiredReads: 3)
        XCTAssertFalse(verifier.onRead(value: "123", symbology: "ITF"))
        XCTAssertFalse(verifier.onRead(value: "123", symbology: "ITF"))
        XCTAssertTrue(verifier.onRead(value: "123", symbology: "ITF"))
    }

    func testDifferentReadResetsTheStreakToTheNewValue() {
        var verifier = ReadVerifier(requiredReads: 3)
        XCTAssertFalse(verifier.onRead(value: "123", symbology: "ITF"))
        XCTAssertFalse(verifier.onRead(value: "123", symbology: "ITF"))
        XCTAssertFalse(verifier.onRead(value: "456", symbology: "ITF"))  // single-pass misread
        XCTAssertFalse(verifier.onRead(value: "456", symbology: "ITF"))
        XCTAssertTrue(verifier.onRead(value: "456", symbology: "ITF"))
    }

    func testSymbologyIsPartOfTheReadIdentity() {
        var verifier = ReadVerifier(requiredReads: 2)
        XCTAssertFalse(verifier.onRead(value: "123", symbology: nil))
        XCTAssertFalse(verifier.onRead(value: "123", symbology: "ITF"))
        XCTAssertTrue(verifier.onRead(value: "123", symbology: "ITF"))
    }

    func testCountTracksTheCurrentStreak() {
        var verifier = ReadVerifier(requiredReads: 3)
        _ = verifier.onRead(value: "1", symbology: nil)
        XCTAssertEqual(1, verifier.count)
        _ = verifier.onRead(value: "1", symbology: nil)
        XCTAssertEqual(2, verifier.count)
        _ = verifier.onRead(value: "2", symbology: nil)
        XCTAssertEqual(1, verifier.count)
    }
}
