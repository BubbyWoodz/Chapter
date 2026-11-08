// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest

final class ChapterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testConnectionScreenAccessibilityAndPrivacy() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["connection.server"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["connection.phrase"].exists)
        XCTAssertTrue(app.buttons["connection.unlock"].isEnabled)
        attach(app, name: "Chapter connection — no journal data")
        try audit(app)
        app.buttons["connection.unlock"].tap()
        XCTAssertTrue(app.staticTexts["connection.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["connection.status"].label.contains("Enter your server URL"))
    }
    func testLargestDynamicTypeConnectionScreen() throws {
        let app = XCUIApplication()
        // CI sets the Simulator OS text-size preference, not a launch override
        // that could prevent the audit itself from changing preferred sizes.
        app.launch()
        XCTAssertTrue(app.navigationBars["Chapter"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.staticTexts["connection.heading"].frame.height, 60, "This test must actually start at accessibility XXXL, not default text size")
        attach(app, name: "Chapter accessibility XXXL viewport")
        try audit(app, for: .dynamicType)
        // At XXXL the form correctly scrolls; off-screen lazy rows need revealing.
        // Assert reachability rather than treating off-screen virtualization as failure.
        reveal(app.textFields["connection.server"], in: app)
        attach(app, name: "Chapter accessibility XXXL viewport")
        try audit(app, for: .dynamicType)
        reveal(app.secureTextFields["connection.phrase"], in: app)
        attach(app, name: "Chapter accessibility XXXL viewport")
        try audit(app, for: .dynamicType)

    }
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func audit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            // Public fixture screens only. Returning false keeps EVERY finding a failure.
            print("AUDIT type: \(issue.auditType); element: \(issue.element?.debugDescription ?? "unknown")")
            return false
        }
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Required control must be reachable by scrolling")
    }
    func testHTTPIsRejectedBeforeAnyAuthenticationOrVaultCreation() throws {
        let app = XCUIApplication(); app.launch()
        let server = app.textFields["connection.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10)); server.tap(); server.typeText("http://fixture.invalid")
        let phrase = app.secureTextFields["connection.phrase"]; phrase.tap()
        // PUBLIC BIP39 fixture only. No network request should be made for invalid HTTP.
        phrase.typeText("legal winner thank year wave sausage worth useful legal winner thank yellow")
        app.swipeUp()
        app.buttons["connection.unlock"].tap()
        let status = app.staticTexts["connection.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5)); XCTAssertTrue(status.label.contains("HTTPS"))
        // The server row may be virtualized offscreen after the error scrolls into view.
        XCTAssertTrue(app.navigationBars["Chapter"].exists)
        XCTAssertTrue(app.buttons["connection.unlock"].exists)
    }
}
