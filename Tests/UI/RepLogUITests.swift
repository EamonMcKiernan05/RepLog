import XCTest

/// XCUITest covers every text-entry flow, because agent-device's keystroke
/// injection does not update SwiftUI @State bindings (plan §7.3):
///   - RPE entry (numeric pad + chips)
///   - exercise search
///   - sync URL + token
///   - set notes
/// agent-device handles navigation and screenshots; this drives the typing.
final class RepLogUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-ResetRepLog", "YES"]
        app.launch()
    }

    /// Walk past onboarding (units -> privacy -> sync) to the Log tab.
    private func completeOnboarding() {
        // Page 1: pick kg (default), Continue
        let continueBtn = app.buttons["Continue"]
        XCTAssertTrue(waitFor(continueBtn), "onboarding Continue not found")
        continueBtn.tap()
        // Page 2: Continue
        waitFor(app.buttons["Continue"]).tap()
        // Page 3: Get Started (skip sync)
        let start = app.buttons["Get Started"]
        XCTAssertTrue(waitFor(start), "Get Started not found")
        start.tap()
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 8) -> XCUIElement {
        let exp = NSPredicate(format: "exists == true")
        let ok = expectation(for: exp, evaluatedWith: element, handler: nil)
        wait(for: [ok], timeout: timeout)
        return element
    }

    // MARK: - RPE entry

    func testRPEEntryTypes85AndReadsBack() {
        completeOnboarding()
        // Start a workout.
        app.buttons["plus"].tap()
        waitFor(app.buttons["New Workout (Today)"]).tap()
        // Add an exercise: open the sheet, pick a category, pick the first exercise.
        waitFor(app.buttons["Add Exercise"]).tap()
        // Category list -> tap first category row.
        let firstCategory = app.tables.firstMatch.cells.firstMatch
        XCTAssertTrue(waitFor(firstCategory), "no category row")
        firstCategory.tap()
        // Now the variant list; tap the first exercise row (a button).
        let firstExercise = app.buttons.matching(identifier: "exercise-*").firstMatch
        // Fallback: the first button in the list.
        let row = waitFor(app.buttons.matching(identifier: "exercise-*").firstMatch)
        row.tap()
        // Now we are in the active workout with one exercise card.
        // The RPE column is a button labelled with "RPE" header + a value.
        // Tap the RPE cell: it's a button whose label contains "RPE".
        let rpeCell = app.buttons.matching { b in
            b.label.contains("RPE")
        }.firstMatch
        XCTAssertTrue(waitFor(rpeCell), "RPE cell not found")
        rpeCell.tap()
        // RPE sheet: type 8.5 into the field.
        let field = waitFor(app.textFields["rpe-field"])
        field.tap()
        field.typeText("8.5")
        waitFor(app.buttons["Done"]).tap()
        // Read it back: the RPE cell should now show 8.5.
        let rpeValue = app.buttons.matching { b in
            b.label.contains("8.5") && b.label.contains("RPE")
        }.firstMatch
        XCTAssertTrue(waitFor(rpeValue), "RPE 8.5 not shown after entry")
    }

    // MARK: - Exercise search

    func testExerciseSearchFilters() {
        completeOnboarding()
        app.buttons["plus"].tap()
        waitFor(app.buttons["New Workout (Today)"]).tap()
        waitFor(app.buttons["Add Exercise"]).tap()
        // Search field.
        let search = waitFor(app.textFields["exercise-search"])
        search.tap()
        search.typeText("Squat")
        // The list should now show only Squat exercises.
        let squatRow = app.buttons.matching { b in
            b.label.localizedCaseInsensitiveContains("Squat")
        }.firstMatch
        XCTAssertTrue(waitFor(squatRow), "no Squat result after search")
    }

    // MARK: - Sync URL + token

    func testSyncURLAndTokenFields() {
        completeOnboarding()
        // Profile tab.
        app.tabBars.buttons["Profile"].tap()
        // Open Settings.
        waitFor(app.buttons["Settings"]).tap()
        // Scroll to the Sync section.
        let syncToggle = app.switches.matching { s in
            s.label.contains("Enable Sync")
        }.firstMatch
        scrollSyncIntoView()
        XCTAssertTrue(waitFor(syncToggle), "Enable Sync toggle not found")
        syncToggle.tap()
        // URL field.
        let url = waitFor(app.textFields["sync-url-field"])
        url.tap()
        url.typeText("http://192.168.1.12:8080")
        // Token field.
        let token = waitFor(app.secureTextFields["sync-token-field"])
        token.tap()
        token.typeText("test-token-123")
        // Save.
        waitFor(app.buttons["Done"]).tap()
    }

    private func scrollSyncIntoView() {
        // Best-effort scroll; the toggle may already be visible.
        for _ in 0..<6 {
            if app.switches.matching { $0.label.contains("Enable Sync") }.firstMatch.exists {
                return
            }
            app.swipeUp()
        }
    }

    // MARK: - Set notes

    func testSetNoteEntry() {
        completeOnboarding()
        app.buttons["plus"].tap()
        waitFor(app.buttons["New Workout (Today)"]).tap()
        waitFor(app.buttons["Add Exercise"]).tap()
        let firstCategory = app.tables.firstMatch.cells.firstMatch
        waitFor(firstCategory).tap()
        let firstExercise = waitFor(app.buttons.matching(identifier: "exercise-*").firstMatch)
        firstExercise.tap()
        // Tap the Notes column of the first set row.
        let notesCell = app.buttons.matching { b in
            b.label.contains("Notes")
        }.firstMatch
        XCTAssertTrue(waitFor(notesCell), "Notes cell not found")
        notesCell.tap()
        // Set note sheet.
        let field = waitFor(app.textFields.matching { t in
            t.label.contains("Note for set")
        }.firstMatch)
        field.tap()
        field.typeText("felt heavy")
        waitFor(app.buttons["Save"]).tap()
        // The note should render as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"].firstMatch
        XCTAssertTrue(waitFor(noteLine), "set note not displayed")
    }
}
