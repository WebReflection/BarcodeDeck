import XCTest

/// One-off helper for App Store screenshots: seeds the simulator's store
/// with a small demo deck through the real UI, then leaves it there.
///
/// Run with:
///   xcodebuild test-without-building \
///     -only-testing:BarcodeDeckUITests/ScreenshotSeedTests \
///     -destination 'platform=iOS Simulator,name=…'
///
/// Unlike the smoke tests there is NO --debug-reset-store here: the seeded
/// cards persist, so the plain launch afterwards shows a populated list.
final class ScreenshotSeedTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--debug-skip-scanner"]
        app.launch()
    }

    private func field(_ placeholder: String) -> XCUIElement {
        app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", placeholder)
        ).firstMatch
    }

    private func addCard(name: String, value: String) {
        let addButton = app.buttons["Add card"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "add button missing")
        addButton.tap()

        let nameField = field("Name")
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "name field missing")
        nameField.tap()
        nameField.typeText(name)

        let valueField = field("Barcode value")
        XCTAssertTrue(valueField.waitForExistence(timeout: 5), "value field missing")
        valueField.tap()
        valueField.typeText(value)

        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Save missing")
        XCTAssertTrue(save.isEnabled, "Save is disabled")
        save.tap()
        XCTAssertTrue(app.buttons["Add card"].waitForExistence(timeout: 5), "sheet did not close")
    }

    func testSeedDemoDeck() throws {
        // Newest-first ordering: the last added card tops the list.
        addCard(name: "Codice Fiscale", value: "GMMNDR78E17A271Q")
        addCard(name: "Corner Pharmacy", value: "4006381333931")
        addCard(name: "Green Grocery", value: "A123456789")

        XCTAssertTrue(app.staticTexts["Green Grocery"].waitForExistence(timeout: 3),
                      "seeded cards missing after save")
    }
}
