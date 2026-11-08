// SPDX-License-Identifier: AGPL-3.0-or-later
import XCTest
import UIKit

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
    func testLargestDynamicTypeControlGeometry() throws {
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.navigationBars["Chapter"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(app.staticTexts["connection.heading"].frame.height, 60)
        let server = app.textFields["connection.server"]
        reveal(server, in: app)
        print("XXXL server frame: \(server.frame)")
        XCTAssertGreaterThan(server.frame.height, 45, "The input must grow beyond its default-size row")
        attach(app, name: "Chapter actual OS XXXL server input")
        let action = app.buttons["connection.unlock"]
        reveal(action, in: app)
        print("XXXL action frame: \(action.frame)")
        XCTAssertGreaterThan(action.frame.height, 70, "The long native action must wrap and grow at XXXL")
        attach(app, name: "Chapter actual OS XXXL action")
        // This supplements, never replaces, the separate strict audit tests.
    }
    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func audit(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType = .all) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            // Public fixture screens only. Returning false keeps EVERY finding a failure.
            print("AUDIT type: \(issue.auditType); element: \(issue.element?.debugDescription ?? "unknown")")
            print("AUDIT summary: \(issue.compactDescription)")
            print("AUDIT details: \(issue.detailedDescription)")
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
    func testNativeRichRenderingEditingAndTaskPersistence() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        let entry = app.staticTexts["Public rich fixture"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout: 5))
        let task = app.buttons["Mark task complete"]; reveal(task, in: app); task.tap()
        XCTAssertTrue(app.buttons["Mark task incomplete"].waitForExistence(timeout: 5))
        attach(app, name: "Chapter genuine native rich document and persisted task")
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit rich entry"].waitForExistence(timeout: 5))
        let run = app.buttons["rich.run.0/0"]
        XCTAssertTrue(run.waitForExistence(timeout: 5)); run.tap()
        let editor = app.textViews["Formatted text run"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(" FIELD-EDIT-PROBE")
        XCTAssertTrue(app.staticTexts["Draft saved encrypted on this device. Tap Save to update the entry."].waitForExistence(timeout: 5))
        app.buttons["Save"].tap(); app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "FIELD-EDIT-PROBE")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Mark task incomplete"].exists)
        attach(app, name: "Chapter actual native formatted-run edit")
    }
    func testUnmodifiedNativeFormDynamicTypeReproduction() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-native-form-audit-repro"]; app.launch()
        XCTAssertTrue(app.buttons["repro.native-button"].waitForExistence(timeout: 10))
        attach(app, name: "Unmodified native SwiftUI Form Dynamic Type reproduction")
        // Additional required diagnostic only. Both original production audits
        // remain required and no issue is accepted/ignored in this comparison.
        try audit(app, for: .dynamicType)
    }
    func testNotebookMetadataEditingPersistsInNativeList() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["Notebooks"].waitForExistence(timeout: 10)); app.tabBars.buttons["Notebooks"].tap()
        let edit = app.buttons["Edit notebook Public notebook"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let name = app.textFields["notebook.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText(" RENAMED")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "RENAMED")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["notebook.error"].exists)
        XCTAssertTrue(app.staticTexts["Public subtitle"].exists)
        attach(app, name: "Chapter actual persisted notebook metadata edit")
    }
    func testAppearanceChoicesAndNativeNotebookCovers() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Notebooks"].waitForExistence(timeout:10));app.tabBars.buttons["Notebooks"].tap()
        attach(app,name:"Chapter actual native notebook cover from original web pattern")
        app.tabBars.buttons["Settings"].tap()
        let style=app.buttons["appearance.skin"]
        XCTAssertTrue(style.waitForExistence(timeout:5));style.tap()
        app.buttons["Forest"].tap()
        XCTAssertFalse(app.staticTexts["appearance.error"].exists)
        attach(app,name:"Chapter actual Forest theme using original web colors")
        app.tabBars.buttons["Notebooks"].tap()
        XCTAssertTrue(app.staticTexts["Public notebook"].waitForExistence(timeout:5))
        attach(app,name:"Chapter actual Forest-themed native notebook")
        // Independent source value: original forest --paper is #eef0e2.
        // Prior root-only tint produced WHITE here; this must catch that regression.
        let image=try XCTUnwrap(app.screenshot().image.cgImage)
        let crop=try XCTUnwrap(image.cropping(to:CGRect(x:CGFloat(image.width)/40,y:CGFloat(image.height)/2,width:1,height:1)))
        var pixel=[UInt8](repeating:0,count:4)
        let context=try XCTUnwrap(CGContext(data:&pixel,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(crop,in:CGRect(x:0,y:0,width:1,height:1))
        for (actual,expected) in zip(pixel.prefix(3),[238,240,226]) { XCTAssertLessThanOrEqual(abs(Int(actual)-expected),2,"Forest paper must actually render, not merely save a preference") }
    }
    func testHTTPIsRejectedBeforeAnyAuthenticationOrVaultCreation() throws {
        let app = XCUIApplication(); app.launch()
        let server = app.textFields["connection.server"]
        XCTAssertTrue(server.waitForExistence(timeout: 10)); server.tap(); server.typeText("http://fixture.invalid\n")
        let phrase = app.secureTextFields["connection.phrase"]; XCTAssertTrue(phrase.exists)
        // Real native Next action must focus the secure field, including while the bottom CTA resizes.
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
    func testNativeFormattingAndNewHeadingPersistInOriginalDocument() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        let entry = app.staticTexts["Public rich fixture"]; XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        app.buttons["Edit"].tap(); app.buttons["rich.run.0/0"].tap()
        app.buttons["rich.formatting"].tap(); app.buttons["rich.format.italic"].tap()
        XCTAssertTrue(app.staticTexts["Formatting: Bold, Italic"].waitForExistence(timeout: 5)); app.buttons["Save"].tap()
        app.buttons["rich.run.0/0"].tap()
        XCTAssertTrue(app.staticTexts["Formatting: Bold, Italic"].waitForExistence(timeout: 5), "Reopening must derive formatting from the saved original document")
        app.buttons["Save"].tap(); app.buttons["rich.add-block"].tap()
        let editor = app.textViews["New block text"]; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText("PUBLIC-NATIVE-STRUCTURAL-PROBE")
        app.buttons["rich.block-style"].tap(); app.buttons["Heading 2"].tap()
        XCTAssertTrue(app.staticTexts["Draft saved encrypted on this device. Tap Save to update the entry."].waitForExistence(timeout: 5))
        attach(app, name: "Chapter real encrypted heading draft and native block picker")
        app.buttons["Save"].tap(); app.buttons["Done"].tap()
        let heading = app.staticTexts["PUBLIC-NATIVE-STRUCTURAL-PROBE"]; reveal(heading, in: app)
        XCTAssertTrue(heading.exists); attach(app, name: "Chapter actual persisted native-authored heading")
    }

    func testLargestDynamicTypeUnmodifiedNativeFormReproduction() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-native-form-audit-repro"]; app.launch()
        let heading = app.staticTexts["Native Form reproduction"]
        XCTAssertTrue(heading.waitForExistence(timeout: 10)); XCTAssertGreaterThan(heading.frame.height, 40, "Diagnostic must actually run at OS accessibility XXXL")
        attach(app, name: "Unmodified native Form at actual OS accessibility XXXL")
        try audit(app, for: .dynamicType)
    }

    func testRichEntryMovesToNotebookWithoutLosingContent() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        let entry = app.staticTexts["Public rich fixture"]; XCTAssertTrue(entry.waitForExistence(timeout: 10)); entry.tap()
        XCTAssertEqual(app.staticTexts["entry.notebook"].label, "Notebook: Public notebook")
        app.buttons["More"].tap(); app.buttons["Move to notebook"].tap()
        app.buttons["move.notebook"].tap(); app.buttons["Public destination"].tap(); app.buttons["Move"].tap()
        XCTAssertTrue(app.staticTexts["entry.notebook"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["entry.notebook"].label, "Notebook: Public destination")
        XCTAssertTrue(app.staticTexts["Public heading"].exists)
        attach(app, name: "Chapter real native rich entry moved between notebooks")
    }

}
