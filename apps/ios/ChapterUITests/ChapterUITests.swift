// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest

final class ChapterUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testConnectionScreenAccessibilityAndPrivacy() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.textFields["connection.server"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.secureTextFields["connection.phrase"].exists)
        XCTAssertFalse(app.buttons["connection.unlock"].isEnabled)
        try app.performAccessibilityAudit()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Chapter connection — no journal data"; shot.lifetime = .keepAlways; add(shot)
    }
    func testLargestDynamicTypeConnectionScreen() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Chapter"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: .dynamicType)
        // At XXXL the form correctly scrolls; off-screen lazy rows need revealing.
        // Assert reachability rather than treating off-screen virtualization as failure.
        reveal(app.textFields["connection.server"], in: app)
        try app.performAccessibilityAudit(for: .dynamicType)
        reveal(app.secureTextFields["connection.phrase"], in: app)
        try app.performAccessibilityAudit(for: .dynamicType)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Chapter connection — accessibility XXXL"; shot.lifetime = .keepAlways; add(shot)
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
        XCTAssertTrue(app.textFields["connection.server"].exists)
    }
}
