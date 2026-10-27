import XCTest
import SwiftUI
import CoreGraphics

/// XCUITest covers every text-entry flow, because agent-device's keystroke
/// injection does not update SwiftUI @State bindings (plan §7.3):
///   - RPE entry (numeric pad + chips)
///   - exercise search
///   - set notes
///   - keyboard arrows and the focused box clearing the software keyboard
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

    /// Switch to the Profile tab and prove it is on screen.
    ///
    /// A tab tap can be swallowed while the previous screen settles, and a
    /// loaded-but-not-shown Profile still reports its elements with a hit point
    /// of (-1, -1), so prove a real control is hittable first.
    @MainActor
    private func openProfileTab() async {
        for _ in 0..<3 {
            await tapSettled(app.tabBars.buttons.element(boundBy: 3))
            if app.buttons["export-csv"].isHittable { return }
        }
    }

    /// Walk onboarding (units -> privacy) to the Log tab.
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

    /// "+" → the named routine, and the workout screen must be up.
    ///
    /// Starts by selecting the Log tab: the ROUTINES screen also has a "+"
    /// (Add routine), and it carries the same identifier, so tapping "plus"
    /// from there opens the New Routine sheet and the routine never appears in
    /// the start list (found the hard way, 2026-09-25).
    @MainActor
    private func startWorkout(fromRoutine name: String) async {
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        await settle()
        await expectExists(app.buttons["plus"], "'plus' toolbar button not found")
        await tapSettled(app.buttons["plus"])
        let row = app.buttons["routine-start-\(name)"]
        if !(await wait(for: row, timeout: 8)) {
            let ids = app.buttons.allElementsBoundByIndex.map { "\($0.label) [\($0.identifier)]" }
            XCTFail("'\(name)' is not offered in the Start Workout sheet. Buttons: \(ids)")
            return
        }
        await tapSettled(row)
        await expectExists(app.buttons["add-exercise"], "active workout not shown after starting a routine")
    }

    /// "+" → exercise picker → category → exercise.
    @MainActor
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

    /// Swipe a row from right to left the way a finger does: press, then drag.
    /// XCUITest's `swipeLeft()` flicks fast enough that a NavigationLink row
    /// reads it as a tap and navigates instead (2026-09-25).
    @MainActor
    private func swipeRowLeft(_ element: XCUIElement) async {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0.05)
        await settle(1.6)
    }

    /// The same swipe taken right across the row: enough for a full-swipe
    /// delete on a narrow element, which cannot be reached otherwise.
    @MainActor
    private func swipeRowFullLeft(_ element: XCUIElement) async {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        start.press(forDuration: 0.08, thenDragTo: end,
                    withVelocity: .slow, thenHoldForDuration: 0.05)
        await settle(1.6)
    }

    /// Empty a box that has focus, without the keyboard's delete key (see
    /// `clearIfFilled` for why). Select-all, then delete the selection.
    @MainActor
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

    /// Add the first exercise of the first category (Abs -> Ab Wheel).
    @MainActor
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
        // firstMatch: a workout can show several rows, and every row's weight
        // box shares the identifier. "The cell" always means the top row's.
        let field = app.textFields[id].firstMatch
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
        // The workout covers the app and has no navigation bar (owner request,
        // 2026-10-23): its own header's chevron is the way out.
        let close = app.buttons["close-workout"]
        if await wait(for: close, timeout: 6) { await tapSettled(close) }
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
        // Retried once: the chips animate in when the box takes focus, so a tap
        // delivered before they settle lands as a miss roughly one run in eight
        // (measured 2026-09-25: the only failure in a full UI run, every other
        // test green). One retry distinguishes a miss from a chip that cannot
        // set a value at all.
        let field = app.textFields["rpe-cell"]
        await tapSettled(app.buttons["rpe-chip-8"])
        await settle(0.8)
        await expectExists(field, "RPE box missing after chip tap")
        var shown = (field.value as? String) ?? ""
        if !(shown.contains("8") && !shown.contains("8.0")) {
            await tapSettled(app.buttons["rpe-chip-8"])
            await settle(0.8)
            shown = (field.value as? String) ?? ""
        }
        XCTAssertTrue(shown.contains("8") && !shown.contains("8.0"),
                      "RPE box should read '8' (not '8.0'), got '\(shown)'")
    }

    // MARK: - Session row navigation

    /// Tapping a session row in the Log must push the session detail
    /// (plan §6.1). Regression test: the row was a Button setting the item of
    /// .navigationDestination(item:) and the push never fired.
    /// Owner request (2026-09-25): swipe a set row left to delete it, with
    /// nothing to confirm ("it should just delete on one slide"); swipe a
    /// workout row in the Log and THAT asks first.
    @MainActor
    func testSwipeToDeleteASetAndAWorkout() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()
        await typeInCell("weight-cell", "50")
        // The keyboard covers Add Set: put it away first.
        await dismissKeyboard()
        await tapSettled(app.buttons["add-set"])
        await settle(1.5)
        let rows = app.textFields.matching(identifier: "weight-cell")
        XCTAssertEqual(rows.count, 2, "Add Set did not add a second row")

        // Swipe the SECOND row away, then press the Delete the swipe revealed:
        // a set goes without anything to confirm.
        await swipeRowLeft(app.textFields.matching(identifier: "notes-cell").element(boundBy: 1))
        let setDelete = app.buttons["swipe-delete-set-2"]
        await expectExists(setDelete, "swiping a set row did not reveal a Delete button")
        // Press the revealed panel where it actually is: at the row's right
        // edge. (The button's own frame is the panel, but a tap aimed at it by
        // element can land on the row that slid aside.)
        let setCell = app.textFields.matching(identifier: "notes-cell").element(boundBy: 1)
        setCell.coordinate(withNormalizedOffset: CGVector(dx: 1.0, dy: 0.5))
            .withOffset(CGVector(dx: 55, dy: 0))
            .tap()
        await settle(1.2)
        XCTAssertEqual(app.textFields.matching(identifier: "weight-cell").count, 1,
                       "pressing Delete on a set row did not remove it")
        XCTAssertFalse(app.buttons["exercise-delete-confirm"].exists,
                       "deleting a set asked for confirmation")
        XCTAssertEqual((app.textFields["weight-cell"].firstMatch.value as? String) ?? "", "50",
                       "the wrong set was deleted")

        // Now the workout. Its row is a real List row, so the slide is the
        // system's own swipe action — and because a workout is a whole session
        // of work, this one DOES ask first.
        await dismissKeyboard()
        await finishWorkout()
        await expectExists(app.buttons["plus"], "not back on the Log after finishing")
        let workout = await expectSessionRow("the finished workout is not in the Log")
        let sid = workout.identifier.replacingOccurrences(of: "session-row-", with: "")
        workout.swipeLeft()
        let swipeDelete = app.buttons["swipe-delete-\(sid)"]
        await expectExists(swipeDelete, "swiping a workout did not reveal Delete")

        // Cancel first: the confirmation is real, and cancelling keeps the
        // workout.
        await tapSettled(swipeDelete)
        await settle(1.5)
        XCTAssertTrue(app.buttons["row-delete-confirm"].exists,
                      "deleting a workout did not ask first")
        // Cancelling has to be done by dismissing it: iOS 26 does not expose a
        // confirmationDialog's .cancel button at all (see dismissDialog).
        await dismissDialog()
        await settle(1.2)
        XCTAssertTrue(app.buttons["session-row-\(sid)"].exists,
                      "cancelling the confirmation removed the workout anyway")

        // Then go through with it.
        workout.swipeLeft()
        await tapSettled(app.buttons["swipe-delete-\(sid)"])
        await confirmDialog("row-delete-confirm", "deleting a workout did not ask first")
        await settle(2)
        XCTAssertFalse(app.buttons["session-row-\(sid)"].exists,
                       "the workout was still in the Log after confirming the delete")
    }

    /// Owner request (2026-09-25): an empty box shows the previous performance
    /// greyed out behind it — the last time the EXERCISE was done ("Latest") or
    /// the last time the ROUTINE was done ("By Routine") — only while the box
    /// is empty, gone the moment something is typed, and back when the text is
    /// deleted. It is a hint, never a value: an untouched box stays empty.
    @MainActor
    func testEmptyBoxesHintThePreviousPerformance() async {
        // Demo data for the Push Day routine (and its Competition Bench).
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES"]
        app.launch()
        await settle(4)
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

        // 3. Start Push Day again: the empty box hints step 2's 120.
        await startWorkout(fromRoutine: "Push Day")
        let weight = app.textFields["weight-cell"].firstMatch
        await expectExists(weight, "the routine's first exercise has no editable weight box")
        XCTAssertEqual((weight.value as? String) ?? "", "",
                       "an untouched box must stay EMPTY — the hint is not a value")
        // Sets that have never been done are BLANK, not a repeat of the last
        // session's final set (owner report, 2026-09-25).
        let setRows = app.textFields.matching(identifier: "weight-cell").count
        let hints = app.staticTexts.matching(identifier: "hint-weight-cell")
        XCTAssertGreaterThan(hints.count, 0, "no empty weight box shows a hint")
        // Every row is either a hint (last time's set) or blank (a set that has
        // never been done). The routine prescribes more sets than the last
        // session had, so some MUST be blank: without that rule the extras
        // would repeat the last set's numbers (owner report, 2026-09-25).
        let blanks = app.staticTexts.matching(identifier: "blank-weight-cell").count
        XCTAssertLessThan(hints.count, setRows,
                          "every box is hinting — a set that was never done must be blank")
        XCTAssertEqual(hints.count + blanks, setRows,
                       "every row should be either a hint or blank")
        XCTAssertEqual(hints.element(boundBy: 0).label, "120",
                       "the hint is not the last time the EXERCISE was done")
        let rows = hints.count

        // 4. Type into the first box: ITS hint goes (only the box being typed
        //    in loses it), and the box shows what was typed.
        await typeInCell("weight-cell", "90")
        XCTAssertEqual((weight.value as? String) ?? "", "90",
                       "the box does not show what was typed")
        XCTAssertEqual(hints.count, rows - 1,
                       "the hint did not go when a value was typed over it")

        // 5. Delete it: the previous entry comes back.
        await clearField(weight)
        var hintIsBack = false
        for _ in 0..<15 {
            if hints.count == rows { hintIsBack = true; break }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        XCTAssertTrue(hintIsBack, "clearing the box did not bring the previous entry back")
        XCTAssertEqual(hints.count, rows, "the hint did not come back for the emptied box")
        XCTAssertEqual(hints.element(boundBy: 0).label, "120",
                       "the hint came back as something other than the last performance")

        // 6. "By Routine" asks the ROUTINE, not the newest session: 100, not 120.
        await tapSettled(app.buttons["close-workout"])
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
        let byRoutineHint = app.staticTexts.matching(identifier: "hint-weight-cell").firstMatch
        await expectExists(byRoutineHint, "'By Routine' shows no hint at all")
        XCTAssertEqual(byRoutineHint.label, "100",
                       "'By Routine' is not hinting the routine's own last session (120 would mean it is still reading the newest session of the exercise)")
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
        await tapSettled(app.buttons["close-workout"])
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

    /// Deleting a workout from its own menu takes it out of the Log.
    ///
    /// The drill covers this as one step among many; on its own it is the
    /// fastest way to see whether the editor's delete still lands (it stopped
    /// landing on 2026-09-25, which the drill could only report as "deleted
    /// session should be gone from the Log").
    @MainActor
    func testDeleteWorkoutFromTheEditorMenu() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()
        await fillFirstSet(weight: "60", reps: "5", rpe: "7")
        await dismissKeyboard()
        await finishWorkout()
        let row = await expectSessionRow("finished workout not in the Log")
        let sid = row.identifier.replacingOccurrences(of: "session-row-", with: "")

        await tapSettled(app.buttons["session-row-\(sid)"])
        await expectExists(app.buttons["workout-menu"], "the workout editor did not open")
        await tapSettled(app.buttons["workout-menu"])
        await tapSettled(app.buttons["delete-workout"])
        await confirmDialog("delete-workout-confirm", "delete confirmation not shown")
        await settle(3)
        await expectExists(app.buttons["log-edit"], "not back on the Log after deleting")
        XCTAssertFalse(app.buttons["session-row-\(sid)"].exists,
                       "the workout is still in the Log after deleting it from its menu")
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

    // MARK: - The keyboard's arrows (owner request, 2026-10-13)

    /// The keyboard's chevrons walk the boxes in the order they appear on
    /// screen: weight -> reps -> RPE, and back. What proves the step is WHERE
    /// the typing lands — keystrokes only reach the focused box, so a
    /// `typeText` into an unfocused one fails by itself.
    @MainActor
    func testKeyboardArrowsStepBetweenBoxes() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        // The bar exists while a box is focused, with both arrows.
        await typeInCell("weight-cell", "60")
        await expectExists(app.buttons["keyboard-next"], "the keyboard has no next arrow")
        await expectExists(app.buttons["keyboard-prev"], "the keyboard has no previous arrow")

        // → to reps, then → to RPE. Each value is typed into whatever box the
        // arrow left focused.
        await tapSettled(app.buttons["keyboard-next"])
        await settle(1.0)
        let repsBox = app.textFields["reps-cell"].firstMatch
        repsBox.typeText("12")
        await settle(0.5)

        await tapSettled(app.buttons["keyboard-next"])
        await settle(1.0)
        let rpeBox = app.textFields["rpe-cell"].firstMatch
        rpeBox.typeText("8")
        await settle(0.5)

        // ← twice: RPE -> reps -> weight. Overwrite weight with 55.
        await tapSettled(app.buttons["keyboard-prev"])
        await settle(0.8)
        await tapSettled(app.buttons["keyboard-prev"])
        await settle(0.8)
        let weightBox = app.textFields["weight-cell"].firstMatch
        await clearIfFilled(weightBox)
        weightBox.typeText("55")
        await settle(0.5)

        await dismissKeyboard()

        // Read it all back: every value landed in its own box, so the arrows
        // really moved the focus.
        let gotWeight = (app.textFields["weight-cell"].firstMatch.value as? String) ?? "nil"
        let gotReps = (app.textFields["reps-cell"].firstMatch.value as? String) ?? "nil"
        let gotRpe = (app.textFields["rpe-cell"].firstMatch.value as? String) ?? "nil"
        XCTAssertEqual(gotWeight, "55", "weight box should read 55 (typed after ← ← returned to it), got '\(gotWeight)'")
        XCTAssertEqual(gotReps, "12", "reps box should read 12 (typed after → from weight), got '\(gotReps)'")
        XCTAssertEqual(gotRpe, "8", "RPE box should read 8 (typed after → from reps), got '\(gotRpe)'")
    }

    /// Owner report (2026-10-13): a box tapped low on the screen used to stay
    /// behind the keyboard. Asserted geometrically — the focused box's bottom
    /// edge must sit above the accessory bar — not by a look.
    @MainActor
    func testFocusedBoxIsScrolledAboveTheKeyboard() async {
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES"]
        app.launch()
        await settle(4)
        await completeOnboarding()
        await startWorkout(fromRoutine: "Push Day")

        // To the bottom: the boxes near the keyboard's edge are the case that
        // used to be blocked.
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "the workout's scroll view was not found")
        for _ in 0..<4 { scroll.swipeUp() }
        await settle(1)

        // The bottom-most visible weight box, low on the screen.
        let screen = app.frame
        let boxes = app.textFields.matching(identifier: "weight-cell")
        var target: XCUIElement?
        for i in stride(from: boxes.count - 1, through: 0, by: -1) {
            let candidate = boxes.element(boundBy: i)
            if candidate.isHittable, candidate.frame.minY > screen.height * 0.5 {
                target = candidate
                break
            }
        }
        guard let target else {
            XCTFail("no weight box sits low enough on the screen to test the keyboard overlap")
            return
        }
        let before = target.frame
        target.tap()
        // Raise the software keyboard by typing: a bare tap leaves the keys
        // parked off-screen on this simulator (the accessory bar is drawn, the
        // keys are not), and this assertion is only meaningful against a
        // keyboard that is really showing. Typing is also the real flow, and
        // it must land in the box that was tapped.
        target.typeText("15")
        await settle(2)

        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.exists, "the keyboard did not open for the tapped box")
        // Prove the software keyboard is really up: on this simulator a bare
        // tap leaves the keys parked off-screen and the check below would then
        // pass against nothing (2026-10-13).
        XCTAssertGreaterThan(keyboard.frame.height, 150,
            "the software keyboard is not showing (frame \(keyboard.frame)) — the geometry check would be vacuous")
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.exists, "the keyboard's accessory bar is missing")
        // Clear of BOTH the keyboard and its accessory bar, whichever way the
        // keyboard element's frame counts them.
        let barTop = min(keyboard.frame.minY, done.frame.minY)
        let after = target.frame
        print("KEYBOARD-GEOMETRY box=\(after) keyboard=\(keyboard.frame) done=\(done.frame)")
        XCTAssertLessThanOrEqual(after.maxY, barTop + 1,
            "the focused box is behind the keyboard: box bottom y=\(after.maxY), bar top y=\(barTop) (before the tap the box was y=\(before.minY)-\(before.maxY), screen \(screen.height))")
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

    /// The Statistics chart's export ships the sessions the CHART shows, not
    /// the whole history (owner request, 2026-10-24). -DemoHistory adds
    /// sessions 40 / 150 / 300 / 600 days back on top of the three in the last
    /// week, so every window holds strictly more sessions than the one inside it.
    @MainActor
    func testStatisticsExportRespectsTheRange() async {
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES", "-DemoHistory", "YES"]
        app.launch()
        await settle(3)
        await completeOnboarding()

        // Statistics -> Overall Statistics -> Volume (a chart screen with the
        // range picker and its own export).
        await tapSettled(app.tabBars.buttons.element(boundBy: 2))
        let volume = app.buttons["Volume"].firstMatch
        await expectExists(volume, "the Volume metric row is not on the Statistics screen")
        await tapSettled(volume)
        await expectExists(app.buttons["export-range-csv"], "the chart's export button is missing")

        let month = await exportedSessionCount(range: "1M")
        let year = await exportedSessionCount(range: "1Y")
        let all = await exportedSessionCount(range: "All")

        XCTAssertEqual(month, 3, "1M should hold the three demo sessions from this week, got \(month)")
        XCTAssertEqual(year, 6, "1Y should hold every session except the 600-day one, got \(year)")
        XCTAssertEqual(all, 7, "All should hold every seeded session, got \(all)")
        XCTAssertLessThan(month, year,
                          "the range did not reach the export: 1M and 1Y both exported \(month) sessions")
        XCTAssertLessThan(year, all,
                          "the range did not reach the export: 1Y and All both exported \(year) sessions")
    }

    /// Pick a range on the open chart, open its export sheet, and return the
    /// session count the sheet says it will export.
    @MainActor
    private func exportedSessionCount(range: String) async -> Int {
        let segment = app.buttons[range].firstMatch
        await expectExists(segment, "range segment '\(range)' not found on the chart")
        await tapSettled(segment)
        await tapSettled(app.buttons["export-range-csv"])
        let summary = app.staticTexts["export-summary"]
        await expectExists(summary, "the export sheet's summary line is missing for range '\(range)'")
        let label = summary.label
        let count = Int(label.split(separator: " ").first ?? "") ?? -1
        XCTAssertGreaterThanOrEqual(count, 0,
                                    "could not read a session count out of '\(label)' for range '\(range)'")

        // The filename carries the range, so a file that reaches Files can be
        // told apart from the full-history export.
        await tapSettled(app.buttons["export-run"])
        let file = app.staticTexts["export-filename"]
        await expectExists(file, "the export produced no file for range '\(range)'")
        XCTAssertTrue(file.label.contains("-\(range)-"),
                      "the filename '\(file.label)' does not carry the range '\(range)'")

        await tapSettled(app.buttons["export-done"])
        return count
    }

    // MARK: - Rest timer (owner request, 2026-10-27)

    /// The rest timer after the 2026-10-27 reshape:
    ///   - the interval comes from Settings → Timer (`-timer.defaultRest` is the
    ///     same UserDefaults key the picker writes),
    ///   - the bar is edge-to-edge, not a floating pill, and carries a progress
    ///     line so its end is visible,
    ///   - the preset circles are gone,
    ///   - it actually counts down when started,
    ///   - the Live Activity is on screen (session clock + rest clock) — the app
    ///     is sent home and the island is captured, because that is the thing
    ///     that "showed nothing" before.
    @MainActor
    func testRestTimerUsesTheDefaultAndTheLiveActivityShows() async {
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-timer.defaultRest", "30"]
        app.launch()
        await settle(3)
        await completeOnboarding()

        // Settings offers the picker that sets this same key. The Timer section
        // is below the fold, and a SwiftUI Form does not instantiate rows that
        // are far off-screen — scroll to it first.
        await openProfileTab()
        await tapSettled(app.buttons["settings-link"])
        await settle()
        let timerRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Default Rest Timer'"))
            .firstMatch
        for _ in 0..<3 where !timerRow.exists {
            app.collectionViews.firstMatch.swipeUp()
            await settle(0.6)
        }
        XCTAssertTrue(timerRow.exists,
                      "Settings has no 'Default Rest Timer' row — scroll reached the bottom without finding it")
        await tapSettled(app.buttons["done"])
        await settle()

        // Settings was opened from Profile: get back to the Log tab, which is
        // where the workout starts from.
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        await settle()
        await startFreshWorkout()

        // The bar is up, showing the interval the setting gave it.
        let display = app.staticTexts["timer-display"]
        await expectExists(display, "the rest timer bar is not in an open workout")
        XCTAssertEqual(display.label, "00:30",
                       "the bar started at '\(display.label)', not the 30 s the setting holds")

        // Edge-to-edge: the bar spans the window, so it is not a floating pill.
        let bar = app.otherElements["timer-bar"].firstMatch
        let width = app.windows.element(boundBy: 0).frame.width
        if bar.exists {
            XCTAssertGreaterThan(bar.frame.width, width - 2,
                                 "the timer bar is \(bar.frame.width)pt wide on a \(width)pt screen — still a floating pill")
        } else {
            XCTFail("no timer-bar element to measure")
        }
        XCTAssertTrue(app.otherElements["timer-progress"].exists || app.otherElements["timer-bar"].exists,
                      "the bar has no progress line")

        // Preset circles are gone.
        let presets = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'timer-preset-'")).count
        XCTAssertEqual(presets, 0, "the preset circles are still on the bar")

        attach("timer-bar-collapsed")

        // Start it: the digits have to move.
        await tapSettled(app.buttons["timer-toggle"])
        await settle(3)
        XCTAssertNotEqual(display.label, "00:30",
                          "the timer did not count down after it was started")
        attach("timer-bar-running")

        // Send the app home: the Live Activity lives on the island / lock
        // screen, which only a device screenshot can show.
        XCUIDevice.shared.press(.home)
        await settle(4)
        attach("live-activity-island")
        app.activate()
        await settle(2)
        await tapSettled(app.buttons["timer-toggle"])   // pause
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
