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
/// (set in the views), and the test addresses them by identifier subscript.
/// SwiftUI page/sheet transitions animate, so every tap is followed by a
/// settle delay (tapSettled) — taps fired mid-animation are dropped.
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

    /// Let the UI settle after a transition (page change, sheet, navigation).
    private func settle(_ seconds: Double = 1.5) {
        let delay = expectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { delay.fulfill() }
        wait(for: [delay], timeout: seconds + 5)
    }

    /// Tap, then settle so the next action sees a stable UI.
    private func tapSettled(_ element: XCUIElement) {
        element.tap()
        settle()
    }

    /// Walk onboarding (units -> privacy -> skip sync) to the Log tab.
    @MainActor
    private func completeOnboarding() async {
        for _ in 0..<3 {
            let next = app.buttons["onboarding-next"]
            guard wait(for: next) else { break }
            next.tap()
            settle()
        }
        // The main app is up: the Log "+" button is present.
        XCTAssertTrue(wait(for: app.buttons["plus"]), "main app not shown after onboarding")
    }

    /// Tap the Log "+" button and start a fresh workout (ActiveWorkoutView).
    @MainActor
    private func startFreshWorkout() async {
        let plus = app.buttons["plus"]
        XCTAssertTrue(wait(for: plus), "'plus' toolbar button not found")
        tapSettled(plus)
        let today = app.buttons["new-workout-today"]
        XCTAssertTrue(wait(for: today), "'New Workout (Today)' not found")
        tapSettled(today)
        XCTAssertTrue(wait(for: app.buttons["add-exercise"]), "Active workout not shown")
    }

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    @MainActor
    private func addFirstExercise() async {
        tapSettled(app.buttons["add-exercise"])
        let absCat = app.buttons["category-Abs"]
        XCTAssertTrue(wait(for: absCat), "'Abs' category not found")
        tapSettled(absCat)
        let abWheel = app.buttons["pick-Ab Wheel"]
        XCTAssertTrue(wait(for: abWheel), "'Ab Wheel' not found")
        tapSettled(abWheel)
        XCTAssertTrue(wait(for: app.buttons["rpe-cell"]), "RPE cell not shown after adding exercise")
    }

    // MARK: - RPE entry

    @MainActor
    func testRPEEntryTypes85AndReadsBack() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        tapSettled(app.buttons["rpe-cell"])
        let field = app.textFields["rpe-field"]
        XCTAssertTrue(wait(for: field), "RPE field not found")
        field.tap()
        field.typeText("8.5")
        let done = app.buttons["done"]
        XCTAssertTrue(wait(for: done), "RPE 'Done' not found")
        tapSettled(done)

        // Read it back: the RPE cell now shows 8.5.
        let rpeCell = app.buttons["rpe-cell"]
        XCTAssertTrue(wait(for: rpeCell), "RPE cell missing after entry")
        let label = rpeCell.label ?? ""
        XCTAssertTrue(label.contains("8.5"), "RPE cell should read 8.5, got '\(label)'")
    }

    // MARK: - Exercise search

    @MainActor
    func testExerciseSearchFilters() async {
        await completeOnboarding()
        await startFreshWorkout()
        tapSettled(app.buttons["add-exercise"])

        let search = app.textFields["exercise-search"]
        XCTAssertTrue(wait(for: search), "search field not found")
        search.tap()
        search.typeText("Squat")
        settle(1)

        // The category list now shows only "Squats".
        let squats = app.buttons["category-Squats"]
        XCTAssertTrue(wait(for: squats), "'Squats' category not shown after searching 'Squat'")
        // "Abs" should be filtered out.
        let gone = !app.buttons["category-Abs"].exists
        XCTAssertTrue(gone, "'Abs' should be filtered out when searching 'Squat'")
    }

    // MARK: - Sync URL + token

    @MainActor
    func testSyncURLAndTokenFields() async {
        await completeOnboarding()
        // Profile tab is the 4th tab (index 3); SwiftUI does not propagate
        // accessibilityIdentifier to .tabItem, so target it positionally.
        let profile = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(wait(for: profile), "'Profile' tab not found")
        tapSettled(profile)
        let settings = app.buttons["settings-link"]
        XCTAssertTrue(wait(for: settings), "'Settings' not found in Profile")
        tapSettled(settings)

        // Scroll to the Sync section.
        let toggle = app.switches["enable-sync"]
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
            settle(0.5)
        }
        XCTAssertTrue(toggle.exists, "'Enable Sync' toggle not found")
        tapSettled(toggle)

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
        tapSettled(done)
    }

    // MARK: - Set notes

    @MainActor
    func testSetNoteEntry() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        tapSettled(app.buttons["notes-cell"])
        let field = app.textFields["set-note-field"]
        XCTAssertTrue(wait(for: field), "set note field not found")
        field.tap()
        field.typeText("felt heavy")
        let save = app.buttons["save-note"]
        XCTAssertTrue(wait(for: save), "note 'Save' not found")
        tapSettled(save)

        // The note renders as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"]
        XCTAssertTrue(wait(for: noteLine), "set note 'felt heavy' not displayed")
    }
}
