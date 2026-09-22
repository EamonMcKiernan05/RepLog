import XCTest

/// XCUITest covers every text-entry flow, because agent-device's keystroke
/// injection does not update SwiftUI @State bindings (plan §7.3):
///   - RPE entry (numeric pad + chips)
///   - exercise search
///   - sync URL + token
///   - set notes
/// agent-device handles navigation and screenshots; this drives the typing.
///
/// The real UI flow (verified against the views):
///   Log "+" is a Menu -> "New Workout" -> StartWorkoutSheet ->
///   "New Workout (Today)" -> ActiveWorkoutView -> "Add Exercise" ->
///   SelectExerciseSheet -> category -> exercise.
final class RepLogUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // -ResetRepLog wipes persisted state so every test starts at onboarding.
        app.launchArguments += ["-ResetRepLog", "YES"]
        app.launch()
    }

    /// Wait until the element exists; returns whether it appeared.
    private func wait(for element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let exp = NSPredicate(format: "exists == true")
        let ok = expectation(for: exp, evaluatedWith: element, handler: nil)
        wait(for: [ok], timeout: timeout)
        return element.exists
    }

    /// Walk onboarding (units -> privacy -> skip sync) to the Log tab.
    private func completeOnboarding() {
        let cont = app.buttons["Continue"]
        XCTAssertTrue(wait(for: cont), "onboarding 'Continue' not found")
        cont.tap()
        XCTAssertTrue(wait(for: app.buttons["Continue"]), "second 'Continue' not found")
        app.buttons["Continue"].tap()
        let start = app.buttons["Get Started"]
        XCTAssertTrue(wait(for: start), "'Get Started' not found")
        start.tap()
    }

    /// Open the Log "+" menu and start a fresh workout (ActiveWorkoutView).
    private func startFreshWorkout() {
        let plus = app.buttons["plus"]
        XCTAssertTrue(wait(for: plus), "'+' menu not found")
        plus.tap()
        let new = app.buttons["New Workout"]
        XCTAssertTrue(wait(for: new), "'New Workout' menu item not found")
        new.tap()
        let today = app.buttons["new-workout-today"]
        XCTAssertTrue(wait(for: today), "'New Workout (Today)' not found")
        today.tap()
        // ActiveWorkoutView shows the "Add Exercise" button.
        XCTAssertTrue(wait(for: app.buttons["add-exercise"]), "Active workout not shown")
    }

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    private func addFirstExercise() {
        app.buttons["add-exercise"].tap()
        // Category list: first category is "Abs".
        let absCat = app.buttons["category-Abs"]
        XCTAssertTrue(wait(for: absCat), "'Abs' category not found")
        absCat.tap()
        // Category detail: first exercise is "Ab Wheel".
        let abWheel = app.buttons["pick-Ab Wheel"]
        XCTAssertTrue(wait(for: abWheel), "'Ab Wheel' not found")
        abWheel.tap()
        // Back on the active workout with one exercise card (RPE cell present).
        XCTAssertTrue(wait(for: app.buttons["rpe-cell"]), "RPE cell not shown after adding exercise")
    }

    // MARK: - RPE entry

    func testRPEEntryTypes85AndReadsBack() {
        completeOnboarding()
        startFreshWorkout()
        addFirstExercise()

        app.buttons["rpe-cell"].tap()
        let field = app.textFields["rpe-field"]
        XCTAssertTrue(wait(for: field), "RPE field not found")
        field.tap()
        field.typeText("8.5")
        let done = app.buttons["Done"]
        XCTAssertTrue(wait(for: done), "RPE 'Done' not found")
        done.tap()

        // Read it back: the RPE cell now shows 8.5.
        let rpeCell = app.buttons["rpe-cell"]
        XCTAssertTrue(wait(for: rpeCell), "RPE cell missing after entry")
        let label = rpeCell.label ?? ""
        XCTAssertTrue(label.contains("8.5"), "RPE cell should read 8.5, got '\(label)'")
    }

    // MARK: - Exercise search

    func testExerciseSearchFilters() {
        completeOnboarding()
        startFreshWorkout()
        app.buttons["add-exercise"].tap()

        let search = app.textFields["exercise-search"]
        XCTAssertTrue(wait(for: search), "search field not found")
        search.tap()
        search.typeText("Squat")

        // The category list now shows only "Squats".
        let squats = app.buttons["category-Squats"]
        XCTAssertTrue(wait(for: squats), "'Squats' category not shown after searching 'Squat'")
        // "Abs" should be gone.
        let absCat = app.buttons["category-Abs"]
        let gone = !absCat.exists
        XCTAssertTrue(gone, "'Abs' should be filtered out when searching 'Squat'")
    }

    // MARK: - Sync URL + token

    func testSyncURLAndTokenFields() {
        completeOnboarding()
        // Profile tab -> Settings.
        app.tabBars.buttons["Profile"].tap()
        let settings = app.buttons["Settings"]
        XCTAssertTrue(wait(for: settings), "'Settings' not found in Profile")
        settings.tap()

        // Scroll to the Sync section.
        var toggle = app.switches["Enable Sync"]
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
            toggle = app.switches["Enable Sync"]
        }
        XCTAssertTrue(toggle.exists, "'Enable Sync' toggle not found")
        toggle.tap()

        let url = app.textFields["sync-url-field"]
        XCTAssertTrue(wait(for: url), "sync URL field not found")
        url.tap()
        url.typeText("http://192.168.1.12:8080")

        let token = app.secureTextFields["sync-token-field"]
        XCTAssertTrue(wait(for: token), "sync token field not found")
        token.tap()
        token.typeText("test-token-123")

        let done = app.buttons["Done"]
        XCTAssertTrue(wait(for: done), "Settings 'Done' not found")
        done.tap()
    }

    // MARK: - Set notes

    func testSetNoteEntry() {
        completeOnboarding()
        startFreshWorkout()
        addFirstExercise()

        app.buttons["notes-cell"].tap()
        let field = app.textFields["set-note-field"]
        XCTAssertTrue(wait(for: field), "set note field not found")
        field.tap()
        field.typeText("felt heavy")
        let save = app.buttons["Save"]
        XCTAssertTrue(wait(for: save), "note 'Save' not found")
        save.tap()

        // The note renders as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"]
        XCTAssertTrue(wait(for: noteLine), "set note 'felt heavy' not displayed")
    }
}
