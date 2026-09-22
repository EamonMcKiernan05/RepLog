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
    /// Async polling (not waitForExpectations) so it is safe on the main actor.
    @MainActor
    private func wait(for element: XCUIElement, timeout: TimeInterval = 10) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return element.exists
    }

    /// Let the UI settle after a transition (page change, sheet, navigation).
    @MainActor
    private func settle(_ seconds: Double = 1.5) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Tap, then settle so the next action sees a stable UI.
    @MainActor
    private func tapSettled(_ element: XCUIElement) async {
        element.tap()
        await settle()
    }


    /// Wait for an element and assert it appeared (autoclosures can't await).
    @MainActor
    private func expectExists(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 10) async {
        let ok = await wait(for: element, timeout: timeout)
        XCTAssertTrue(ok, message)
    }

    /// Walk onboarding (units -> privacy -> skip sync) to the Log tab.
    @MainActor
    private func completeOnboarding() async {
        for _ in 0..<3 {
            let next = app.buttons["onboarding-next"]
            guard await wait(for: next) else { break }
            next.tap()
            await settle()
        }
        // The main app is up: the Log "+" button is present.
        await expectExists(app.buttons["plus"]), "main app not shown after onboarding")
    }

    /// Tap the Log "+" button and start a fresh workout (ActiveWorkoutView).
    @MainActor
    private func startFreshWorkout() async {
        let plus = app.buttons["plus"]
        await expectExists(plus), "'plus' toolbar button not found")
        await tapSettled(plus)
        let today = app.buttons["new-workout-today"]
        await expectExists(today), "'New Workout (Today)' not found")
        await tapSettled(today)
        await expectExists(app.buttons["add-exercise"]), "Active workout not shown")
    }

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    @MainActor
    private func addFirstExercise() async {
        await tapSettled(app.buttons["add-exercise"])
        let absCat = app.buttons["category-Abs"]
        await expectExists(absCat), "'Abs' category not found")
        await tapSettled(absCat)
        let abWheel = app.buttons["pick-Ab Wheel"]
        await expectExists(abWheel), "'Ab Wheel' not found")
        await tapSettled(abWheel)
        await expectExists(app.buttons["rpe-cell"]), "RPE cell not shown after adding exercise")
    }

    // MARK: - RPE entry

    @MainActor
    func testRPEEntryTypes85AndReadsBack() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["rpe-cell"])
        let field = app.textFields["rpe-field"]
        await expectExists(field), "RPE field not found")
        field.tap()
        field.typeText("8.5")
        let done = app.buttons["done"]
        await expectExists(done), "RPE 'Done' not found")
        await tapSettled(done)

        // Read it back: the RPE cell now shows 8.5.
        let rpeCell = app.buttons["rpe-cell"]
        await expectExists(rpeCell), "RPE cell missing after entry")
        let label = rpeCell.label ?? ""
        XCTAssertTrue(label.contains("8.5"), "RPE cell should read 8.5, got '\(label)'")
    }

    // MARK: - Exercise search

    @MainActor
    func testExerciseSearchFilters() async {
        await completeOnboarding()
        await startFreshWorkout()
        await tapSettled(app.buttons["add-exercise"])

        let search = app.textFields["exercise-search"]
        await expectExists(search), "search field not found")
        search.tap()
        search.typeText("Squat")
        await settle(1)

        // The category list now shows only "Squats".
        let squats = app.buttons["category-Squats"]
        await expectExists(squats), "'Squats' category not shown after searching 'Squat'")
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
        await expectExists(profile), "'Profile' tab not found")
        await tapSettled(profile)
        let settings = app.buttons["settings-link"]
        await expectExists(settings), "'Settings' not found in Profile")
        await tapSettled(settings)

        // Scroll to the Sync section.
        let toggle = app.switches["enable-sync"]
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
            await settle(0.5)
        }
        XCTAssertTrue(toggle.exists, "'Enable Sync' toggle not found")
        await tapSettled(toggle)

        let url = app.textFields["sync-url-field"]
        await expectExists(url), "sync URL field not found")
        url.tap()
        url.typeText("http://192.168.1.12:8080")

        let token = app.secureTextFields["sync-token-field"]
        await expectExists(token), "sync token field not found")
        token.tap()
        token.typeText("test-token-123")

        let done = app.buttons["done"]
        await expectExists(done), "Settings 'Done' not found")
        await tapSettled(done)
    }

    // MARK: - Set notes

    @MainActor
    func testSetNoteEntry() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["notes-cell"])
        let field = app.textFields["set-note-field"]
        await expectExists(field), "set note field not found")
        field.tap()
        field.typeText("felt heavy")
        let save = app.buttons["save-note"]
        await expectExists(save), "note 'Save' not found")
        await tapSettled(save)

        // The note renders as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"]
        await expectExists(noteLine), "set note 'felt heavy' not displayed")
    }
}
