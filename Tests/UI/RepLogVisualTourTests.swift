import XCTest

/// Visual-pass capture harness (plan §5, §10 item 6). Drives the app through
/// every screen with the synthetic `-DemoData` history and attaches a
/// full-resolution screenshot per screen. XCUITest is used rather than
/// agent-device because the populated screens need real typing (a set's
/// weight/reps/RPE, a note) and agent-device keystrokes do not update SwiftUI
/// bindings.
///
/// Captures are XCTAttachments. Extract them with:
///   xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>
/// (manifest.json maps each attachment name to its file).
///
/// Set the simulator to dark BEFORE running:
///   xcrun simctl ui <udid> appearance dark
/// Run:
///   xcodebuild test -scheme RepLog \
///     -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
///     -only-testing:RepLogUITests/RepLogVisualTourTests
/// Optional (TEST_RUNNER_ prefix passes them to the test process):
///   TEST_RUNNER_TOUR_PREFIX=xxl-   prefixes every attachment name
///   TEST_RUNNER_TOUR_QUICK=1       only the heaviest screens (Dynamic Type pass)
///
/// This class is deliberately NOT part of the 7-test UI gate in
/// scripts/mac-tests.sh (which -skip-testing's it).
final class RepLogVisualTourTests: XCTestCase {

    private var app: XCUIApplication!
    private var captured: [String] = []
    private var prefix = ""
    private var quick = false

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        prefix = ProcessInfo.processInfo.environment["TOUR_PREFIX"] ?? ""
        quick = ProcessInfo.processInfo.environment["TOUR_QUICK"] != nil
        app = XCUIApplication()
        // Phase A: onboarding needs a launch WITHOUT -DemoData (the seed
        // marks onboarding done, and the onboarding pages are part of the
        // capture set).
        app.launchArguments = ["-ResetRepLog", "YES"]
        app.launch()
    }

    // MARK: - helpers

    @MainActor
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = prefix + name
        attachment.lifetime = .keepAlways
        add(attachment)
        captured.append(prefix + name)
        print("TOUR-CAPTURE \(prefix + name)")
    }

    @MainActor
    private func settle(_ seconds: Double = 1.2) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Scroll an element into the visible area (an element below the fold has
    /// a frame outside the screen, so a coordinate tap at its centre lands off
    /// screen and hits nothing — that is how the add-exercise and Personal
    /// Records steps silently missed).
    @MainActor
    private func bringIntoView(_ element: XCUIElement, maxSwipes: Int = 5) async {
        var swipes = 0
        while element.exists, swipes < maxSwipes {
            let f = element.frame
            let h = app.frame.height
            if f.minY >= 130 && f.maxY <= h - 130 { return }
            if f.maxY > h - 130 { app.swipeUp() } else { app.swipeDown() }
            await settle(0.9)
            swipes += 1
        }
    }

    /// Tap the first of `queries` that exists within the timeout.
    @MainActor
    @discardableResult
    private func tapAny(_ queries: [XCUIElement], _ what: String, timeout: TimeInterval = 8) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for q in queries where q.exists {
                await bringIntoView(q)
                guard q.exists else { continue }
                // Tap by coordinate: a plain .tap() raises a hard XCTest
                // failure for a not-hittable element (e.g. a cell half under
                // the navigation bar) and would abort the whole tour.
                let frame = q.frame
                guard frame.width > 0, frame.height > 0 else { continue }
                q.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                await settle()
                return true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        print("TOUR-MISS \(what)")
        return false
    }

    /// Tap an element by label, whatever element type it turns out to be.
    @MainActor
    @discardableResult
    private func tapLabel(_ label: String, timeout: TimeInterval = 6) async -> Bool {
        let exact = NSPredicate(format: "label == %@", label)
        let begins = NSPredicate(format: "label BEGINSWITH %@", label)
        return await tapAny([
            app.buttons.matching(exact).firstMatch,
            app.cells.matching(exact).firstMatch,
            app.buttons.matching(begins).firstMatch,
            app.cells.matching(begins).firstMatch,
            app.staticTexts.matching(exact).firstMatch,
        ], label, timeout: timeout)
    }

    @MainActor
    private func firstSessionRow() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'session-row-'")).firstMatch
    }

    /// The Log rows must read "3x Competition Bench" — never "0x".
    @MainActor
    private func logRowSummaryCheck() {
        let row = firstSessionRow()
        if row.waitForExistence(timeout: 12) {
            let label = row.label
            print("TOUR-ROW-LABEL \(label)")
            XCTAssertFalse(label.contains("0x "), "Log row still shows '0x' counts: \(label)")
        } else {
            print("TOUR-ROW-LABEL <no session row>")
        }
    }

    // MARK: - the tour

    @MainActor
    func testVisualTour() async {
        if !quick {
            // ---- Phase A: onboarding (no demo data yet) ----
            // A first launch on a just-booted simulator is slower than a warm
            // one; 2.5s was not always enough for the Continue button to exist
            // (missed once on 2026-09-24).
            await settle(4.5)
            shot("01-onboarding-units")
            if await tapAny([app.buttons["onboarding-next"]], "onboarding continue") {
                shot("02-onboarding-privacy")
                await tapAny([app.buttons["onboarding-next"]], "onboarding continue")
                shot("03-onboarding-sync")
                await tapAny([app.buttons["onboarding-next"]], "Get Started")
                await settle(1.5)
            }
        }

        // ---- Phase B: relaunch with the synthetic demo history ----
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES"]
        app.launch()
        await settle(3)
        shot("04-log")
        // The summary lines count entry.setEntries — they must not read "0x".
        logRowSummaryCheck()

        if !quick {
            // Start sheet, then the repeat-workout sheet from it.
            await tapAny([app.buttons["plus"]], "log plus")
            shot("05-start-workout-sheet")
            await tapAny([app.buttons["repeat-last"]], "repeat last")
            shot("06-repeat-workout-sheet")
            // Two Cancel taps: repeat sheet first, then the start sheet.
            await tapLabel("Cancel")
            await tapLabel("Cancel")
            // Re-open the start sheet to start from the demo routine.
            await tapAny([app.buttons["plus"]], "log plus again")
        } else {
            await tapAny([app.buttons["plus"]], "log plus")
        }

        // Start from the demo routine so the workout arrives with sets.
        if await tapLabel("Push Day") {
            await settle(2)
        } else {
            await tapAny([app.buttons["new-workout-today"]], "new workout today")
            await settle(1.5)
            await tapAny([app.buttons["add-exercise"]], "add exercise")
            await tapAny([app.buttons["category-Abs"]], "category abs")
            await tapAny([app.buttons["pick-Ab Wheel"]], "pick ab wheel")
            await settle(1)
        }
        shot("07-active-workout")

        if !quick {
            // Select Exercise sheet + a category drill-in (references 8148/8149).
            await tapAny([app.buttons["add-exercise"]], "add exercise")
            await settle(1)
            shot("08-select-exercise")
            await tapAny([app.buttons["category-Chest"], app.buttons["category-Bench Press"]], "category drill-in")
            shot("09-select-exercise-category")
            // The sheet's Cancel lives on its ROOT screen; the drill-in has a
            // back button first.
            await tapAny([app.navigationBars.buttons.element(boundBy: 0)], "back from category")
            await settle(1)
            await tapLabel("Cancel")
            await settle(1)

            // RPE typed in place (with the inline quick chips under the row),
            // then a note typed straight into the row's Notes box. The first
            // RPE box can sit half under the navigation bar, so nudge the
            // content up first (a small drag, not a full swipe).
            let rpeCell = app.textFields["rpe-cell"].firstMatch
            if rpeCell.exists, rpeCell.frame.minY < 200 {
                let dragStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
                let dragEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
                await settle(1)
            }
            await tapAny([app.textFields["rpe-cell"].firstMatch], "rpe cell")
            await settle(1)
            shot("10-rpe-inline")
            await tapAny([app.buttons["rpe-chip-8"]], "rpe chip 8")
            await settle(0.8)

            // A number typed straight into a set cell, shot with the caret in
            // the box and the keyboard up (the whole point: no sheet). The
            // demo routine's LAST set row is empty, so type there: XCUITest's
            // delete keys land wherever the tap put the caret and cannot be
            // trusted to clear a filled box.
            let weightCells = app.textFields.matching(identifier: "weight-cell")
            var emptyWeightCell: XCUIElement?
            for i in 0..<min(weightCells.count, 8) {
                let candidate = weightCells.element(boundBy: i)
                let value = (candidate.value as? String) ?? ""
                if value.isEmpty || value == "—" {
                    emptyWeightCell = candidate
                    break
                }
            }
            if let emptyWeightCell {
                await bringIntoView(emptyWeightCell)
                emptyWeightCell.tap()
                await settle(0.8)
                emptyWeightCell.typeText("140")
                await settle(0.6)
                shot("10b-set-cell-typed")
                await tapAny([app.buttons["keyboard-done"]], "keyboard done")
                await settle(0.8)
            }

            await tapAny([app.textFields["notes-cell"].firstMatch], "notes cell")
            await settle(0.8)
            let noteField = app.textFields["notes-cell"].firstMatch
            if noteField.exists {
                let existing = (noteField.value as? String) ?? ""
                if !existing.isEmpty, existing != "—" {
                    noteField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                              count: existing.count + 2))
                    await settle(0.4)
                }
                noteField.typeText("felt heavy")
                await tapAny([app.buttons["keyboard-done"]], "keyboard done")
            }
            await settle(1)
        }

        shot("11-active-workout-populated")

        if !quick {
            // The exercise card's "…" menu (owner screenshot, 2026-09-24) and
            // the End Time picker. Both are opened and dismissed: the tour
            // still finishes this workout through the checkmark below.
            // .firstMatch: every exercise card carries this identifier, so a
            // plain subscript query is ambiguous and aborts the tour.
            await tapAny([app.buttons["exercise-menu"].firstMatch], "exercise menu")
            await settle(1.2)
            shot("11b-exercise-menu")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.93)).tap()
            await settle(1)

            await tapAny([app.buttons["end-time-row"]], "end time row")
            await settle(1.2)
            shot("11c-end-time-picker")
            await tapAny([app.buttons["end-time-cancel"]], "cancel end time")
            await settle(1)

            // Rest timer dock (plan §6.8).
            await tapAny([app.buttons["timer-button"]], "timer button")
            await settle(1)
            shot("12-rest-timer")
            await tapAny([app.buttons["Close timer"]], "close timer")
            await settle(0.8)
        }

        // Finish -> Log -> session detail. The checkmark asks first now (owner
        // request, 2026-09-23): capture the dialog and cancel it. Then leave the
        // editor and come back — that path used to strand an open workout — and
        // finish through the confirmation.
        await tapAny([app.buttons["finish-workout"]], "finish workout")
        await settle(1.2)
        shot("12b-finish-confirm")
        // The dialog's .cancel button is not exposed to XCUITest on iOS 26
        // (measured 2026-09-24: 0 matches for a "Cancel" label across every
        // element type, and the dialog's other button is duplicated in the
        // tree), so cancel it by tapping outside the sheet.
        // dy 0.85, not 0.12: the iOS 26 dialog is a card pinned near the TOP of
        // the screen (its button starts at y=132pt of 874), so a tap at 0.12
        // lands INSIDE it and does nothing — the swipe then missed and 12c/12d
        // captured the workout screen instead of the Log (2026-09-24).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
        await settle(1.2)

        // Back to the Log: the open workout is marked in progress...
        //
        // Tap the nav bar's back chevron, not the edge swipe. Measured
        // 2026-09-24: an edge swipe here silently does nothing (12c captured
        // the editor twice, and the same miss made the UI test read "no rows
        // in the Log"), so the explicit control is used and the swipe is only
        // the fallback.
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
            await settle(1.5)
        } else {
            let backLeft = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let backMiddle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            backLeft.press(forDuration: 0.05, thenDragTo: backMiddle)
            await settle(1.5)
        }
        shot("12c-log-in-progress")
        // ...and tapping it reopens the EDITOR, not the read-only detail.
        await tapAny([firstSessionRow()], "in-progress row")
        await settle(1.5)
        shot("12d-open-workout-reopened")

        await tapAny([app.buttons["finish-workout"]], "finish workout")
        await settle(1.2)
        // .firstMatch: the dialog's button is nested inside a second element
        // with the same identifier (both 'finish-confirm'), so a plain
        // subscript query raises "Multiple matching elements" and the tour
        // aborted here on 2026-09-24.
        await tapAny([app.buttons["finish-confirm"].firstMatch], "confirm finish")
        await settle(2.5)
        await tapAny([firstSessionRow()], "session row")
        await settle(1.5)
        shot("13-session-detail")
        await tapAny([app.navigationBars.buttons.element(boundBy: 0)], "back from detail")
        await settle(1)

        if !quick {
            // Routines.
            await tapAny([app.tabBars.buttons.element(boundBy: 1)], "routines tab")
            await settle(1)
            shot("14-routines-list")
            await tapAny([app.buttons["routine-Push Day"]], "routine row")
            await settle(1.2)
            shot("15-routine-detail")
            await tapLabel("Competition Bench")
            await settle(1.2)
            shot("16-routine-exercise-editor")
            // The exercise editor is a sheet (Done/Cancel), the routine detail
            // is a push (back button) — try both shapes.
            await tapAny([app.buttons["Done"], app.buttons["Cancel"],
                          app.navigationBars.buttons.element(boundBy: 0)], "close routine editor")
            await settle(1)
            await tapAny([app.navigationBars.buttons.element(boundBy: 0)], "back to routines")
            await settle(1)
        }

        // Statistics hub.
        await tapAny([app.tabBars.buttons.element(boundBy: 2)], "statistics tab")
        await settle(1.2)
        shot("17-statistics-hub")

        if !quick {
            // Chart screen + personal records.
            await tapLabel("Exercises")
            await settle(1.2)
            await tapLabel("Competition Bench")
            await settle(1.5)
            shot("18-chart-screen")
            await tapLabel("Personal Records")
            await settle(1.2)
            shot("19-personal-records")
            await tapAny([app.buttons["Done"]], "pr done")
            await tapAny([app.navigationBars.buttons.element(boundBy: 0)], "back from chart")
            await settle(1)
        }

        // Profile + settings.
        await tapAny([app.tabBars.buttons.element(boundBy: 3)], "profile tab")
        await settle(1.2)
        shot("20-profile")
        await tapAny([app.buttons["settings-link"]], "settings link")
        await settle(1.2)
        shot("21-settings")
        await tapAny([app.buttons["done"]], "settings done")
        await settle(1)

        if !quick {
            // Exercise library and editor, then categories.
            await tapLabel("Edit Exercises")
            await settle(1.5)
            shot("22-exercise-library")
            await tapAny([app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise-'")).firstMatch],
                         "library row")
            await settle(1.2)
            shot("23-exercise-editor")
            await tapLabel("Cancel")   // editor sheet
            await settle(1)
            // Back in the library? Then dismiss it (no toolbar button — drag
            // it down) and confirm the Profile is showing before the next step.
            if await waitFor(app.textFields["library-search"], timeout: 4) {
                let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.03))
                let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.92))
                top.press(forDuration: 0.15, thenDragTo: bottom)
                await settle(1.5)
            }
            if !(await waitFor(app.buttons["settings-link"], timeout: 4)) {
                // Still covered: pull the sheet down once more.
                let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
                let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
                top.press(forDuration: 0.2, thenDragTo: bottom)
                await settle(1.5)
            }
            await tapLabel("Edit Categories")
            await settle(1.5)
            shot("24-edit-categories")
        }

        print("TOUR-CAPTURED (\(captured.count)): \(captured.joined(separator: ", "))")
    }

    /// The set-row layout variants under owner review (2026-09-24): one
    /// capture per `-RowLayout` value, the same screen every time so they can
    /// be compared side by side. Run with
    ///   -only-testing:RepLogUITests/RepLogVisualTourTests/testRowLayoutVariants
    ///
    /// Each variant relaunches with `-ResetRepLog YES -DemoData YES` so every
    /// shot starts from the identical demo workout (fresh store, same 4-set
    /// routine), and the shot is taken before anything is typed.
    @MainActor
    func testRowLayoutVariants() async {
        continueAfterFailure = true
        for variant in 1...4 {
            app.terminate()
            app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES",
                                   "-RowLayout", "\(variant)"]
            app.launch()
            await settle(4)

            await tapAny([app.buttons["plus"]], "log plus")
            await settle(1.5)
            // First launch shows the start sheet; a run that reopens an open
            // workout is already in the editor.
            _ = await tapLabel("Push Day", timeout: 4)
            await settle(2.5)
            shot("layout-v\(variant)")
        }

        // The chosen layout (variant 4) again, this time with an RPE and a
        // note typed in — once per Notes-column treatment under review. The
        // note is only visible with something in it.
        for style in 1...4 {
            app.terminate()
            app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES",
                                   "-RowLayout", "4", "-NotesStyle", "\(style)"]
            app.launch()
            await settle(4)
            await tapAny([app.buttons["plus"]], "log plus")
            await settle(1.5)
            _ = await tapLabel("Push Day", timeout: 4)
            await settle(2.5)

            await tapAny([app.textFields["rpe-cell"].firstMatch], "rpe cell")
            await settle(0.8)
            await tapAny([app.buttons["rpe-chip-8"]], "rpe chip 8")
            await settle(0.8)

            await tapAny([app.textFields["notes-cell"].firstMatch], "notes cell")
            await settle(0.8)
            let notesCell = app.textFields["notes-cell"].firstMatch
            if notesCell.exists {
                let existing = (notesCell.value as? String) ?? ""
                if !existing.isEmpty, existing != "—" {
                    notesCell.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                                              count: existing.count + 2))
                    await settle(0.4)
                }
                notesCell.typeText("felt heavy")
                await settle(0.6)
            }
            _ = await tapAny([app.buttons["keyboard-done"]], "keyboard done", timeout: 4)
            await settle(1)
            shot("notes-\(style)")
        }

        print("TOUR-CAPTURED (\(captured.count)): \(captured.joined(separator: ", "))")
    }

    /// TEMPORARY (migration check, removed once the scheme columns are gone).
    /// Phase 1: with the OLD schema, leave a store on disk holding a marker.
    @MainActor
    func testMigrationSnapshotOldSchema() async {
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES"]
        app.launch()
        await settle(4)
        _ = await tapAny([app.tabBars.buttons.element(boundBy: 1)], "routines tab")
        await settle(1.2)
        _ = await tapAny([app.buttons["routine-Push Day"]], "routine row")
        await settle(1.5)
        _ = await tapLabel("Competition Bench")
        await settle(1.5)
        let field = app.textFields["routine-exercise-notes-field"].firstMatch
        _ = await tapAny([field], "notes field")
        await settle(0.8)
        field.typeText("MIGRATION-PROBE-4242")
        await settle(0.6)
        _ = await tapAny([app.navigationBars.buttons["Done"].firstMatch], "sheet Done")
        await settle(1.5)
        let onRow = app.staticTexts["MIGRATION-PROBE-4242"].exists
        print("MIGRATION old schema: store written, marker on row=\(onRow)")
    }

    /// TEMPORARY (migration check). Phase 2: with the NEW schema (scheme columns
    /// dropped) and NO reset, the app must open the SAME store and still show
    /// the marker. An in-memory fallback would show an empty routine list, so
    /// finding the marker proves the on-disk store migrated.
    @MainActor
    func testMigrationSurvivedNewSchema() async {
        app.terminate()
        app.launchArguments = []
        app.launch()
        await settle(4)
        let logged = await waitFor(app.tabBars.buttons.element(boundBy: 1), timeout: 10)
        print("MIGRATION new schema: app opened=\(logged)")
        _ = await tapAny([app.tabBars.buttons.element(boundBy: 1)], "routines tab")
        await settle(1.5)
        let routine = app.buttons["routine-Push Day"].firstMatch
        let routineThere = await waitFor(routine, timeout: 8)
        print("MIGRATION new schema: routine present=\(routineThere)")
        if routineThere {
            _ = await tapAny([routine], "routine row")
            await settle(1.5)
            let marker = await waitFor(app.staticTexts["MIGRATION-PROBE-4242"], timeout: 8)
            print("MIGRATION new schema: MARKER SURVIVED=\(marker)")
            let note = app.textFields["routine-exercise-notes-field"].firstMatch
            print("MIGRATION new schema: note field on screen=\(note.exists)")
        }
    }

    /// The routine detail row under each style (owner report, 2026-09-24).
    /// A note is typed into one exercise first — the row only shows it when
    /// there is one.
    @MainActor
    func testRoutineRowVariants() async {
        continueAfterFailure = true
        for style in 1...3 {
            app.terminate()
            app.launchArguments = ["-ResetRepLog", "YES", "-DemoData", "YES",
                                   "-RoutineRow", "\(style)"]
            app.launch()
            await settle(4)

            await tapAny([app.tabBars.buttons.element(boundBy: 1)], "routines tab")
            await settle(1.2)
            await tapAny([app.buttons["routine-Push Day"]], "routine row")
            await settle(1.2)

            await tapLabel("Competition Bench")
            await settle(1.5)
            let field = app.textFields["routine-exercise-notes-field"].firstMatch
            if await waitFor(field, timeout: 5) {
                await tapAny([field], "routine exercise notes field")
                await settle(0.8)
                field.typeText("belt on, pause every rep")
                await settle(0.8)
                _ = await tapAny([app.buttons["keyboard-done"]], "keyboard done", timeout: 3)
                await settle(0.6)
            }
            _ = await tapAny([app.navigationBars.buttons["Done"].firstMatch], "sheet Done")
            await settle(1.5)
            shot("routine-row-\(style)")
        }
        print("TOUR-CAPTURED (\(captured.count)): \(captured.joined(separator: ", "))")
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return element.exists
    }
}
