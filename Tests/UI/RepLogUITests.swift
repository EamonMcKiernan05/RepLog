import XCTest

/// XCUITest covers every text-entry flow, because agent-device's keystroke
/// injection does not update SwiftUI @State bindings (plan §7.3):
///   - RPE entry (numeric pad + chips)
///   - exercise search
///   - sync URL + token
///   - set notes
/// agent-device handles navigation and screenshots; this drives the typing.
///
/// Element strategy (verified against the live accessibility tree):
///   - Buttons are matched by accessibility *label* (toolbar "+", menu items,
///     sheet rows, categories, exercises, tab bar) — `app.buttons["x"]` would
///     query by identifier, which these don't carry.
///   - Text fields are matched by accessibility *identifier* (rpe-field,
///     set-note-field, exercise-search, sync-url-field, sync-token-field).
///   - Set-row RPE / Notes columns carry identifiers (rpe-cell, notes-cell).
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

    /// A button matched by its accessibility label.
    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Walk onboarding (units -> privacy -> skip sync) to the Log tab.
    private func completeOnboarding() {
        let cont = button("Continue")
        XCTAssertTrue(wait(for: cont), "onboarding 'Continue' not found")
        cont.tap()
        XCTAssertTrue(wait(for: button("Continue")), "second 'Continue' not found")
        button("Continue").tap()
        let start = button("Get Started")
        XCTAssertTrue(wait(for: start), "'Get Started' not found")
        start.tap()
    }

    /// Open the Log "+" menu and start a fresh workout (ActiveWorkoutView).
    private func startFreshWorkout() {
        let plus = button("Add workout")
        XCTAssertTrue(wait(for: plus), "'Add workout' toolbar button not found")
        plus.tap()
        let new = button("New Workout")
        XCTAssertTrue(wait(for: new), "'New Workout' menu item not found")
        new.tap()
        let today = button("New Workout (Today)")
        XCTAssertTrue(wait(for: today), "'New Workout (Today)' not found")
        today.tap()
        XCTAssertTrue(wait(for: button("Add Exercise")), "Active workout not shown")
    }

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    private func addFirstExercise() {
        button("Add Exercise").tap()
        let absCat = button("Abs")
        XCTAssertTrue(wait(for: absCat), "'Abs' category not found")
        absCat.tap()
        let abWheel = button("Ab Wheel")
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
        let done = button("Done")
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
        button("Add Exercise").tap()

        let search = app.textFields["exercise-search"]
        XCTAssertTrue(wait(for: search), "search field not found")
        search.tap()
        search.typeText("Squat")

        // The category list now shows only "Squats".
        let squats = button("Squats")
        XCTAssertTrue(wait(for: squats), "'Squats' category not shown after searching 'Squat'")
        // "Abs" should be filtered out.
        let gone = !button("Abs").exists
        XCTAssertTrue(gone, "'Abs' should be filtered out when searching 'Squat'")
    }

    // MARK: - Sync URL + token

    func testSyncURLAndTokenFields() {
        completeOnboarding()
        // Profile tab -> Settings.
        let profile = app.tabBars.buttons.matching(NSPredicate(format: "label == 'Profile'")).firstMatch
        XCTAssertTrue(wait(for: profile), "'Profile' tab not found")
        profile.tap()
        let settings = button("Settings")
        XCTAssertTrue(wait(for: settings), "'Settings' not found in Profile")
        settings.tap()

        // Scroll to the Sync section.
        let toggle = app.switches.matching(NSPredicate(format: "label == 'Enable Sync'")).firstMatch
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

        let done = button("Done")
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
        let save = button("Save")
        XCTAssertTrue(wait(for: save), "note 'Save' not found")
        save.tap()

        // The note renders as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"]
        XCTAssertTrue(wait(for: noteLine), "set note 'felt heavy' not displayed")
    }
}
