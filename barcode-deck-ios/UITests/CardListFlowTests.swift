import XCTest

/// Smoke test for the card list's add flow: seeds two cards through the
/// real UI and asserts they appear newest-first.
///
/// The gesture-driven interactions (edit-mode drag reorder, swipe-delete
/// undo) can't be simulated reliably with synthetic XCUITest events — they
/// are verified manually on device.
final class CardListFlowTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Fresh store; the "+" button opens the add form directly (no camera).
        app.launchArguments += ["--debug-reset-store", "--debug-skip-scanner"]
        app.launch()
    }

    private func field(_ placeholder: String) -> XCUIElement {
        app.textFields.matching(
            NSPredicate(format: "placeholderValue == %@", placeholder)
        ).firstMatch
    }

    private func row(_ name: String) -> XCUIElement {
        app.staticTexts[name].firstMatch
    }

    private func addCard(name: String, value: String) {
        // Opens the manual form directly: the test run uses --debug-skip-scanner.
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

        // Save lives in the navigation bar, above the keyboard.
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3), "Save missing")
        XCTAssertTrue(save.isEnabled, "Save is disabled")
        save.tap()
        XCTAssertTrue(app.buttons["Add card"].waitForExistence(timeout: 5), "sheet did not close")
    }

    func testAddFlowSeedsCardsNewestFirst() throws {
        // Newest cards land on top: BBB created first, AAA second.
        addCard(name: "BBB", value: "222")
        addCard(name: "AAA", value: "111")

        let rowA = row("AAA")
        let rowB = row("BBB")
        XCTAssertTrue(rowA.waitForExistence(timeout: 3), "AAA row missing")
        XCTAssertTrue(rowB.waitForExistence(timeout: 3), "BBB row missing")
        XCTAssertLessThan(rowA.frame.minY, rowB.frame.minY,
                          "newest card should be listed first")
    }
}
