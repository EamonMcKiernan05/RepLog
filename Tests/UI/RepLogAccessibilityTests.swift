import XCTest

/// VoiceOver / HIG proxy pass (plan §10 item 6): XCUITest's
/// `performAccessibilityAudit()` is the automatable stand-in for a manual
/// VoiceOver spot-check — it catches missing labels, tiny hit regions,
/// low contrast and clipped text.
///
/// Findings are REPORTED, never gated: the handler returns `true` (meaning
/// "handled by the test"), so the audit records the issue instead of
/// failing the test. The list is printed and goes in the visual-pass
/// section of docs/BUILD-REPORT.md.
///
/// This class is deliberately NOT part of the 7-test UI gate in
/// scripts/mac-tests.sh (which skips it with -skip-testing). Run it
/// standalone:
///   xcodebuild test -scheme RepLog \
///     -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
///     -only-testing:RepLogUITests/RepLogAccessibilityTests
final class RepLogAccessibilityTests: XCTestCase {

    private var app: XCUIApplication!
    private var findings: [String] = []

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-ResetRepLog", "YES"]
        app.launch()
    }

    /// Run the audit and record issues instead of failing.
    @MainActor
    private func audit(_ screen: String) {
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { el in
                    "\(el.elementType.rawValue) id='\(el.identifier)' label='\(el.label)'"
                } ?? "no element"
                self.findings.append("[\(screen)] type=\(issue.auditType.rawValue) | \(issue.compactDescription) | \(element)")
                return true
            }
        } catch {
            self.findings.append("[\(screen)] audit did not run: \(error)")
        }
    }

    @MainActor
    private func settle(_ seconds: Double = 1.2) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor
    func testAccessibilityAuditScreens() async {
        // 1. Onboarding (first page as launched).
        await settle(1)
        audit("onboarding")

        // 2. Log tab (empty state).
        for _ in 0..<3 {
            let next = app.buttons["onboarding-next"]
            guard next.waitForExistence(timeout: 3) else { break }
            next.tap()
            await settle()
        }
        audit("log-empty")

        // 3. Active workout with one exercise and one filled set.
        app.buttons["plus"].tap()
        await settle()
        app.buttons["new-workout-today"].tap()
        await settle()
        audit("active-workout-empty")
        app.buttons["add-exercise"].tap()
        await settle()
        if app.buttons["category-Abs"].waitForExistence(timeout: 3) { app.buttons["category-Abs"].tap() }
        await settle()
        if app.buttons["pick-Ab Wheel"].waitForExistence(timeout: 3) { app.buttons["pick-Ab Wheel"].tap() }
        await settle()
        audit("active-workout-with-exercise")

        // 4. Statistics hub and the Profile/Settings screen.
        app.tabBars.buttons.element(boundBy: 2).tap()
        await settle()
        audit("statistics")
        app.tabBars.buttons.element(boundBy: 3).tap()
        await settle()
        audit("profile")
        if app.buttons["settings-link"].waitForExistence(timeout: 3) { app.buttons["settings-link"].tap() }
        await settle()
        audit("settings")

        print("ACCESSIBILITY AUDIT FINDINGS (\(findings.count))")
        for f in findings { print("AUDIT " + f) }
    }
}
