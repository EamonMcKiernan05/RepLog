import XCTest

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
    private func addFirstExercise() async {
        await tapSettled(app.buttons["add-exercise"])
        let absCat = app.buttons["category-Abs"]
        await expectExists(absCat, "'Abs' category not found")
        await tapSettled(absCat)
        let abWheel = app.buttons["pick-Ab Wheel"]
        await expectExists(abWheel, "'Ab Wheel' not found")
        await tapSettled(abWheel)
        await expectExists(app.buttons["rpe-cell"], "RPE cell not shown after adding exercise")
    }

    /// Fill the first set's weight/reps/RPE through the real input sheets
    /// (XCUITest is the only way — agent-device keystrokes do not update
    /// SwiftUI bindings).
    @MainActor
    private func fillFirstSet(weight: String, reps: String, rpe: String) async {
        await tapSettled(app.buttons["weight-cell"])
        let w = app.textFields["number-field"]
        await expectExists(w, "weight field not found")
        w.tap(); w.typeText(weight)
        await tapSettled(app.buttons["done"])

        await tapSettled(app.buttons["reps-cell"])
        let r = app.textFields["number-field"]
        await expectExists(r, "reps field not found")
        r.tap(); r.typeText(reps)
        await tapSettled(app.buttons["done"])

        await tapSettled(app.buttons["rpe-cell"])
        let rp = app.textFields["rpe-field"]
        await expectExists(rp, "RPE field not found")
        rp.tap(); rp.typeText(rpe)
        await tapSettled(app.buttons["done"])
    }

    // MARK: - RPE entry

    @MainActor
    func testRPEEntryTypes85AndReadsBack() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["rpe-cell"])
        let field = app.textFields["rpe-field"]
        await expectExists(field, "RPE field not found")
        field.tap()
        field.typeText("8.5")
        let done = app.buttons["done"]
        await expectExists(done, "RPE 'Done' not found")
        await tapSettled(done)

        // Read it back: the RPE cell now shows 8.5.
        let rpeCell = app.buttons["rpe-cell"]
        await expectExists(rpeCell, "RPE cell missing after entry")
        let label = rpeCell.label ?? ""
        XCTAssertTrue(label.contains("8.5"), "RPE cell should read 8.5, got '\(label)'")
    }

    /// The quick chips must display whole values without a trailing ".0"
    /// (plan §3.2: chips 6, 7, 7.5, 8, 8.5, 9; "displays 8, not 8.0").
    @MainActor
    func testRPEChipsDisplayWholeValues() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["rpe-cell"])
        await expectExists(app.textFields["rpe-field"], "RPE sheet not found")

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
        await tapSettled(app.buttons["done"])
        let rpeCell = app.buttons["rpe-cell"]
        await expectExists(rpeCell, "RPE cell missing after chip tap")
        let label = rpeCell.label ?? ""
        XCTAssertTrue(label.contains("8") && !label.contains("8.0"),
                      "RPE cell should read '8' (not '8.0'), got '\(label)'")
    }

    // MARK: - Session row navigation

    /// Tapping a session row in the Log must push the session detail
    /// (plan §6.1). Regression test: the row was a Button setting the item of
    /// .navigationDestination(item:) and the push never fired.
    @MainActor
    func testSessionRowOpensDetail() async {
        // Finish one workout so the Log has a row to tap.
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()
        await fillFirstSet(weight: "100", reps: "5", rpe: "8")
        await tapSettled(app.buttons["finish-workout"])
        await settle(2)
        // Back on the Log tab: the finished session renders as a row.
        let row = app.buttons["session-row-"]
        await expectExists(row, "session row not shown in Log after finishing")

        // Tap it — the detail view must push.
        await tapSettled(row)
        let detail = app.buttons["session-detail-menu"]
        await expectExists(detail, "session detail did not open after tapping the row")
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
        // Tap the switch KNOB, not the row: a SwiftUI Form does not toggle
        // from a label tap, and the element's centre is the label. The knob
        // is the trailing subelement of the switch.
        let knob = toggle.otherElements.last ?? toggle
        await tapSettled(knob)

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
    }

    // MARK: - Set notes

    @MainActor
    func testSetNoteEntry() async {
        await completeOnboarding()
        await startFreshWorkout()
        await addFirstExercise()

        await tapSettled(app.buttons["notes-cell"])
        let field = app.textFields["set-note-field"]
        await expectExists(field, "set note field not found")
        field.tap()
        field.typeText("felt heavy")
        let save = app.buttons["save-note"]
        await expectExists(save, "note 'Save' not found")
        await tapSettled(save)

        // The note renders as a second line under the row.
        let noteLine = app.staticTexts["felt heavy"]
        await expectExists(noteLine, "set note 'felt heavy' not displayed")
    }

    // MARK: - Offline drill (plan §7.5)

    /// The lift-sync service for this drill: a real uvicorn on a private
    /// port with a private token (no real data, no prod service).
    private let drillPort = 8391
    private let drillToken = "uitest-drill-token"
    private var drillProc: Process?
    private var drillDataDir: URL!

    /// Start the drill service (fresh data dir) and wait for its health.
    private func startDrillService() throws {
        drillDataDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("replog-drill-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: drillDataDir, withIntermediateDirectories: true)

        let repo = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Documents/RepLog")
        let proc = Process()
        proc.executableURL = repo.appendingPathComponent("service/.venv/bin/uvicorn")
        proc.arguments = ["lift_sync.app:app", "--port", String(drillPort),
                          "--host", "127.0.0.1", "--log-level", "warning"]
        proc.environment = ["LIFT_SYNC_DATA_DIR": drillDataDir.path,
                            "LIFT_SYNC_TOKEN": drillToken,
                            "PATH": "/usr/bin:/bin"]
        proc.currentDirectoryURL = repo.appendingPathComponent("service")
        let err = FileHandle.nullDevice
        proc.standardError = err
        proc.standardOutput = err
        try proc.run()
        drillProc = proc

        // Wait for the service to come up.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let ok = try? await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(drillPort)/v1/health")!).response as? HTTPURLResponse,
               ok.statusCode == 200 {
                return
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        XCTFail("drill service did not come up on port \(drillPort)")
    }

    private func stopDrillService() {
        drillProc?.terminate()
        drillProc?.waitUntilExit()
        drillProc = nil
    }

    /// Count the rows for one session in the service's CSV.
    private func drillRows(sessionID: String) -> Int {
        let url = drillDataDir.appendingPathComponent("sessions.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return -1 }
        return text.split(separator: "\n").filter { line in
            line.hasPrefix(sessionID + ",")
        }.count
    }

    /// POST the same session payload again (the resurrection attempt).
    private func drillReimport(sessionID: String) async -> Int {
        let body: [String: Any] = [
            "session_id": sessionID,
            "date": "2026-09-22",
            "sets": [["exercise": "Drill", "set_number": 1, "weight_kg": 100.0, "reps": 5]],
        ]
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(drillPort)/v1/sessions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(drillToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        return (resp as? HTTPURLResponse)?.statusCode ?? -1
    }

    /// Plan §7.5, in-simulator: service stopped -> finish a session ->
    /// relaunch the app -> service back up -> exactly one upload -> delete ->
    /// tombstone lands -> re-import 409s.
    @MainActor
    func testOfflineDrill() async throws {
        // 0. The drill port must be free (service down for the offline phase).
        let probe = URL(string: "http://127.0.0.1:\(drillPort)/v1/health")!
        do {
            let (_, resp) = try await URLSession.shared.data(from: probe)
            XCTFail("drill port \(drillPort) is already in use")
            _ = resp
        } catch {
            // Expected: connection refused — the service is down.
        }

        // 1. Configure sync (URL + token) with the service stopped.
        await completeOnboarding()
        let profile = app.tabBars.buttons.element(boundBy: 3)
        await expectExists(profile, "'Profile' tab not found")
        await tapSettled(profile)
        await tapSettled(app.buttons["settings-link"])
        let toggle = app.switches["enable-sync"]
        for _ in 0..<8 where !toggle.exists {
            app.swipeUp()
            await settle(0.5)
        }
        XCTAssertTrue(toggle.exists, "'Enable Sync' toggle not found")
        let knob = toggle.otherElements.last ?? toggle
        await tapSettled(knob)
        let urlField = app.textFields["sync-url-field"]
        await expectExists(urlField, "sync URL field not found")
        urlField.tap()
        urlField.typeText("http://127.0.0.1:\(drillPort)")
        let tokenField = app.secureTextFields["sync-token-field"]
        await expectExists(tokenField, "sync token field not found")
        tokenField.tap()
        tokenField.typeText(drillToken)
        await tapSettled(app.buttons["done"])   // applies config + syncNow (fails: service down)

        // 2. Finish a session while the service is stopped -> queued offline.
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        await startFreshWorkout()
        await addFirstExercise()
        await fillFirstSet(weight: "100", reps: "5", rpe: "8")
        await tapSettled(app.buttons["finish-workout"])
        await settle(3)

        // The session is in the Log, and the Profile status shows it waiting.
        let row = app.buttons["session-row-"]
        await expectExists(row, "session row not shown after offline finish")
        let rowID = (row.identifier as NSString).replacingOccurrences(of: "session-row-", with: "")
        let sid = String(rowID.prefix(8))

        // 3. Relaunch the app (queue must survive the restart).
        app.terminate()
        await settle(1)
        app.launchArguments = ["-ResetRepLog", "NO"]
        app.launch()
        await settle(3)

        // 4. Service back up -> the queued session uploads exactly once.
        try startDrillService()
        // Give the app's sync a moment (foreground run / path monitor).
        await tapSettled(app.tabBars.buttons.element(boundBy: 3))
        let syncNow = app.buttons["sync-now"]
        await expectExists(syncNow, "'Sync now' not found")
        await tapSettled(syncNow)
        await settle(4)

        XCTAssertEqual(drillRows(sessionID: sid), 1,
                       "expected exactly the session's one set row, got \(drillRows(sessionID: sid))")
        // Exactly one upload: one upsert event for this session in the audit.
        let audit = try String(contentsOf: drillDataDir.appendingPathComponent("sessions.jsonl"), encoding: .utf8)
        let upserts = audit.components(separatedBy: "\n").filter {
            $0.contains("\"type\":\"upsert\"") && $0.contains(sid)
        }.count
        XCTAssertEqual(upserts, 1, "expected exactly one upload, got \(upserts) upsert events")

        // 5. Delete the session in the app -> tombstone lands on the server.
        await tapSettled(app.tabBars.buttons.element(boundBy: 0))
        await tapSettled(app.buttons["session-row-\(sid)"])
        await expectExists(app.buttons["session-detail-menu"], "session detail not open")
        await tapSettled(app.buttons["session-detail-menu"])
        await tapSettled(app.buttons["delete-workout"])
        let dialogDelete = app.buttons["Delete"]
        await expectExists(dialogDelete, "delete confirmation not shown")
        await tapSettled(dialogDelete)
        await settle(3)

        XCTAssertEqual(drillRows(sessionID: sid), 0, "session rows should be removed after delete")
        let jsonl = try String(contentsOf: drillDataDir.appendingPathComponent("sessions.jsonl"), encoding: .utf8)
        XCTAssertTrue(jsonl.contains("\"type\":\"delete\"") && jsonl.contains(sid),
                      "tombstone event not recorded for \(sid)")

        // 6. Re-import the same session -> the server must refuse (409).
        let status = await drillReimport(sessionID: sid)
        XCTAssertEqual(status, 409, "re-import of a tombstoned session must 409, got \(status)")
        XCTAssertEqual(drillRows(sessionID: sid), 0, "tombstoned session must not be resurrected")

        stopDrillService()
    }
}
