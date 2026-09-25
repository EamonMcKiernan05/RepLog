import XCTest
import SwiftUI
import CoreGraphics

/// XCUITest covers every text-entry flow, because agent-device's keystroke
/// injection does not update SwiftUI @State bindings (plan §7.3):
///   - RPE entry (numeric pad + chips)
///   - exercise search
///   - sync URL + token
///   - set notes
///   - the in-simulator offline drill (plan §7.5)
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

    /// Tap a Form toggle, then assert the value actually flipped.
    ///
    /// A SwiftUI Form does not toggle from a label tap, and the switch
    /// element spans the whole row, so both its centre and its top edge are
    /// the label. Normalised offsets are measured from the element's
    /// TOP-LEFT — (0,0) is the top-left corner, (1,1) the bottom-right — so
    /// the knob is at (0.92, 0.5): right edge, vertically centred.
    /// (Verified 2026-09-22: dx 0.45, dy 0 at the row's top edge is the
    /// label and flips nothing.)
    ///
    /// The value assertion is the point of this helper: if the toggle
    /// silently fails to flip, the next failure names the toggle instead of
    /// the URL field that never appeared.
    @MainActor
    private func tapSwitchKnob(_ toggle: XCUIElement) async {
        let before = (toggle.value as? String) ?? "?"
        if before != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            await settle()
        }
        let after = (toggle.value as? String) ?? "?"
        XCTAssertEqual(after, "1",
                       "toggle '\(toggle.identifier)' did not flip after a knob tap (value '\(before)' -> '\(after)')")
    }

    /// iOS offers to save the password after typing into the token's
    /// SecureField ("Save Password?"). It is a system alert: while it is up,
    /// every tap in the app is swallowed and the test stalls with a misleading
    /// failure (found in the 2026-09-22 run: the alert was up over the Log).
    @MainActor
    private func dismissSavePasswordPrompt() async {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Not Now", "Never for This Website", "Not now", "Later"]
        let deadline = Date().addingTimeInterval(8)
        let hosts: [XCUIApplication] = [app, springboard]
        while Date() < deadline {
            for host in hosts {
                for label in labels where host.buttons[label].exists {
                    host.buttons[label].tap()
                    await settle()
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    /// The Log's session rows carry `session-row-<first 8 of the id>`
    /// (SessionRowView.swift), so an exact subscript — `app.buttons["session-row-"]`
    /// — can never match. A BEGINSWITH predicate query is the only way in.
    @MainActor
    private func firstSessionRow() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session-row-'")).firstMatch
    }

    /// Wait for the first session row in the Log. On failure, dump every
    /// element whose identifier starts with "session-row" so the next run
    /// says whether the row is a button, an otherElement, or absent.
    @MainActor
    @discardableResult
    private func expectSessionRow(_ message: String, timeout: TimeInterval = 15) async -> XCUIElement {
        let row = firstSessionRow()
        if await wait(for: row, timeout: timeout) { return row }
        let ids = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session-row'"))
            .allElementsBoundByIndex
            .map { "\($0.elementType.rawValue):\($0.identifier)" }
        XCTFail("\(message) — elements matching 'session-row*': \(ids)")
        return row
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
        await expectExists(app.buttons["plus"], "main app not shown after onboarding")
    }

    /// Tap the Log "+" button and start a fresh workout (ActiveWorkoutView).
    @MainActor
    private func startFreshWorkout() async {
        let plus = app.buttons["plus"]
        await expectExists(plus, "'plus' toolbar button not found")
        await tapSettled(plus)
        let today = app.buttons["new-workout-today"]
        await expectExists(today, "'New Workout (Today)' not found")
        await tapSettled(today)
        await expectExists(app.buttons["add-exercise"], "Active workout not shown")
    }

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    @MainActor
    /// "+" → the named routine, and the workout screen must be up.
    private func startWorkout(fromRoutine name: String) async {
        await expectExists(app.buttons["plus"], "'plus' toolbar button not found")
        await tapSettled(app.buttons["plus"])
        let row = app.buttons["routine-start-\(name)"]
        await expectExists(row, "'\(name)' is not offered in the Start Workout sheet")
        await tapSettled(row)
        await expectExists(app.buttons["add-exercise"], "active workout not shown after starting a routine")
    }

    /// "+" → exercise picker → category → exercise.
    private func addExercise(category: String, name: String) async {
        await tapSettled(app.buttons["add-exercise"])
        let cat = app.buttons["category-\(category)"]
        await expectExists(cat, "'\(category)' category not found")
        await tapSettled(cat)
        let pick = app.buttons["pick-\(name)"]
        await expectExists(pick, "'\(name)' not found in \(category)")
        await tapSettled(pick)
        await settle()
    }

    /// Empty a box that has focus, without the keyboard's delete key (see
    /// `clearIfFilled` for why). Select-all, then delete the selection.
    private func clearField(_ field: XCUIElement) async {
        field.typeKey("a", modifierFlags: .command)
        await settle(0.3)
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        await settle(0.4)
        if !((field.value as? String) ?? "").isEmpty {
            // Delete did not take: back out of the selection and try U+0008.
            field.typeText(String(repeating: "\u{8}", count: 4))
            await settle(0.4)
        }
        XCTAssertTrue(((field.value as? String) ?? "").isEmpty,
                      "the test could not empty the box, so the hint cannot be checked")
    }

    private func addFirstExercise() async {
        await tapSettled(app.buttons["add-exercise"])
        let absCat = app.buttons["category-Abs"]
        await expectExists(absCat, "'Abs' category not found")
        await tapSettled(absCat)
        let abWheel = app.buttons["pick-Ab Wheel"]
        await expectExists(abWheel, "'Ab Wheel' not found")
        await tapSettled(abWheel)
        await expectExists(app.textFields["rpe-cell"], "RPE cell not shown after adding exercise")
    }

    /// Type into a cell that is edited in place — no sheet. XCUITest is the
    /// only way in (agent-device keystrokes do not update SwiftUI bindings).
    ///
    /// The box may already hold a value (the target placeholder from the last
    /// time this exercise was done), and typing appends, so clear it first.
    @MainActor
    private func typeInCell(_ id: String, _ text: String) async {
        let field = app.textFields[id]
        await expectExists(field, "'\(id)' box not found")
        field.tap()
        await settle(0.6)
        await clearIfFilled(field)
        field.typeText(text)
        await settle(0.3)
    }

    /// Empty a field that already holds a value, and CHECK that it worked.
    ///
    /// `XCUIKeyboardKey.delete` (U+007F) does not clear a SwiftUI TextField
    /// here: the new text was inserted at the caret instead, so a field holding
    /// "100" ended up as "135100" (2026-09-24, first in isolation and again in
    /// the gate). U+0008 is the character a text field treats as delete, so try
    /// that first and only fall back to select-all. Whatever happens, the field
    /// is read back, so a silent failure to clear cannot masquerade as a pass.
    @MainActor
    private func clearIfFilled(_ field: XCUIElement) async {
        let existing = (field.value as? String) ?? ""
        guard !existing.isEmpty, existing != "—" else { return }
        field.typeText(String(repeating: "\u{8}", count: existing.count + 2))
        await settle(0.35)
        if ((field.value as? String) ?? "").isEmpty { return }
        field.typeKey("a", modifierFlags: .command)
        await settle(0.35)
    }

    /// Close the keyboard with the toolbar Done button. The numeric pads have
    /// no return key, and the value is committed when the box loses focus.
    @MainActor
    private func dismissKeyboard() async {
        let done = app.buttons["keyboard-done"]
        if await wait(for: done, timeout: 5) {
            await tapSettled(done)
        }
    }

    /// Fill the first set's weight/reps/RPE by typing straight into each box.
    @MainActor
    private func fillFirstSet(weight: String, reps: String, rpe: String) async {
        await typeInCell("weight-cell", weight)
        await typeInCell("reps-cell", reps)
        await typeInCell("rpe-cell", rpe)
        await dismissKeyboard()
    }

    /// Finish the open workout and answer the confirmation. The checkmark asks
    /// first now (owner request, 2026-09-23), so every finish has to go through
    /// the dialog.
    @MainActor
    private func finishWorkout() async {
        await tapSettled(app.buttons["finish-workout"])
        await confirmDialog("finish-confirm", "finish confirmation dialog not shown")
        await settle(1.5)
    }

    /// Tap a button inside a `confirmationDialog`.
    ///
    /// Two iOS 26 traps, both measured on the iPhone 17 Pro simulator
    /// (2026-09-24): the dialog's button is exposed TWICE in the accessibility
    /// tree (two elements, same identifier, same frame), so a plain
    /// `app.buttons["id"].tap()` fails with "Multiple matching elements" —
    /// hence `.firstMatch`; and its `.cancel` button is not exposed at all
    /// (0 matches for a "Cancel" label across every element type), so
    /// cancelling has to be done by dismissing the sheet (see `dismissDialog`).
    @MainActor
    private func confirmDialog(_ identifier: String, _ message: String) async {
        let button = app.buttons[identifier].firstMatch
        await expectExists(button, message)
        await tapSettled(button)
    }

    /// Dismiss an open confirmation dialog WITHOUT confirming: tap outside it
    /// (an iOS action sheet dismisses on an outside tap), and if it refuses to
    /// go, drag the sheet down.
    @MainActor
    private func dismissDialog() async {
        // Measured from the failure recording (2026-09-24): the iOS 26
        // confirmationDialog renders as a small card pinned near the TOP of the
        // screen (its button's frame starts at y=132pt of 874), with no dimmed
        // backdrop and no exposed Cancel. A tap at dy=0.12 landed INSIDE the
        // card and did nothing, so tap well below it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        await settle(1.2)
        let stillUp = app.buttons["finish-confirm"].firstMatch.exists
            || app.buttons["row-delete-confirm"].firstMatch.exists
            || app.buttons["delete-workout-confirm"].firstMatch.exists
        if stillUp {
            app.sheets.firstMatch.swipeDown()
            await settle(1.2)
        }
    }

    /// Leave the pushed workout screen: the owner's edge swipe first, then the
    /// nav bar's back button, then the Log tab. The test is about what the Log
    /// shows afterwards, not about the gesture — and the swipe is
    /// timing-sensitive on a busy simulator (it silently missed in the
    /// 2026-09-24 gate run, which read as "no rows in the Log").
    @MainActor
    private func leaveWorkoutScreen() async {
        await swipeBackFromPushedScreen()
        if await wait(for: firstSessionRow(), timeout: 6) { return }
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { await tapSettled(back) }
        if await wait(for: firstSessionRow(), timeout: 6) { return }
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        await settle(1.5)
    }

    /// Leave the pushed screen the way the owner does: an edge swipe.
    @MainActor
    private func swipeBackFromPushedScreen() async {
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        left.press(forDuration: 0.05, thenDragTo: middle)
        await settle(1.5)
    }

    // MARK: - RPE entry

    @MainActor
    func testRPEEntryTypes85AndReadsBack() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await typeInCell("rpe-cell", "8.5")
        await dismissKeyboard()

        // Read it back: the RPE box now shows 8.5 — typed in place, with no
        // sheet in between.
        let field = app.textFields["rpe-cell"]
        await expectExists(field, "RPE box missing after entry")
        XCTAssertEqual(field.value as? String, "8.5",
                       "RPE box should read 8.5, got '\((field.value as? String) ?? "nil")'")
    }

    /// The quick chips must display whole values without a trailing ".0"
    /// (plan §3.2: chips 6, 7, 7.5, 8, 8.5, 9; "displays 8, not 8.0"). They
    /// now sit under the row whose RPE box is being edited.
    @MainActor
    func testRPEChipsDisplayWholeValues() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.textFields["rpe-cell"])

        // Whole-value chips read exactly "6" / "8" — no "6.0" / "8.0".
        for chip in ["6", "7", "8", "9"] {
            let c = app.buttons["rpe-chip-\(chip)"]
            await expectExists(c, "RPE chip '\(chip)' not found")
            XCTAssertEqual(c.label, chip, "chip should read '\(chip)', got '\(c.label ?? "nil")'")
        }
        // Half-step chips keep the decimal.
        for chip in ["7.5", "8.5"] {
            let c = app.buttons["rpe-chip-\(chip)"]
            await expectExists(c, "RPE chip '\(chip)' not found")
            XCTAssertEqual(c.label, chip, "chip should read '\(chip)', got '\(c.label ?? "nil")'")
        }

        // Tapping the "8" chip stores 8 and the cell displays "8", not "8.0".
        await tapSettled(app.buttons["rpe-chip-8"])
        await settle(0.8)
        let field = app.textFields["rpe-cell"]
        await expectExists(field, "RPE box missing after chip tap")
        let shown = (field.value as? String) ?? ""
        XCTAssertTrue(shown.contains("8") && !shown.contains("8.0"),
                      "RPE box should read '8' (not '8.0'), got '\(shown)'")
    }

    // MARK: - Session row navigation

    /// Tapping a session row in the Log must push the session detail
    /// (plan §6.1). Regression test: the row was a Button setting the item of
    /// .navigationDestination(item:) and the push never fired.
    /// Owner request (2026-09-25): an empty box shows the previous performance
    /// greyed out behind it — the last time the EXERCISE was done ("Latest") or
    /// the last time the ROUTINE was done ("By Routine") — only while the box
    /// is empty, gone the moment something is typed, and back when the text is
    /// deleted. It is a hint, never a value: an untouched box stays empty.
    @MainActor
    func testEmptyBoxesHintThePreviousPerformance() async {
        await completeOnboarding()

        // 1. Push Day's Competition Bench: 100 x 5. This is the routine's own
        //    history for that exercise.
        await startWorkout(fromRoutine: "Push Day")
        await typeInCell("weight-cell", "100")
        await typeInCell("reps-cell", "5")
        await dismissKeyboard()
        await finishWorkout()

        // 2. A workout with NO routine, same exercise, 120 x 3. It is newer, so
        //    "Latest" now points somewhere other than Push Day's own last.
        await startFreshWorkout()
        await addExercise(category: "Bench Press", name: "Competition Bench")
        await typeInCell("weight-cell", "120")
        await typeInCell("reps-cell", "3")
        await dismissKeyboard()
        await finishWorkout()

        // 3. Start Push Day again: the empty boxes hint step 2's 120.
        await startWorkout(fromRoutine: "Push Day")
        let weight = app.textFields["weight-cell"].firstMatch
        await expectExists(weight, "the routine's first exercise has no editable weight box")
        XCTAssertEqual((weight.value as? String) ?? "", "",
                       "an untouched box must stay EMPTY — the hint is not a value")
        await expectExists(app.staticTexts["120"],
                           "the empty box does not hint the last time the exercise was done")

        // 4. Type: the hint goes, only what was typed shows.
        await typeInCell("weight-cell", "90")
        XCTAssertEqual((weight.value as? String) ?? "", "90",
                       "the box does not show what was typed")
        XCTAssertFalse(app.staticTexts["120"].exists,
                       "the hint stayed on screen while a value was being typed")

        // 5. Delete it: the previous entry comes back.
        await clearField(weight)
        let hintIsBack = await wait(for: app.staticTexts["120"], timeout: 5)
        XCTAssertTrue(hintIsBack, "clearing the box did not bring the previous entry back")

        // 6. "By Routine" asks the ROUTINE, not the newest session: 100, not 120.
        await tapSettled(app.navigationBars.buttons.element(boundBy: 0))
        await settle()
        await tapSettled(app.tabBars.buttons.element(boundBy: 1))
        await settle()
        await tapSettled(app.buttons["routine-Push Day"])
        await settle()
        let modeRow = app.descendants(matching: .any)
            .matching(identifier: "routine-target-mode").firstMatch
        await expectExists(modeRow, "the routine's Weight and Reps row is not there")
        await tapSettled(modeRow)
        await settle(1.2)
        await tapSettled(app.navigationBars.buttons.element(boundBy: 0))
        await settle()

        await startWorkout(fromRoutine: "Push Day")
        await expectExists(app.staticTexts["100"],
                           "'By Routine' did not hint the routine's own last session")
        XCTAssertFalse(app.staticTexts["120"].exists,
                       "'By Routine' is still hinting a session from another routine")
    }

    /// Owner request (2026-09-24): "update things so I can edit a finished
    /// workout the same way I can an active one". A finished workout opens the
    /// SAME editor, its values are editable and stay edited, and it offers no
    /// Finish control (it is already finished).
    @MainActor
    func testFinishedWorkoutOpensTheEditableScreen() async {
        // Finish one workout so the Log has a row to tap.
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()
        await fillFirstSet(weight: "100", reps: "5", rpe: "8")
        await finishWorkout()
        // Finishing pops the pushed workout (ActiveWorkoutView.finish() ->
        // dismiss() -> the Log root), so the Log's "+" toolbar button is the
        // proof we are back on the Log tab before hunting for the row.
        await expectExists(app.buttons["plus"], "Log tab not shown after finishing")
        let row = await expectSessionRow("session row not shown in Log after finishing")

        await tapSettled(row)
        await expectExists(app.buttons["add-exercise"],
                           "the finished workout did not open the editor")
        await expectExists(app.buttons["add-set"],
                           "the finished workout's cards are not editable")
        XCTAssertFalse(app.buttons["finish-workout"].exists,
                       "a finished workout must not offer Finish again")

        // Edit a set row, leave, and come back: the edit must have stuck. The
        // box used is one that is empty in this workout, so the change is a
        // plain insert.
        await typeInCell("notes-cell", "felt easy")
        await dismissKeyboard()
        await tapSettled(app.navigationBars.buttons.element(boundBy: 0))
        await settle()
        let again = await expectSessionRow("row missing after leaving the editor")
        await tapSettled(again)
        await settle()
        let note = app.textFields["notes-cell"].firstMatch
        await expectExists(note, "the set's notes box after reopening the finished workout")
        XCTAssertEqual((note.value as? String) ?? "", "felt easy",
                       "the edit to a finished workout did not persist")
        // And the values that were already there are untouched.
        let weight = app.textFields["weight-cell"].firstMatch
        XCTAssertEqual((weight.value as? String) ?? "", "100",
                       "reopening a finished workout changed a value that was not edited")
    }

    // MARK: - Finishing, leaving and deleting a workout (owner report, 2026-09-23)

    /// The checkmark must ask before ending the workout: cancel keeps it open,
    /// confirming finishes it.
    @MainActor
    func testFinishAsksBeforeEnding() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["finish-workout"])
        await expectExists(app.buttons["finish-confirm"].firstMatch,
                           "finish confirmation dialog not shown")
        await dismissDialog()
        XCTAssertFalse(app.buttons["finish-confirm"].firstMatch.exists,
                       "the finish dialog was still up after cancelling it")
        // Cancelling must not end the workout.
        await expectExists(app.buttons["add-exercise"],
                           "cancelling the finish dialog closed the workout")

        await finishWorkout()
        await expectExists(app.buttons["plus"], "workout did not finish after confirming")
    }

    /// Leaving an open workout must not strand it: the Log marks it in progress,
    /// and tapping it reopens the EDITOR. It used to open the read-only detail,
    /// which hid the End Time row and had no control that could end it — the
    /// owner's "the end time section disappears and I cannot end the workout".
    @MainActor
    func testOpenWorkoutReopensEditorAfterLeavingIt() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await leaveWorkoutScreen()

        let row = await expectSessionRow("open workout not listed in the Log")
        XCTAssertTrue(row.label.contains("In progress"),
                      "open workout row should read 'In progress', got '\(row.label)'")

        await tapSettled(row)
        await expectExists(app.buttons["add-exercise"],
                           "tapping the open workout did not reopen the editor")
        await expectExists(app.buttons["finish-workout"],
                           "finish control missing on the reopened workout")

        await finishWorkout()
        await expectExists(app.buttons["plus"], "Log not shown after finishing the reopened workout")
    }

    /// Edit mode must reveal a delete per row. It used to flip editMode with
    /// nothing to act on, which is why the app looked as if a workout could not
    /// be deleted at all.
    @MainActor
    func testEditModeRevealsRowDelete() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()
        await fillFirstSet(weight: "100", reps: "5", rpe: "8")
        await finishWorkout()
        await expectExists(app.buttons["plus"], "Log not shown after finishing")

        let row = await expectSessionRow("session row missing in the Log")
        let sid = row.identifier.replacingOccurrences(of: "session-row-", with: "")

        XCTAssertFalse(app.buttons["row-delete-\(sid)"].exists,
                       "a delete must not be on screen outside Edit mode")
        await tapSettled(app.buttons["log-edit"])
        let rowDelete = app.buttons["row-delete-\(sid)"]
        await expectExists(rowDelete, "Edit mode revealed no delete for the row")
        await tapSettled(rowDelete)
        await confirmDialog("row-delete-confirm", "row delete confirmation not shown")
        await settle(1.5)
        XCTAssertFalse(app.buttons["session-row-\(sid)"].exists,
                       "deleted workout should be gone from the Log")
    }

    // MARK: - The End Time row (owner request, 2026-09-24)

    /// Tapping End Time must open a clock picker at the current time, and
    /// confirming it must set the end time AND finish the workout.
    @MainActor
    func testEndTimeRowFinishesTheWorkout() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        let row = app.buttons["end-time-row"]
        await expectExists(row, "the End Time row is not tappable")
        await tapSettled(row)

        let done = app.buttons["end-time-done"]
        await expectExists(done, "the end time picker was not shown")
        await tapSettled(done)
        await settle(2.5)

        await expectExists(app.buttons["plus"], "the workout did not finish after picking an end time")
        let sessionRow = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'session-row-'")).firstMatch
        await expectExists(sessionRow, "the finished session is not listed in the Log")
        XCTAssertFalse(sessionRow.label.contains("In progress"),
                       "session still reads In progress after an end time was set: \(sessionRow.label)")
    }

    // MARK: - The exercise card menu (owner request, 2026-09-24)

    /// The "…" on an exercise card must open the reference app's action set.
    /// It used to be a bare glyph with no tap target, so it read as dead.
    @MainActor
    func testExerciseMenuOffersTheReferenceActions() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["exercise-menu"])
        for label in ["Move", "Replace", "Delete", "Edit Note", "History", "Charts", "Personal Records", "Weight Unit"] {
            let item = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).firstMatch
            let shown = await wait(for: item, timeout: 6)
            XCTAssertTrue(shown, "the exercise menu is missing '\(label)'")
        }
        // Dismiss without choosing anything.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
        await settle(1)
    }

    // MARK: - Exercise search

    @MainActor
    func testExerciseSearchFilters() async {
        await completeOnboarding()
        await startFreshWorkout()
        await tapSettled(app.buttons["add-exercise"])

        let search = app.textFields["exercise-search"]
        await expectExists(search, "search field not found")
        search.tap()
        search.typeText("Squat")
        await settle(1)

        // The category list now shows only "Squats".
        let squats = app.buttons["category-Squats"]
        await expectExists(squats, "'Squats' category not shown after searching 'Squat'")
        // "Abs" should be filtered out.
        let gone = !app.buttons["category-Abs"].exists
        XCTAssertTrue(gone, "'Abs' should be filtered out when searching 'Squat'")
    }

    // MARK: - Sync URL + token

    @MainActor
    func testSyncURLAndTokenFields() async {
        await completeOnboarding()
        let profile = app.tabBars.buttons.element(boundBy: 3)
        await expectExists(profile, "'Profile' tab not found")
        await tapSettled(profile)
        let settings = app.buttons["settings-link"]
        await expectExists(settings, "'Settings' not found in Profile")
        await tapSettled(settings)

        // Scroll to the Sync section.
        let toggle = app.switches["enable-sync"]
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
            await settle(0.5)
        }
        XCTAssertTrue(toggle.exists, "'Enable Sync' toggle not found")
        await tapSwitchKnob(toggle)

        let url = app.textFields["sync-url-field"]
        await expectExists(url, "sync URL field not found")
        url.tap()
        url.typeText("http://192.168.1.12:8080")

        let token = app.secureTextFields["sync-token-field"]
        await expectExists(token, "sync token field not found")
        token.tap()
        token.typeText("test-token-123")

        let done = app.buttons["done"]
        await expectExists(done, "Settings 'Done' not found")
        await tapSettled(done)
        await dismissSavePasswordPrompt()
    }

    // MARK: - Set notes

    @MainActor
    func testSetNoteEntry() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        // Typed straight into the row's Notes box — no note sheet.
        await typeInCell("notes-cell", "felt heavy")
        await dismissKeyboard()

        // The note shows ONCE, in the Notes box. The copy that used to render
        // as a second line under the row was removed on the owner's
        // instruction (2026-09-24) — so this asserts both halves: the box
        // holds it, and nothing else repeats it.
        let cell = app.textFields["notes-cell"].firstMatch
        await expectExists(cell, "Notes box not found")
        XCTAssertEqual(cell.value as? String, "felt heavy",
                       "the note is not in the Notes box")
        XCTAssertEqual(
            app.staticTexts.matching(NSPredicate(format: "label == %@", "felt heavy")).count, 0,
            "the note is drawn a second time outside the Notes box")
    }

    /// Owner requirement (2026-09-24): the note belongs to the EXERCISE IN THAT
    /// ROUTINE, not to the exercise. Two routines can hold the same exercise and
    /// must keep their own notes — his example: session 1's squat says "3x5 go
    /// light", session 2's says "4x4 go heavy, no belt".
    ///
    /// A duplicate is the cheapest second routine that holds the same exercise.
    @MainActor
    func testNotesArePerRoutineNotPerExercise() async {
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES"]
        app.launch()
        await settle(3)

        let first = "3x5 go light"
        let second = "4x4 go heavy, no belt"

        await tapSettled(app.tabBars.buttons.element(boundBy: 1))
        await settle()
        await tapSettled(app.buttons["routine-Push Day"])
        await settle()

        // Push Day's own note goes on Dips.
        await setNote(first, on: "Dips")
        await expectExists(app.staticTexts[first], "Push Day's own note on its row")

        // Duplicate the routine: the copy holds the same exercise. This also
        // covers the 2026-09-24 defect where a duplicate never appeared in the
        // list — the copy was in the store but the list was never re-fetched.
        let menu = app.buttons["routine-menu"].firstMatch
        await expectExists(menu, "routine menu")
        await tapSettled(menu)
        await settle(1.2)
        await tapSettled(app.buttons["Duplicate"].firstMatch)
        await settle(1.5)

        // Back to the list, which must already show the copy.
        await tapSettled(app.navigationBars.buttons.element(boundBy: 0))
        await settle(1.5)
        let copy = app.buttons["routine-Push Day Copy"].firstMatch
        await expectExists(copy, "the duplicated routine in the list")
        await tapSettled(copy)
        await settle()
        await expectExists(app.staticTexts[first], "the copy inherits the note")

        // Give the copy's Bench a note of its own (an empty field, so this
        // also avoids depending on how the field clears existing text).
        await setNote(second, on: "Competition Bench")
        await expectExists(app.staticTexts[second], "the copy's own note on its row")
        // The copy also carries the note it was duplicated WITH, on its other
        // row. Two routines, two independent sets of notes.
        await expectExists(app.staticTexts[first], "the copy's inherited note on its other row")

        // Push Day still holds its own note.
        await tapSettled(app.navigationBars.buttons.element(boundBy: 0))
        await settle()
        await tapSettled(app.buttons["routine-Push Day"].firstMatch)
        await settle()
        await expectExists(app.staticTexts[first], "Push Day kept its own note")
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label == %@", second)).count == 0,
            "the copy's note leaked into Push Day")
    }

    /// Open the routine exercise editor for `exercise`, type `note`, Done.
    @MainActor
    private func setNote(_ note: String, on exercise: String) async {
        let row = app.staticTexts[exercise].firstMatch
        await expectExists(row, "\(exercise) row in the routine")
        await tapSettled(row)
        let field = app.textFields["routine-exercise-notes-field"].firstMatch
        await expectExists(field, "routine exercise notes field")
        await tapSettled(field)
        await clearIfFilled(field)
        field.typeText(note)
        await settle(0.6)
        // The sheet's own Done — the nav bar's, not the keyboard's (the
        // keyboard carries a "Done" too, and tapping that leaves the sheet up).
        let sheetDone = app.navigationBars.buttons["Done"].firstMatch
        await expectExists(sheetDone, "the routine editor's Done button")
        await tapSettled(sheetDone)
        await settle()
    }

    /// Owner report (2026-09-24): "When editing a routine the exercise notes
    /// don't reflect the actual exercise note set in the routine." The note a
    /// routine exercise carries was never drawn on the routine and was dropped
    /// when a workout started from it. Both halves are asserted here.
    @MainActor
    func testRoutineExerciseNoteIsShownAndCarriesIntoTheWorkout() async {
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES"]
        app.launch()
        await settle(3)

        let note = "belt on, pause every rep"
        await tapSettled(app.tabBars.buttons.element(boundBy: 1))
        await settle()
        await tapSettled(app.buttons["routine-Push Day"])
        await settle()

        // Set the note the way the owner did: in the exercise editor.
        let row = app.staticTexts["Competition Bench"].firstMatch
        await expectExists(row, "Competition Bench row in the routine")
        await tapSettled(row)
        let field = app.textFields["routine-exercise-notes-field"].firstMatch
        await expectExists(field, "routine exercise notes field")
        await tapSettled(field)
        field.typeText(note)
        await settle(0.6)
        // The sheet's own Done button, exactly as reported. It has to be the
        // one in the nav bar: the keyboard carries a "Done" too, and tapping
        // that one leaves the sheet open.
        let sheetDone = app.navigationBars.buttons["Done"].firstMatch
        await expectExists(sheetDone, "the routine editor's Done button")
        await tapSettled(sheetDone)
        await settle()

        // 1. The routine's row draws the note that was set.
        await expectExists(app.staticTexts[note],
                           "the routine's exercise row does not show the note set for it")

        // 2. A workout started from the routine carries the note to the card.
        // It is a Button whose label is the text — a staticText query for it
        // finds nothing (the probe proved that).
        let start = app.buttons["Start this Workout"].firstMatch
        await expectExists(start, "Start this Workout button")
        await tapSettled(start)
        await settle(2.5)
        let cardNote = app.textFields["exercise-note-field"].firstMatch
        if cardNote.exists {
            XCTAssertEqual((cardNote.value as? String) ?? "", note,
                           "the workout card lost the routine's note for the exercise")
        } else {
            await expectExists(app.staticTexts[note],
                               "the routine's note is not on the workout card")
        }
    }

    // MARK: - Offline drill (plan §7.5)

    /// The lift-sync service for this drill: a real uvicorn on a private
    /// port with a private token (no real data, no prod service), controlled
    /// by scripts/drill_supervisor.py (the test bundle is iOS-compiled and
    /// cannot spawn processes on the Mac host).
    private let supervisorPort = 8392
    private let drillToken = "uitest-drill-token"
    /// The simulator shares the Mac's network stack, so the Mac's loopback is
    /// reachable directly (proven: the supervisor calls to 127.0.0.1:8392
    /// succeed from the simulator).
    private let drillServiceURL = "http://127.0.0.1:8391"

    @MainActor
    private func supervisor(_ path: String, method: String = "GET") async -> Data? {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(supervisorPort)\(path)")!)
        req.httpMethod = method
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return data
        } catch { return nil }
    }

    @MainActor
    private func supervisorJSON(_ path: String, method: String = "POST") async -> [String: Any]? {
        guard let data = await supervisor(path, method: method) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Data rows in the service's CSV (header excluded). The drill's service
    /// always starts in a FRESH data dir, so any row here was written by this
    /// run — that is what makes "exactly one upload" checkable without
    /// guessing which Log row is the new session.
    @MainActor
    private func drillCSVDataRows() async -> Int {
        guard let data = await supervisor("/csv"),
              let text = String(data: data, encoding: .utf8) else { return -1 }
        return max(0, text.split(separator: "\n").count - 1)
    }

    /// The session_id of the CSV's first data row (the uploaded session).
    @MainActor
    private func drillCSVFirstSessionID() async -> String? {
        guard let data = await supervisor("/csv"),
              let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").dropFirst() {
            let id = line.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            if !id.isEmpty { return id }
        }
        return nil
    }

    /// POST the same session payload again (the resurrection attempt).
    @MainActor
    private func drillReimport(sessionID: String) async throws -> Int {
        let body: [String: Any] = [
            "session_id": sessionID,
            "date": "2026-09-22",
            "sets": [["exercise": "Drill", "set_number": 1, "weight_kg": 100.0, "reps": 5]],
        ]
        var req = URLRequest(url: URL(string: "\(drillServiceURL)/v1/sessions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(drillToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode ?? -1
    }

    /// Plan §7.5, in-simulator: service stopped -> finish a session ->
    /// relaunch the app -> service back up -> nothing uploads until sync is
    /// tapped -> exactly one upload -> delete the workout on the phone (LOCAL
    /// only: the database copy stays) -> re-import is accepted, not refused.
    @MainActor
    func testOfflineDrill() async {
        // 0. Supervisor must be reachable (started by scripts/mac-tests.sh).
        guard await supervisor("/health") != nil else {
            // A skip would let the gate look green while the drill never ran;
            // the supervisor is mac-tests.sh's job, so its absence is a failure.
            XCTFail("drill supervisor not running on 127.0.0.1:\(supervisorPort) — start it via scripts/mac-tests.sh")
            return
        }
        // The service must be down for the offline phase.
        await supervisorJSON("/stop")

        // 1. Sync is pre-configured by the -SyncURL/-SyncToken launch
        // arguments (see RepLogApp): typing into the Settings form triggers
        // iOS's AutoFill "Save Password?" prompt, and while that alert is up
        // every later tap is swallowed. The Settings form itself is covered by
        // testSyncURLAndTokenFields. The service is stopped for this phase.
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES",
                               "-SyncURL", drillServiceURL,
                               "-SyncToken", drillToken]
        app.launch()
        await settle(2)
        await completeOnboarding()

        // 2. Finish a session while the service is stopped -> queued offline.
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        await startFreshWorkout()
        await addFirstExercise()
        await fillFirstSet(weight: "100", reps: "5", rpe: "8")
        await finishWorkout()
        await settle(3)

        // The session is in the Log. (Its id is NOT read from here: the Log
        // holds earlier sessions too, and "the first row" is not reliably the
        // new one — the service's fresh CSV is the source of truth below.)
        await expectSessionRow("session row not shown after offline finish")

        // 3. Relaunch the app (queue must survive the restart). -ResetRepLog NO
        // keeps the persisted state; the sync args are re-applied so the
        // configured server is unambiguous.
        app.terminate()
        await settle(1)
        app.launchArguments = ["-ResetRepLog", "NO",
                               "-SyncURL", drillServiceURL,
                               "-SyncToken", drillToken]
        app.launch()
        await settle(3)

        // 4. Service back up -> the queued session uploads exactly once.
        let started = await supervisorJSON("/start")
        guard let started, started["ok"] as? Bool == true else {
            XCTFail("drill service failed to start: \(String(describing: started?["error"]))")
            return
        }
        // The service must be reachable from the simulator before we blame the
        // upload: this test process and the app share the simulator's network
        // stack, so a 200 here means the app's POST path is the same.
        let healthReq = URLRequest(url: URL(string: "\(drillServiceURL)/v1/health")!)
        let healthResult = try? await URLSession.shared.data(for: healthReq)
        XCTAssertEqual((healthResult?.1 as? HTTPURLResponse)?.statusCode, 200,
                       "drill service not reachable from the simulator at \(drillServiceURL)/v1/health")

        // The queue survived the restart and is VISIBLE from the Log without
        // opening Profile: the sync control reads "1 to sync". (Assert the
        // BUTTON's label — an explicit accessibilityLabel makes the button a
        // leaf element, so its inner Text is not separately queryable.)
        let syncNow = app.buttons["sync-now"]
        await expectExists(syncNow, "Log's sync control not found before syncing")
        let queuedLabel = (syncNow.label as? String) ?? ""
        XCTAssertTrue(queuedLabel.contains("1 to sync"),
                      "the Log's sync control should read '1 to sync' while one session is queued, got '\(queuedLabel)'")

        // Sync is manual (owner request, 2026-09-23): nothing uploads on launch
        // or when the network comes back, so prove the queue waits, then tap the
        // Log's sync control and poll for the upload.
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        let rowsWithoutTap = await drillCSVDataRows()
        XCTAssertEqual(rowsWithoutTap, 0,
                       "nothing may upload until sync is tapped, got \(rowsWithoutTap) row(s)")

        var rows = rowsWithoutTap
        var attempt = 0
        while rows != 1 && attempt < 20 {
            if attempt % 4 == 0 {
                let syncNow = app.buttons["sync-now"]
                if await wait(for: syncNow, timeout: 5) { await tapSettled(syncNow) }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            rows = await drillCSVDataRows()
            attempt += 1
        }
        XCTAssertEqual(rows, 1,
                       "expected exactly one uploaded row (the service starts empty), got \(rows)")
        // The CSV (not the Log) names the session — and the delete below
        // removes that row, so keep the id.
        guard let fullID = await drillCSVFirstSessionID() else {
            XCTFail("uploaded session id not readable from the service CSV")
            return
        }
        let sid = String(fullID.prefix(8))
        // Exactly one upload: one upsert event for this session in the audit.
        guard let auditData = await supervisor("/audit"),
              let audit = String(data: auditData, encoding: .utf8) else {
            XCTFail("audit log not readable"); return
        }
        let upserts = audit.components(separatedBy: "\n").filter {
            $0.contains("\"type\":\"upsert\"") && $0.contains(fullID)
        }.count
        XCTAssertEqual(upserts, 1, "expected exactly one upload, got \(upserts) upsert events")

        // 5. Delete the session in the app -> LOCAL ONLY (owner rule,
        //    2026-09-23): the phone forgets the workout, and the copy that
        //    already reached the sync database stays there.
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        // The tab tap can be swallowed while another screen settles; the Log's
        // "+" is the proof we are on the Log before hunting for the row.
        if !(await wait(for: app.buttons["plus"], timeout: 6)) {
            await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        }
        await expectExists(app.buttons["plus"], "Log tab not shown before delete")
        let rowToDelete = app.buttons["session-row-\(sid)"]
        await expectExists(rowToDelete, "uploaded session's row (session-row-\(sid)) not in the Log")
        await tapSettled(rowToDelete)
        await expectExists(app.buttons["workout-menu"], "the workout editor did not open")
        await tapSettled(app.buttons["workout-menu"])
        await tapSettled(app.buttons["delete-workout"])
        await confirmDialog("delete-workout-confirm", "delete confirmation not shown")
        await settle(3)

        // Gone from the phone, and the editor screen left with it (the old
        // detail screen used to stay on a deleted model, which read as "delete
        // did nothing").
        XCTAssertFalse(app.buttons["session-row-\(sid)"].exists,
                       "deleted session should be gone from the Log")
        // The detail screen must have dismissed. The assertion is on the Log's
        // Edit button, not its "+": with the Log now EMPTY the toolbar's
        // trailing group (the sync control + "+") collapses into an overflow
        // button, so "+" is not a reliable marker of being on the Log (seen in
        // the 2026-09-24 failure recording — reported separately, not worked
        // around here).
        await expectExists(app.buttons["log-edit"], "not back on the Log after deleting")
        XCTAssertFalse(app.buttons["workout-menu"].exists,
                       "the workout editor was still up after deleting")
        // The database copy is untouched and no delete was ever sent.
        let rowsAfterDelete = await drillCSVDataRows()
        XCTAssertEqual(rowsAfterDelete, 1,
                       "the uploaded session must stay in the sync database after a phone delete, got \(rowsAfterDelete) row(s)")
        guard let jsonlData = await supervisor("/audit"),
              let jsonl = String(data: jsonlData, encoding: .utf8) else {
            XCTFail("audit log not readable"); return
        }
        XCTAssertFalse(jsonl.contains("\"type\":\"delete\""),
                       "a phone delete must never send a server-side delete")

        // 6. Re-import the same session -> accepted as an upsert (there is no
        //    tombstone any more) and the database still holds exactly one row.
        let status = (try? await drillReimport(sessionID: fullID)) ?? -1
        XCTAssertTrue(status < 400,
                      "re-import after a phone-only delete should be accepted, got \(status)")
        let rowsAfterReimport = await drillCSVDataRows()
        XCTAssertEqual(rowsAfterReimport, 1,
                       "the database copy must survive, got \(rowsAfterReimport) row(s)")

        // And a further sync must not bring it back on the phone.
        let finalSync = app.buttons["sync-now"]
        if await wait(for: finalSync, timeout: 5) { await tapSettled(finalSync) }
        await settle(3)
        XCTAssertFalse(app.buttons["session-row-\(sid)"].exists,
                       "a locally deleted session must not come back after syncing")

        await supervisorJSON("/stop")
    }
}
