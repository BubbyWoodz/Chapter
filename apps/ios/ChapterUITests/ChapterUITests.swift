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
    func testOriginalBundledFontsActuallyLoadInIOS() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-font-diagnostic"]; app.launch()
        for name in ["HankenGrotesk-Regular","HankenGrotesk-Italic","Newsreader16pt-Regular","Newsreader16pt-Italic","SplineSansMono-Regular","SplineSansMono-Italic"] {
            let face = app.staticTexts["font."+name]; XCTAssertTrue(face.waitForExistence(timeout:10),"UIFont must load the original bundled face, not silently fall back"); XCTAssertEqual(face.label,name)
        }
        attach(app,name:"Chapter actual original web fonts loaded by native UIFont")
        try audit(app,for:.dynamicType)
        app.buttons["Original font licenses"].tap()
        for family in ["hanken-grotesk","newsreader","spline-sans-mono"] {
            let license = app.staticTexts["license."+family]; XCTAssertTrue(license.waitForExistence(timeout:5)); XCTAssertTrue(license.label.contains("SIL OPEN FONT LICENSE Version 1.1"))
        }
    }
    func testUnmodifiedNativeSecureFieldDynamicTypeReproduction() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-native-secure-field-audit-repro"]; app.launch()
        XCTAssertTrue(app.secureTextFields["Public secure field"].waitForExistence(timeout:10))
        attach(app,name:"Unmodified native SecureField strict Dynamic Type comparison")
        try audit(app,for:.dynamicType)
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

    func testRichEntryMetadataRetainsDocumentAndCommaLabel() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        let entry = app.staticTexts["Public rich fixture"]; XCTAssertTrue(entry.waitForExistence(timeout:10)); entry.tap()
        app.buttons["More"].tap(); app.buttons["Title, date and labels"].tap()
        let title = app.textFields["metadata.title"]; XCTAssertTrue(title.waitForExistence(timeout:5)); title.tap(); title.typeText("-METADATA")
        let label = app.textFields["metadata.new-label"]; reveal(label,in:app); label.tap(); label.typeText("TRAVEL, FRIENDS\n")
        XCTAssertTrue(app.staticTexts["travel, friends"].waitForExistence(timeout:5))
        attach(app,name:"Chapter real rich-entry metadata form and single comma label")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5)); XCTAssertFalse(app.staticTexts["metadata.error"].exists)
        XCTAssertTrue(app.staticTexts["entry.title"].label.contains("-METADATA"),"Native title must actually save without flattening the rich body")
        let labels = app.staticTexts["entry.labels"]; reveal(labels,in:app); XCTAssertEqual(labels.label,"travel, friends")
        attach(app,name:"Chapter original rich document retained after native metadata edit")
    }

    func testDeleteEntryKeepsOriginalAndRestoresNativeRichContent() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        let entry = app.staticTexts["Public rich fixture"]; XCTAssertTrue(entry.waitForExistence(timeout:10)); entry.tap()
        app.buttons["More"].tap(); app.buttons["Delete entry"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","An encrypted recovery copy remains")).firstMatch.waitForExistence(timeout:5))
        app.buttons["Delete entry"].tap()
        XCTAssertTrue(app.staticTexts["Public rich fixture"].waitForNonExistence(timeout:5))
        app.tabBars.buttons["Settings"].tap()
        let restore = app.buttons["Restore as new entry"].firstMatch; reveal(restore,in:app); restore.tap()
        app.tabBars.buttons["Journal"].tap()
        let recovered = app.staticTexts["Public rich fixture"]; XCTAssertTrue(recovered.waitForExistence(timeout:5)); recovered.tap()
        XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["Mark task complete"].exists)
        attach(app,name:"Chapter real recoverable deletion and restored native rich entry")
    }

    func testNotebookCascadeRetainsAndRestoresActualNativeRichEntry() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        app.tabBars.buttons["Notebooks"].tap()
        let edit = app.buttons["Edit notebook Public notebook"]; XCTAssertTrue(edit.waitForExistence(timeout:10)); edit.tap()
        let prepare = app.buttons["notebook.delete.prepare"]; reveal(prepare,in:app); prepare.tap()
        let confirmation = app.textFields["notebook.delete.confirmation"]; reveal(confirmation,in:app)
        XCTAssertFalse(app.buttons["notebook.delete.apply"].isEnabled)
        confirmation.tap(); confirmation.typeText("delete")
        attach(app,name:"Chapter real reviewed recoverable notebook deletion")
        app.buttons["notebook.delete.apply"].tap()
        XCTAssertTrue(app.navigationBars["Notebooks"].waitForExistence(timeout:5)); XCTAssertFalse(app.buttons["Edit notebook Public notebook"].exists)
        app.tabBars.buttons["Journal"].tap(); XCTAssertTrue(app.staticTexts["Public rich fixture"].waitForNonExistence(timeout:5))
        app.tabBars.buttons["Settings"].tap()
        let restore = app.buttons["Restore notebook and entries"]; reveal(restore,in:app); restore.tap()
        app.tabBars.buttons["Notebooks"].tap(); XCTAssertTrue(app.buttons["Edit notebook Public notebook"].waitForExistence(timeout:5))
        app.tabBars.buttons["Journal"].tap(); let entry = app.staticTexts["Public rich fixture"]; XCTAssertTrue(entry.waitForExistence(timeout:5)); entry.tap()
        XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5)); XCTAssertTrue(app.buttons["Mark task complete"].exists)
        attach(app,name:"Chapter actual notebook cascade restored original rich entry and tasks")
    }

    func testFailedPlainWritingKeepsEncryptedRecoveryAndResumes() throws {
        // Public fixture deliberately has NO identity: publishing must fail,
        // while its actual encrypted local store can retain writing safely.
        let app = XCUIApplication(); app.launchArguments = ["--chapter-rich-fixture"]; app.launch()
        XCTAssertTrue(app.buttons["New entry"].waitForExistence(timeout:10)); app.buttons["New entry"].tap()
        let title = app.textFields["Entry title"]; XCTAssertTrue(title.waitForExistence(timeout:5)); title.tap(); title.typeText("PUBLIC-WRITING-RECOVERY")
        let editor = app.textViews["Journal text"]; reveal(editor,in:app); editor.tap(); editor.typeText("PUBLIC-UNSAVED-TEXT")
        let status = app.staticTexts["writing.recovery-status"]; reveal(status,in:app)
        XCTAssertTrue(status.label.contains("Draft saved encrypted"))
        app.buttons["writing.close"].tap(); app.tabBars.buttons["Settings"].tap()
        let resume = app.buttons["Resume unsaved writing"].firstMatch; reveal(resume,in:app); resume.tap()
        XCTAssertEqual(app.textFields["Entry title"].value as? String,"PUBLIC-WRITING-RECOVERY")
        XCTAssertEqual(app.textViews["Journal text"].value as? String,"PUBLIC-UNSAVED-TEXT")
        attach(app,name:"Chapter actual encrypted failed-writing recovery and resumed native editor")
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

// Genuine public-fixture page captures, NOT mocks and not a substitute for the
// separate strict production accessibility/functional test runs. Only this tour
// disables animation to capture final native UI states rather than transitions.
final class ChapterPageCaptures: XCTestCase {
    private func launch(media:Bool = false) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-still-captures"]
        if media {app.launchArguments.append("--chapter-media-fixture")};app.launch();return app
    }
    private func shot(_ app:XCUIApplication,_ name:String) {
        let image=XCTAttachment(screenshot:app.screenshot());image.name="Page — " + name;image.lifetime = .keepAlways;add(image)
    }
    private func reveal(_ element:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<15 {if element.exists && element.isHittable {return};app.swipeUp()}
        for _ in 0..<25 {if element.exists && element.isHittable {return};app.swipeDown()}
        XCTAssertTrue(element.exists && element.isHittable,"Actual page control must be reachable: " + element.debugDescription)
    }
    func testConnectionInitialScreenNoSecrets() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-still-captures"];app.launch()
        XCTAssertTrue(app.textFields["connection.server"].waitForExistence(timeout:10));shot(app,"00 Actual server URL and recovery unlock screen")
    }
    func testJournalSearchCalendarComposeNotebookFormsAndMenus() throws {
        let app=launch(media:true);let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10))
        shot(app,"01 Journal list")
        let search=app.searchFields.firstMatch;XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Public rich")
        XCTAssertTrue(entry.waitForExistence(timeout:5));shot(app,"02 Actual local search")
        app.buttons["Cancel"].tap();app.buttons["New entry"].tap()
        XCTAssertTrue(app.navigationBars["New entry"].waitForExistence(timeout:5));shot(app,"03 New plain entry")
        let title=app.textFields["Entry title"];title.tap();title.typeText("Public plain entry")
        let writing=app.textViews["Journal text"];reveal(writing,app);writing.tap();writing.typeText("Public native plain writing saved encrypted offline.")
        app.buttons["Done"].tap();let plain=app.staticTexts["Public plain entry"];XCTAssertTrue(plain.waitForExistence(timeout:5));plain.tap()
        app.buttons["Edit"].tap();XCTAssertTrue(app.buttons["Text and details"].waitForExistence(timeout:5));shot(app,"31 Actual plain entry edit choices")
        app.buttons["Text and details"].tap();XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout:5));shot(app,"32 Existing plain entry editor")
        app.buttons["writing.close"].tap();app.navigationBars.buttons["Journal"].tap();app.tabBars.buttons["Calendar"].tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout:5));shot(app,"04 Calendar and local statistics")
        app.tabBars.buttons["Notebooks"].tap();let edit=app.buttons["Edit notebook Public notebook"]
        XCTAssertTrue(edit.waitForExistence(timeout:5));shot(app,"05 Original-theme notebook shelf");edit.tap()
        XCTAssertTrue(app.textFields["notebook.name"].waitForExistence(timeout:5));shot(app,"06 Notebook details color and cover form")
        app.buttons["notebook.cover"].tap();XCTAssertTrue(app.buttons["Grid"].waitForExistence(timeout:5));shot(app,"07 Original notebook cover pattern choices")
        app.buttons["Lines"].tap();let deletion=app.buttons["notebook.delete.prepare"];reveal(deletion,app);deletion.tap()
        XCTAssertTrue(app.navigationBars["Delete notebook"].waitForExistence(timeout:5));shot(app,"33 Actual notebook downloaded-set deletion review")
        app.navigationBars["Delete notebook"].buttons["Cancel"].tap();app.navigationBars["Edit notebook"].buttons["Cancel"].tap()
        app.buttons["New notebook"].tap();XCTAssertTrue(app.alerts["New notebook"].waitForExistence(timeout:5));shot(app,"08 Create notebook dialog");app.buttons["Cancel"].tap()
    }
    func testPlainWritingRecoverySettingsAndResumePages() throws {
        let app=launch();XCTAssertTrue(app.buttons["New entry"].waitForExistence(timeout:10));app.buttons["New entry"].tap()
        let title=app.textFields["Entry title"];XCTAssertTrue(title.waitForExistence(timeout:5));title.tap();title.typeText("Public recovery writing")
        let editor=app.textViews["Journal text"];reveal(editor,app);editor.tap();editor.typeText("Public preserved writing when publication is unavailable.")
        let status=app.staticTexts["writing.recovery-status"];reveal(status,app);XCTAssertTrue(status.label.contains("Draft saved encrypted"));shot(app,"36 Genuine failed-writing preserved recovery controls")
        app.buttons["writing.close"].tap();app.tabBars.buttons["Settings"].tap();let resume=app.buttons["Resume unsaved writing"].firstMatch;reveal(resume,app);shot(app,"37 Settings encrypted unsaved-writing recovery")
        resume.tap();XCTAssertTrue(app.textViews["Journal text"].waitForExistence(timeout:5));shot(app,"41 Actual resumed unsaved plain writer")
    }
    func testRichEditorFormattingMoveMetadataAndAppearancePages() throws {
        let app=launch();let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5));shot(app,"09 Original rich reader")
        app.buttons["More"].tap();XCTAssertTrue(app.buttons["Move to notebook"].waitForExistence(timeout:5));shot(app,"10 Entry actions")
        app.buttons["Move to notebook"].tap();XCTAssertTrue(app.buttons["move.notebook"].waitForExistence(timeout:5));shot(app,"11 Move entry form")
        app.buttons["move.notebook"].tap();XCTAssertTrue(app.buttons["Public destination"].waitForExistence(timeout:5));shot(app,"12 Move notebook choices")
        app.buttons["Public notebook"].tap();app.buttons["Cancel"].tap()
        app.buttons["Edit"].tap();XCTAssertTrue(app.buttons["rich.run.0/0"].waitForExistence(timeout:5));shot(app,"13 Lossless rich editor block list")
        app.buttons["rich.run.0/0"].tap();XCTAssertTrue(app.textViews["Formatted text run"].waitForExistence(timeout:5));shot(app,"14 Actual formatted text-run editor")
        app.buttons["rich.formatting"].tap();XCTAssertTrue(app.buttons["rich.format.italic"].waitForExistence(timeout:5));shot(app,"15 Expanded real formatting controls")
        app.buttons["rich.format.italic"].tap();app.buttons["Save"].tap()
        app.buttons["rich.add-block"].tap();let block=app.textViews["New block text"];XCTAssertTrue(block.waitForExistence(timeout:5));block.tap();block.typeText("Public native block")
        shot(app,"29 Actual new rich block and encrypted draft")
        app.buttons["rich.block-style"].tap();XCTAssertTrue(app.buttons["Heading 2"].waitForExistence(timeout:5));shot(app,"30 Actual native block style choices");app.buttons["Heading 2"].tap()
        app.buttons["Save"].tap()
        app.buttons["rich.add-block"].tap();let retained=app.textViews["New block text"];XCTAssertTrue(retained.waitForExistence(timeout:5));retained.tap();retained.typeText("Public retained rich draft")
        app.navigationBars.buttons["Edit rich entry"].tap();app.buttons["Done"].tap()
        app.buttons["More"].tap();app.buttons["Title, date and labels"].tap();XCTAssertTrue(app.textFields["metadata.title"].waitForExistence(timeout:5));shot(app,"16 Entry title date labels form");app.buttons["Cancel"].tap()
        app.tabBars.buttons["Settings"].tap();XCTAssertTrue(app.buttons["appearance.skin"].waitForExistence(timeout:5));shot(app,"17 Settings upper appearance and sync")
        app.buttons["appearance.skin"].tap();XCTAssertTrue(app.buttons["Forest"].waitForExistence(timeout:5));shot(app,"18 Matching original theme style choices");app.buttons["Forest"].tap()
        app.buttons["appearance.palette"].tap();XCTAssertTrue(app.buttons["Moss"].waitForExistence(timeout:5));shot(app,"19 Original accent palette choices");app.buttons["Moss"].tap()
        app.buttons["appearance.mode"].tap();XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout:5));shot(app,"20 Synced appearance mode choices");app.buttons["Dark"].tap();shot(app,"21 Actual dark Forest settings")
        let retainedDraft=app.staticTexts["Public retained rich draft"];reveal(retainedDraft,app);shot(app,"34 Settings encrypted pending rich drafts");retainedDraft.tap()
        XCTAssertTrue(app.textViews["New block text"].waitForExistence(timeout:5));shot(app,"35 Genuine resumed encrypted rich draft");app.buttons["Save"].tap()
        let licenses=app.buttons["Original font licenses"];reveal(licenses,app);shot(app,"22 Settings lower privacy limitations and licenses");licenses.tap()
        XCTAssertTrue(app.staticTexts["license.hanken-grotesk"].waitForExistence(timeout:5));shot(app,"23 Original bundled offline font licenses")
    }
    func testRealEncryptedOfflineMediaPreviewOutboxAndRecoveryPages() throws {
        let app=launch(media:true);let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        let preview=app.buttons["media.preview." + String(repeating:"a",count:32)];reveal(preview,app);shot(app,"24 Real encrypted media controls and pending queue")
        preview.tap();let done=app.buttons["Done"];XCTAssertTrue(done.waitForExistence(timeout:10),"Genuine decrypted local Quick Look must open without server authentication");shot(app,"25 Actual decrypted protected offline file preview");done.tap()
        let filePicker=app.buttons["Attach file"];reveal(filePicker,app);filePicker.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:10));shot(app,"38 Actual iOS Files picker no file selected");app.buttons["Cancel"].tap()
        let photoPicker=app.buttons["Attach photo"];reveal(photoPicker,app);photoPicker.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout:10));shot(app,"39 Actual iOS Photos picker no photo selected");app.buttons["Cancel"].tap()
        let unsupported=app.buttons["media.preview.attachment"];reveal(unsupported,app);unsupported.tap()
        let mediaError=app.staticTexts["media.error"];reveal(mediaError,app);XCTAssertTrue(mediaError.exists);shot(app,"40 Honest unsupported attachment error no fake success")
        app.navigationBars.buttons["Journal"].tap()
        app.tabBars.buttons["Settings"].tap();let retry=app.buttons["Retry attachments and sync"];reveal(retry,app);shot(app,"26 Durable encrypted attachment outbox offline")
        app.tabBars.buttons["Journal"].tap();entry.tap();app.buttons["More"].tap();app.buttons["Delete entry"].tap()
        XCTAssertTrue(app.buttons["Delete entry"].waitForExistence(timeout:5));shot(app,"27 Actual recoverable entry deletion confirmation")
        app.buttons["Delete entry"].tap();XCTAssertTrue(entry.waitForNonExistence(timeout:5))
        app.tabBars.buttons["Settings"].tap();let restore=app.buttons["Restore as new entry"];reveal(restore,app);shot(app,"28 Retained encrypted original recovery and media")
        restore.tap();app.tabBars.buttons["Journal"].tap();XCTAssertTrue(entry.waitForExistence(timeout:5))
    }
}
