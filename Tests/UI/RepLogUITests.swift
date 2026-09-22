import XCTest

/// XCUITest covers every text-entry flow, because agent-device's keystroke
/// injection does not update SwiftUI @State bindings (plan §7.3):
///   - RPE entry (numeric pad + chips)
///   - exercise search
///   - sync URL + token
///   - set notes
/// agent-device handles navigation and screenshots; this drives the typing.
///
/// Every element the test touches carries an explicit accessibilityIdentifier
/// (set in the views), and the test addresses them by identifier subscript —
/// deterministic, independent of localisation or label composition.
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
    private func wait(for element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let exp = NSPredicate(format: "exists == true")
        let ok = expectation(for: exp, evaluatedWith: element, handler: nil)
        wait(for: [ok], timeout: timeout)
        return element.exists
    }

    /// Walk onboarding (units -> privacy -> skip sync) to the Log tab.
    private func completeOnboarding() {
        let next = app.buttons["onboarding-next"]
        XCTAssertTrue(wait(for: next), "onboarding 'Continue' not found")
        next.tap()
        XCTAssertTrue(wait(for: app.buttons["onboarding-next"]), "second 'Continue' not found")
        app.buttons["onboarding-next"].tap()
        // Third page shows "Get Started" (same identifier).
        let start = app.buttons["onboarding-next"]
        XCTAssertTrue(wait(for: start), "'Get Started' not found")
        start.tap()
    }

    /// Tap the Log "+" button and start a fresh workout (ActiveWorkoutView).
    private func startFreshWorkout() {
        let plus = app.buttons["plus"]
        XCTAssertTrue(wait(for: plus), "'plus' toolbar button not found")
        plus.tap()
        let today = app.buttons["new-workout-today"]
        XCTAssertTrue(wait(for: today), "'New Workout (Today)' not found")
        today.tap()
        XCTAssertTrue(wait(for: app.buttons["add-exercise"]), "Active workout not shown")
    }

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    private func addFirstExercise() {
        app.buttons["add-exercise"].tap()
        let absCat = app.buttons["category-Abs"]
        XCTAssertTrue(wait(for: absCat), "'Abs' category not found")
        absCat.tap()
        let abWheel = app.buttons["pick-Ab Wheel"]
        XCTAssertTrue(wait(for: abWheel), "'Ab Wheel' not found")
        abWheel.tap()
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
        let done = app.buttons["done"]
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
        // "Abs" should be filtered out.
        let gone = !app.buttons["category-Abs"].exists
        XCTAssertTrue(gone, "'Abs' should be filtered out when searching 'Squat'")
    }

    // MARK: - Sync URL + token

    func testSyncURLAndTokenFields() {
        completeOnboarding()
        // Profile tab is the 4th tab (index 3); SwiftUI does not propagate
        // accessibilityIdentifier to .tabItem, so target it positionally.
        let profile = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(wait(for: profile), "'Profile' tab not found")
        profile.tap()
        let settings = app.buttons["settings-link"]
        XCTAssertTrue(wait(for: settings), "'Settings' not found in Profile")
        settings.tap()

        // Scroll to the Sync section.
        let toggle = app.switches["enable-sync"]
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
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

        let done = app.buttons["done"]
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
        let save = app.buttons["save-note"]
        XCTAssertTrue(wait(for: save), "note 'Save' not found")
        save.tap()

        // The note renders as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"]
        XCTAssertTrue(wait(for: noteLine), "set note 'felt heavy' not displayed")
    }
}
