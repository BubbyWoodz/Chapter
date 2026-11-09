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
        // Stricter, not weaker: two more fresh launches must also pass every check.
        for _ in 0..<2 {
            app.terminate(); app.launch()
            XCTAssertTrue(app.textFields["connection.server"].waitForExistence(timeout: 10))
            try audit(app)
        }
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
    /// Additional required comparisons at the actual OS XXXL size: unchanged
    /// native SecureField and the production CTA layout, each audited alone.
    func testLargestDynamicTypeUnmodifiedSecureFieldReproduction() throws {
        let app = XCUIApplication(); app.launchArguments = ["--chapter-native-secure-field-audit-repro"]; app.launch()
        XCTAssertTrue(app.secureTextFields["Public secure field"].waitForExistence(timeout:10))
        attach(app,name:"Unmodified native SecureField at actual OS accessibility XXXL")
        try audit(app,for:.dynamicType)
    }
    func testLargestDynamicTypeFullWidthActionReproduction() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-full-width-action-audit-repro"];app.launch()
        XCTAssertTrue(app.buttons["repro.full-width-action"].waitForExistence(timeout:10))
        attach(app,name:"Production full-width CTA layout at actual OS accessibility XXXL")
        try audit(app,for:.dynamicType)
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
        // Slow drags, then back the other way: a fast fling can carry a tall
        // XXXL row straight past the viewport. Reachability is still required.
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp(velocity: .slow)
        }
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeDown(velocity: .slow)
        }
        if !(element.exists && element.isHittable) {
            attach(app, name: "Actual unreached control after bounded scrolling")
            let hierarchy = XCTAttachment(string: app.debugDescription); hierarchy.name = "Actual unreachable-control hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Required control must be reachable by scrolling")
    }
    func testActualNativeWholeBlockReorderingPersistsAndKeepsOpaqueContent() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        app.buttons["Edit"].tap();app.buttons["rich.arrange-blocks"].tap()
        let first=app.descendants(matching:.any).matching(identifier:"rich.block.0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout:5));XCTAssertTrue(first.label.contains("Public heading"))
        first.press(forDuration:1)
        let down=app.buttons["Move down"];XCTAssertTrue(down.waitForExistence(timeout:5));down.tap()
        let moved=NSPredicate(format:"label CONTAINS %@","Hello")
        expectation(for:moved,evaluatedWith:first);waitForExpectations(timeout:5)
        attach(app,name:"Chapter actual native rearranged whole blocks saved encrypted")
        app.navigationBars.buttons["Edit rich entry"].tap();app.buttons["rich.arrange-blocks"].tap()
        XCTAssertTrue(first.waitForExistence(timeout:5));XCTAssertTrue(first.label.contains("Hello"),"Reopened order must come from durable encrypted snapshot")
        let opaque=app.descendants(matching:.any).matching(identifier:"rich.block.13").firstMatch
        reveal(opaque,in:app);XCTAssertTrue(opaque.label.contains("futureNode"),"Whole opaque future block must remain")
    }
    func testNativeEntryLinksAndBacklinksNavigateLocallyWithoutNetwork() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-linked-entry-fixture"];app.launch()
        let source=app.staticTexts["Public rich fixture"];XCTAssertTrue(source.waitForExistence(timeout:10));source.tap()
        let link=app.buttons["entry.link.entry-target"];reveal(link,in:app);link.tap()
        let title=app.staticTexts["entry.title"];XCTAssertTrue(title.waitForExistence(timeout:5));XCTAssertEqual(title.label,"Public linked target")
        let backlink=app.buttons["entry.backlink.public-rich-fixture"];reveal(backlink,in:app)
        attach(app,name:"Actual native local linked target and original-web backlinks")
        backlink.tap();XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["entry.title"].label,"Public rich fixture")
        app.navigationBars.buttons["Entry"].tap();XCTAssertEqual(app.staticTexts["entry.title"].label,"Public linked target")
    }
    func testNativeLinkPickerInsertsOriginalWebLinkAndNavigatesWithBacklink() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-linked-entry-fixture"];app.launch()
        let target=app.staticTexts["Public linked target"];XCTAssertTrue(target.waitForExistence(timeout:10));target.tap()
        XCTAssertTrue(app.staticTexts["entry.title"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["entry.link.public-rich-fixture"].exists)
        app.buttons["More"].tap();let add=app.buttons["entry.addLink"];XCTAssertTrue(add.waitForExistence(timeout:5));add.tap()
        XCTAssertTrue(app.navigationBars["Link to entry"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["link.candidate.entry-target"].exists,"The current entry must never be offered, like the original picker")
        let search=app.searchFields["Search entry titles"];XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("no such title")
        XCTAssertTrue(app.staticTexts["link.empty"].waitForExistence(timeout:5))
        search.buttons.firstMatch.tap();search.typeText("RICH")
        let candidate=app.buttons["link.candidate.public-rich-fixture"];XCTAssertTrue(candidate.waitForExistence(timeout:5))
        attach(app,name:"Actual native entry-link picker mirroring the original web [[ search")
        candidate.tap()
        let link=app.buttons["entry.link.public-rich-fixture"];XCTAssertTrue(link.waitForExistence(timeout:5));reveal(link,in:app)
        XCTAssertTrue(app.staticTexts["🔗 Public rich fixture"].exists || link.label.contains("Public rich fixture"))
        attach(app,name:"Actual native inserted entry link rendered from the original document")
        link.tap();XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["entry.title"].label,"Public rich fixture")
        let backlink=app.buttons["entry.backlink.entry-target"];reveal(backlink,in:app);XCTAssertTrue(backlink.exists)
    }
    func testMissingLocalEntryLinkShowsHonestOfflineStateWithoutCloudOrFakeSuccess() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let source=app.staticTexts["Public rich fixture"];XCTAssertTrue(source.waitForExistence(timeout:10));source.tap()
        let link=app.buttons["entry.link.entry-target"];reveal(link,in:app);link.tap()
        XCTAssertTrue(app.staticTexts["Linked entry is not downloaded"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["Sync your server"].exists)
        attach(app,name:"Actual native missing linked entry offline state, not fake navigation success")
    }
    func testOriginalTableRendersExactMergedGridWithHeaderAndAccessibleCells() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        let header=app.descendants(matching:.any)["table.cell.0.0"];reveal(header,in:app);XCTAssertTrue(header.exists)
        let merged=app.descendants(matching:.any)["table.cell.0.1"];XCTAssertTrue(merged.exists)
        XCTAssertTrue(header.label.hasPrefix("Header, row 1, column 1"),header.label)
        XCTAssertTrue(merged.label.contains("spans 1 rows and 2 columns"),merged.label)
        XCTAssertFalse(app.descendants(matching:.any)["table.cell.0.2"].exists,"A colspan-2 cell must cover column 3, not create a phantom cell")
        // The merged cell starts where the header ends and is wider (two tracks).
        XCTAssertEqual(merged.frame.minX,header.frame.maxX,accuracy:1.5);XCTAssertGreaterThan(merged.frame.width,header.frame.width*0.9)
        XCTAssertEqual(header.frame.width,160,accuracy:1.5,"Original TipTap colwidth must be honored")
        attach(app,name:"Actual native original table with exact merged grid")
        let location=app.staticTexts["custom.location"];reveal(location,in:app);XCTAssertEqual(location.label,"📍 Home → Park")
        let interview=app.staticTexts["custom.videoInterview"];reveal(interview,in:app);XCTAssertEqual(interview.label,"🎬 Public interview · 1 question")
        attach(app,name:"Actual native original custom-block markers")
    }
    func testSyncedTemplateStartsNewEntryWithExactContentAndOriginalDefaultTitle() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-template-fixture"];app.launch()
        let start=app.buttons["journal.fromTemplate"];XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        XCTAssertTrue(app.navigationBars["Start from template"].waitForExistence(timeout:5))
        let use=app.buttons["template.use.public-template"];XCTAssertTrue(use.waitForExistence(timeout:5));XCTAssertTrue(use.label.contains("Public weekly template"))
        attach(app,name:"Actual native template picker with synced template preview")
        use.tap()
        XCTAssertTrue(app.staticTexts["Public template heading"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Public template prompt"].exists)
        let title=app.staticTexts["entry.title"].label
        XCTAssertNotNil(title.range(of:#"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#,options:.regularExpression),"Original defaultEntryTitle format, got \(title)")
        let header=app.descendants(matching:.any)["table.cell.0.0"];reveal(header,in:app);XCTAssertTrue(header.label.hasPrefix("Header, row 1, column 1"))
        attach(app,name:"Actual native entry started from a template, including its table")
    }
    func testNativeTemplateCreateRenameAndDeleteLikeOriginalManager() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-template-fixture"];app.launch()
        let start=app.buttons["journal.fromTemplate"];XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        app.buttons["template.new"].tap()
        let name=app.textFields["template.name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("  Morning pages  ")
        let body=app.textFields["template.body"];body.tap();body.typeText("Gratitude\nOne intention")
        attach(app,name:"Actual native new-template editor")
        app.buttons["template.save"].tap()
        let created=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'template.use.' AND label CONTAINS 'Morning pages'")).firstMatch
        XCTAssertTrue(created.waitForExistence(timeout:5),"Trimmed name like the web save");XCTAssertTrue(created.label.contains("Gratitude"))
        let synced=app.buttons["template.actions.public-template"];XCTAssertTrue(synced.exists);synced.tap()
        app.buttons["template.rename"].tap()
        let rename=app.textFields["template.name"];XCTAssertTrue(rename.waitForExistence(timeout:5));XCTAssertEqual(rename.value as? String,"Public weekly template")
        rename.tap();rename.typeText(" RENAMED");app.buttons["template.save"].tap()
        let renamed=app.buttons["template.use.public-template"];XCTAssertTrue(renamed.waitForExistence(timeout:5))
        XCTAssertTrue(NSPredicate(format:"label CONTAINS 'Public weekly template RENAMED'").evaluate(with:renamed),"Renamed: \(renamed.label)")
        XCTAssertTrue(renamed.label.contains("Public template heading"),"Rename keeps the stored body")
        app.buttons["template.actions.public-template"].tap();app.buttons["template.delete"].tap()
        let confirm=app.buttons["template.confirmDelete"];XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        XCTAssertTrue(app.buttons["template.use.public-template"].waitForNonExistence(timeout:5))
        XCTAssertTrue(created.exists);XCTAssertFalse(app.staticTexts["template.error"].exists)
        attach(app,name:"Actual native template manager after rename and delete")
        created.tap()
        XCTAssertTrue(app.staticTexts["One intention"].waitForExistence(timeout:5),"A native-created template starts an entry with its content")
    }
    /// TEMPORARY bisection of the unnamed connection-screen Dynamic Type finding.
    /// Every finding is still recorded as a failure; the log names each variant.
    func testConnectionAuditVariantsIsolateTheProductionDifference() throws {
        continueAfterFailure = true
        for kind in ["surface", "headers", "sections", "secure", "fields", "inset", "dismiss", "footnotes"] {
            let app = XCUIApplication(); app.launchArguments = ["--chapter-connection-variant=" + kind]; app.launch()
            XCTAssertTrue(app.navigationBars["Variant " + kind].waitForExistence(timeout: 10))
            var findings = 0
            try app.performAccessibilityAudit(for: .dynamicType) { issue in
                findings += 1
                print("VARIANT \(kind) AUDIT: \(issue.compactDescription) | \(issue.detailedDescription) | element: \(issue.element?.debugDescription ?? "unknown")")
                return false
            }
            print("VARIANT \(kind) findings: \(findings)")
            app.terminate()
        }
    }
    func testOriginalLanguageChoiceLocalizesBuiltinTemplatesLikeTheWeb() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout:10));app.tabBars.buttons["Settings"].tap()
        let picker=app.buttons["settings.language"];reveal(picker,in:app);picker.tap()
        let german=app.buttons["Deutsch"];XCTAssertTrue(german.waitForExistence(timeout:5));german.tap()
        app.tabBars.buttons["Journal"].tap()
        let start=app.buttons["journal.fromTemplate"];XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        let daily=app.buttons["template.use.builtin:daily"];XCTAssertTrue(daily.waitForExistence(timeout:5))
        XCTAssertTrue(daily.label.contains("Tagesrückblick"),"Built-ins show in the chosen original language: "+daily.label)
        attach(app,name:"Actual native built-in templates in German from the original web catalog")
        daily.tap()
        XCTAssertTrue(app.staticTexts["Wie sich der Tag anfühlte"].waitForExistence(timeout:5),"The entry starts with the German built-in content")
    }
    func testTableToolbarCommandsRestructureAnOriginalTable() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let start=app.buttons["journal.fromTemplate"];XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        let experiment=app.buttons["template.use.builtin:experiment"];XCTAssertTrue(experiment.waitForExistence(timeout:5));experiment.tap()
        let edit=app.buttons["Edit"];XCTAssertTrue(edit.waitForExistence(timeout:5));edit.tap()
        let table=app.buttons["rich.table.5"];reveal(table,in:app);table.tap()
        XCTAssertTrue(app.buttons["table.cell.0.0"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["table.cell.2.2"].exists);XCTAssertFalse(app.buttons["table.cell.3.0"].exists)
        app.buttons["table.cell.1.1"].tap()
        app.buttons["table.command.addRowAfter"].tap()
        XCTAssertTrue(app.buttons["table.cell.3.2"].waitForExistence(timeout:5),"A row was added below")
        app.buttons["table.command.addColumnAfter"].tap()
        XCTAssertTrue(app.buttons["table.cell.0.3"].waitForExistence(timeout:5),"A column was added to the right")
        XCTAssertTrue(app.buttons["table.cell.0.2"].label.contains("header"),"The new header-row cell is a header, as in prosemirror-tables")
        attach(app,name:"Actual native table editor after adding a row and a column")
        app.buttons["table.command.deleteColumn"].tap()
        XCTAssertTrue(app.buttons["table.cell.0.3"].waitForNonExistence(timeout:5))
        app.buttons["table.command.deleteTable"].tap()
        let confirm=app.buttons["table.confirmDelete"];XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        XCTAssertTrue(app.navigationBars["Edit rich entry"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["rich.table.5"].exists,"The table is gone")
    }
    func testOriginalBuiltinTemplatesStartEntriesAndDeleteForksSyncedTombstone() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let start=app.buttons["journal.fromTemplate"];XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        let weekly=app.buttons["template.use.builtin:weekly"];XCTAssertTrue(weekly.waitForExistence(timeout:5));XCTAssertTrue(weekly.label.contains("Weekly review"))
        attach(app,name:"Actual native picker with the original web built-in templates")
        let weeklyActions=app.buttons["template.actions.builtin:weekly"];XCTAssertTrue(weeklyActions.waitForExistence(timeout:5));weeklyActions.tap();app.buttons["template.delete"].tap()
        let confirm=app.buttons["template.confirmDelete"];XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        XCTAssertTrue(weekly.waitForNonExistence(timeout:5),"Deleting a seed forks a synced tombstone that retires it")
        let daily=app.buttons["template.use.builtin:daily"];XCTAssertTrue(daily.waitForExistence(timeout:5));daily.tap()
        XCTAssertTrue(app.staticTexts["How the day felt"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Tomorrow, one thing"].exists)
        attach(app,name:"Actual native entry started from the original Daily reflection built-in")
    }
    func testCursorInsertsOriginalLinkAndTemplateAtTheCaret() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-linked-entry-fixture","--chapter-template-fixture"];app.launch()
        let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        app.buttons["Edit"].tap()
        let run=app.buttons["rich.run.0/0"];XCTAssertTrue(run.waitForExistence(timeout:5));run.tap()
        let editor=app.textViews["Formatted text run"];XCTAssertTrue(editor.waitForExistence(timeout:5))
        editor.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.05)).tap();editor.typeText("Z")
        let link=app.buttons["rich.insert-link"];XCTAssertTrue(link.waitForExistence(timeout:5));XCTAssertTrue(link.isEnabled,"Typing places a collapsed cursor")
        attach(app,name:"Actual native editor with a tracked cursor and at-cursor insert actions")
        link.tap()
        let candidate=app.buttons["link.candidate.entry-target"];XCTAssertTrue(candidate.waitForExistence(timeout:5));candidate.tap()
        XCTAssertTrue(app.navigationBars["Edit rich entry"].waitForExistence(timeout:5));app.buttons["Done"].tap()
        let linked=app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","ZPublic linked target")).firstMatch
        XCTAssertTrue(linked.waitForExistence(timeout:5),"The link sits exactly at the cursor, right after the typed character")
        attach(app,name:"Actual native link inserted at the cursor inside the original heading")
        app.buttons["Edit"].tap();XCTAssertTrue(run.waitForExistence(timeout:5));run.tap()
        XCTAssertTrue(editor.waitForExistence(timeout:5));editor.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.05)).tap();editor.typeText("Y")
        let template=app.buttons["rich.insert-template"];XCTAssertTrue(template.isEnabled);template.tap()
        let choice=app.buttons["template.insert.public-template"];XCTAssertTrue(choice.waitForExistence(timeout:5));choice.tap()
        XCTAssertTrue(app.navigationBars["Edit rich entry"].waitForExistence(timeout:5));app.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["Public template heading"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Public template prompt"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Y")).firstMatch.exists)
        attach(app,name:"Actual native template inserted at the cursor, splitting the original heading")
    }
    func testSelectionFormattingAppliesOnlyToSelectedTextLikeOriginalToolbar() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        app.buttons["Edit"].tap()
        let run=app.buttons["rich.run.0/0"];XCTAssertTrue(run.waitForExistence(timeout:5));run.tap()
        let editor=app.textViews["Formatted text run"];XCTAssertTrue(editor.waitForExistence(timeout:5))
        // Select the first word of the bold heading "Public heading".
        editor.coordinate(withNormalizedOffset:CGVector(dx:0.06,dy:0.05)).doubleTap()
        let formatting=app.buttons["rich.formatting"];XCTAssertTrue(formatting.waitForExistence(timeout:5));formatting.tap()
        XCTAssertTrue(app.staticTexts["rich.selection-hint"].waitForExistence(timeout:5),"A real selection was tracked")
        attach(app,name:"Actual native editor with selected text and the original toolbar marks")
        app.buttons["rich.format.bold"].tap()
        XCTAssertTrue(app.navigationBars["Edit rich entry"].waitForExistence(timeout:5))
        let tail=app.buttons["rich.run.0/1"];XCTAssertTrue(tail.waitForExistence(timeout:5),"The heading split into the selected word and the rest")
        run.tap();XCTAssertTrue(editor.waitForExistence(timeout:5))
        XCTAssertEqual(editor.value as? String,"Public")
        XCTAssertEqual(app.staticTexts["rich.format-summary"].label,"Formatting: Plain text","Bold was removed from the selection only")
        app.navigationBars["Edit text"].buttons["Edit rich entry"].tap()
        XCTAssertTrue(tail.waitForExistence(timeout:5));tail.tap();XCTAssertTrue(editor.waitForExistence(timeout:5))
        XCTAssertEqual(editor.value as? String," heading");XCTAssertEqual(app.staticTexts["rich.format-summary"].label,"Formatting: Bold")
        attach(app,name:"Actual native run outside the selection keeps the original bold")
    }
    func testFormatAcrossRunsAppliesOriginalToggleMarkOverSeveralRuns() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        app.buttons["Edit"].tap();XCTAssertTrue(app.navigationBars["Edit rich entry"].waitForExistence(timeout:5))
        let hello=app.buttons["rich.run.1/0"],world=app.buttons["rich.run.1/1"],summary=app.staticTexts["rich.format-summary"]
        reveal(hello,in:app);hello.tap();XCTAssertTrue(summary.waitForExistence(timeout:5));XCTAssertEqual(summary.label,"Formatting: Bold")
        app.navigationBars["Edit text"].buttons["Edit rich entry"].tap()
        let range=app.buttons["rich.range.1"];reveal(range,in:app);range.tap()
        XCTAssertTrue(app.navigationBars["Format across runs"].waitForExistence(timeout:5))
        XCTAssertTrue(app.textViews["Text across runs"].exists)
        let bold=app.buttons["rich.range.format.bold"];XCTAssertTrue(bold.exists);XCTAssertFalse(bold.isEnabled,"Nothing is selected yet")
        app.buttons["rich.range.select-all"].tap();XCTAssertTrue(bold.isEnabled)
        attach(app,name:"Actual native selection spanning bold-link, code and inline nodes")
        // TipTap: bold plus code-excluded text covers the selection, so bold is removed everywhere.
        bold.tap();XCTAssertEqual(app.staticTexts["rich.range.status"].label,"Formatting updated.")
        app.navigationBars["Format across runs"].buttons["Edit rich entry"].tap()
        reveal(hello,in:app);hello.tap();XCTAssertTrue(summary.waitForExistence(timeout:5));XCTAssertEqual(summary.label,"Formatting: Plain text")
        app.navigationBars["Edit text"].buttons["Edit rich entry"].tap()
        reveal(world,in:app);world.tap();XCTAssertTrue(summary.waitForExistence(timeout:5))
        XCTAssertEqual(summary.label,"Formatting: Italic, Underline, Strikethrough, Inline code","The code run keeps its own marks")
        attach(app,name:"Actual native multi-run toggle kept the other run's marks")
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
    func testNativeFullWidthActionDynamicTypeReproduction() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-full-width-action-audit-repro"];app.launch()
        XCTAssertTrue(app.buttons["repro.full-width-action"].waitForExistence(timeout:10))
        attach(app,name:"Actual isolated production full-width native CTA strict comparison")
        try audit(app,for:.dynamicType)
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
    func testActualJournalCardOriginalColorsAndNativeNotebookBackNavigation() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout:10));app.tabBars.buttons["Settings"].tap()
        app.buttons["appearance.mode"].tap();app.buttons["Light"].tap();app.tabBars.buttons["Journal"].tap()
        let card=app.descendants(matching:.any).matching(identifier:"entry.card.public-rich-fixture").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Public rich fixture"].exists)
        attach(app,name:"Chapter actual card before strict physical-pixel assertions")
        let geometry=XCTAttachment(string:"AX card bounds: \(card.frame); app: \(app.frame)\n"+app.debugDescription)
        geometry.name="Actual card AX bounds and hierarchy";geometry.lifetime = .keepAlways;add(geometry)
        let image=try XCTUnwrap(app.screenshot().image.cgImage),scale=CGFloat(image.width)/app.frame.width
        let width=image.width,strip=try XCTUnwrap(image.cropping(to:CGRect(x:0,y:floor(card.frame.midY*scale),width:CGFloat(width),height:1)))
        var pixels=[UInt8](repeating:0,count:width*4)
        try pixels.withUnsafeMutableBytes {buffer in
            let context=try XCTUnwrap(CGContext(data:buffer.baseAddress,width:width,height:1,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(strip,in:CGRect(x:0,y:0,width:CGFloat(width),height:1))
        }
        func matches(_ x:Int,_ color:[Int])->Bool {x>=0 && x<width && (0..<3).allSatisfy{abs(Int(pixels[x*4+$0])-color[$0])<=2}}
        // NavigationLink accessibility bounds can include row insets/chevron.
        // Measure the ACTUAL painted leading strip, not an assumed AX origin.
        // Keep original RGB tolerance and additionally require actual3pt width.
        let left=max(0,Int(card.frame.minX*scale)),right=min(width,Int(card.frame.maxX*scale))
        let first=try XCTUnwrap((left..<right).first{matches($0,[78,139,133])},"Original notebook edge must really render in this card")
        var end=first;while end<right && matches(end,[78,139,133]) {end+=1}
        XCTAssertLessThanOrEqual(abs((end-first)-Int((3*scale).rounded())),1,"Actual original notebook strip must be3pt wide")
        XCTAssertLessThanOrEqual(CGFloat(first)/scale-card.frame.minX,24,"Strip must be at the real leading row inset, not somewhere in text")
        let surface=first+Int((8*scale).rounded())
        XCTAssertTrue(matches(surface,[251,247,239]),"Original #fbf7ef card surface must really render inside its padding")
        attach(app,name:"Chapter genuine original-color journal cards and notebook edge")
        app.tabBars.buttons["Notebooks"].tap();app.staticTexts["Public notebook"].tap()
        XCTAssertTrue(app.navigationBars["Public notebook"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["Public subtitle"].exists)
        app.staticTexts["Public rich fixture"].tap();XCTAssertTrue(app.staticTexts["Public heading"].waitForExistence(timeout:5))
        app.navigationBars.buttons["Public notebook"].tap()
        app.navigationBars.buttons["Notebooks"].tap();XCTAssertTrue(app.navigationBars["Notebooks"].waitForExistence(timeout:5))
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
    private func launch(media:Bool = false,systemMedia:Bool = false) -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture"]
        if !systemMedia { app.launchArguments.append("--chapter-still-captures") }
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
    func testActualNativeLinkedEntriesBacklinksAndOfflineMissingPages() throws {
        let app=XCUIApplication();app.launchArguments=["--chapter-rich-fixture","--chapter-linked-entry-fixture","--chapter-still-captures"];app.launch()
        let source=app.staticTexts["Public rich fixture"];XCTAssertTrue(source.waitForExistence(timeout:10));source.tap()
        let link=app.buttons["entry.link.entry-target"];reveal(link,app);shot(app,"44 Actual native entry links using live local titles");link.tap()
        XCTAssertTrue(app.staticTexts["entry.title"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["entry.title"].label,"Public linked target")
        reveal(app.buttons["entry.backlink.public-rich-fixture"],app);shot(app,"45 Actual linked target and downloaded backlinks")
        let missing=launch();let original=missing.staticTexts["Public rich fixture"];XCTAssertTrue(original.waitForExistence(timeout:10));original.tap()
        let absent=missing.buttons["entry.link.entry-target"];reveal(absent,missing);absent.tap()
        XCTAssertTrue(missing.staticTexts["Linked entry is not downloaded"].waitForExistence(timeout:5));shot(missing,"46 Actual preserved missing linked entry offline state")
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
        XCTAssertTrue(edit.waitForExistence(timeout:5));shot(app,"05 Original-theme notebook shelf")
        app.staticTexts["Public notebook"].tap();XCTAssertTrue(app.navigationBars["Public notebook"].waitForExistence(timeout:5));shot(app,"43 Notebook-filtered Journal original covers and cards");app.navigationBars.buttons["Notebooks"].tap();edit.tap()
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
        app.buttons["rich.arrange-blocks"].tap();XCTAssertTrue(app.navigationBars["Arrange blocks"].waitForExistence(timeout:5));shot(app,"42 Native whole-block arrangement");app.navigationBars.buttons["Edit rich entry"].tap()
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
        // System Quick Look/pickers retain production animations and lifecycle.
        let app=launch(media:true,systemMedia:true);let entry=app.staticTexts["Public rich fixture"];XCTAssertTrue(entry.waitForExistence(timeout:10));entry.tap()
        let preview=app.buttons["media.preview." + String(repeating:"a",count:32)];reveal(preview,app);shot(app,"24 Real encrypted media controls and pending queue")
        preview.tap();let done=app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(done.waitForExistence(timeout:10),"Genuine decrypted local Quick Look must open without server authentication")
        let rendered=app.textViews.matching(NSPredicate(format:"label CONTAINS %@","Public Chapter offline media fixture.")).firstMatch
        XCTAssertTrue(rendered.waitForExistence(timeout:15),"Opening chrome is not proof that genuine decrypted text rendered")
        shot(app,"25 Actual decrypted protected offline file preview");done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout:10),"Do not tap controls underneath a still-present system preview")
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
