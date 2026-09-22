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

    /// Wait until the element exists; returns whether it appeared.
    private func wait(for element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let exp = NSPredicate(format: "exists == true")
        let ok = expectation(for: exp, evaluatedWith: element, handler: nil)
        waitForExpectations([ok], timeout: timeout)
        return element.exists
    }

    /// Walk past onboarding (units -> privacy -> sync) to the Log tab.
    private func completeOnboarding() {
        // Page 1: pick kg (default), Continue
        let continueBtn = app.buttons["Continue"]
        XCTAssertTrue(wait(for: continueBtn), "onboarding Continue not found")
        continueBtn.tap()
        // Page 2: Continue
        XCTAssertTrue(wait(for: app.buttons["Continue"]), "second Continue not found")
        app.buttons["Continue"].tap()
        // Page 3: Get Started (skip sync)
        let start = app.buttons["Get Started"]
        XCTAssertTrue(wait(for: start), "Get Started not found")
        start.tap()
    }

    /// Start a workout and add the first exercise, landing on the active
    /// workout screen with one exercise card.
    private func startWorkoutWithOneExercise() {
        app.buttons["plus"].tap()
        XCTAssertTrue(wait(for: app.buttons["New Workout (Today)"]), "New Workout not found")
        app.buttons["New Workout (Today)"].tap()
        XCTAssertTrue(wait(for: app.buttons["Add Exercise"]), "Add Exercise not found")
        app.buttons["Add Exercise"].tap()
        // Category list -> tap first category row.
        let firstCategory = app.tables.firstMatch.cells.firstMatch
        XCTAssertTrue(wait(for: firstCategory), "no category row")
        firstCategory.tap()
        // Variant list: the first exercise is a button whose label contains
        // the exercise name. Use the first button in the list.
        let firstExercise = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'exercise-'")
        ).firstMatch
        XCTAssertTrue(wait(for: firstExercise), "no exercise row")
        firstExercise.tap()
    }

    // MARK: - RPE entry

    func testRPEEntryTypes85AndReadsBack() {
        completeOnboarding()
        startWorkoutWithOneExercise()
        // The RPE column: a button whose label contains "RPE".
        let rpeCell = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'RPE'")
        ).firstMatch
        XCTAssertTrue(wait(for: rpeCell), "RPE cell not found")
        rpeCell.tap()
        // RPE sheet: type 8.5 into the field.
        let field = app.textFields["rpe-field"]
        XCTAssertTrue(wait(for: field), "RPE field not found")
        field.tap()
        field.typeText("8.5")
        let done = app.buttons["Done"]
        XCTAssertTrue(wait(for: done), "RPE Done not found")
        done.tap()
        // Read it back: a button whose label contains both RPE and 8.5.
        let rpeValue = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'RPE' AND label CONTAINS '8.5'")
        ).firstMatch
        XCTAssertTrue(wait(for: rpeValue), "RPE 8.5 not shown after entry")
    }

    // MARK: - Exercise search

    func testExerciseSearchFilters() {
        completeOnboarding()
        app.buttons["plus"].tap()
        XCTAssertTrue(wait(for: app.buttons["New Workout (Today)"]), "New Workout not found")
        app.buttons["New Workout (Today)"].tap()
        XCTAssertTrue(wait(for: app.buttons["Add Exercise"]), "Add Exercise not found")
        app.buttons["Add Exercise"].tap()
        // Search field.
        let search = app.textFields["exercise-search"]
        XCTAssertTrue(wait(for: search), "search field not found")
        search.tap()
        search.typeText("Squat")
        // The list should now show only Squat exercises.
        let squatRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Squat'")
        ).firstMatch
        XCTAssertTrue(wait(for: squatRow), "no Squat result after search")
    }

    // MARK: - Sync URL + token

    func testSyncURLAndTokenFields() {
        completeOnboarding()
        // Profile tab.
        app.tabBars.buttons["Profile"].tap()
        // Open Settings.
        let settingsBtn = app.buttons["Settings"]
        XCTAssertTrue(wait(for: settingsBtn), "Settings not found")
        settingsBtn.tap()
        // Scroll to the Sync section.
        for _ in 0..<8 {
            let syncToggle = app.switches.matching(
                NSPredicate(format: "label CONTAINS[c] 'Enable Sync'")
            ).firstMatch
            if wait(for: syncToggle, timeout: 1) {
                syncToggle.tap()
                break
            }
            app.swipeUp()
        }
        // URL field.
        let url = app.textFields["sync-url-field"]
        XCTAssertTrue(wait(for: url), "sync URL field not found")
        url.tap()
        url.typeText("http://192.168.1.12:8080")
        // Token field.
        let token = app.secureTextFields["sync-token-field"]
        XCTAssertTrue(wait(for: token), "sync token field not found")
        token.tap()
        token.typeText("test-token-123")
        // Save.
        let done = app.buttons["Done"]
        XCTAssertTrue(wait(for: done), "Settings Done not found")
        done.tap()
    }

    // MARK: - Set notes

    func testSetNoteEntry() {
        completeOnboarding()
        startWorkoutWithOneExercise()
        // Tap the Notes column of the first set row.
        let notesCell = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Notes'")
        ).firstMatch
        XCTAssertTrue(wait(for: notesCell), "Notes cell not found")
        notesCell.tap()
        // Set note sheet.
        let field = app.textFields.matching(
            NSPredicate(format: "label CONTAINS[c] 'Note for set'")
        ).firstMatch
        XCTAssertTrue(wait(for: field), "set note field not found")
        field.tap()
        field.typeText("felt heavy")
        let save = app.buttons["Save"]
        XCTAssertTrue(wait(for: save), "note Save not found")
        save.tap()
        // The note should render as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"].firstMatch
        XCTAssertTrue(wait(for: noteLine), "set note not displayed")
    }
}
