import XCTest

/// Temporary diagnostic: dump the accessibility identifiers/labels XCUITest
/// actually exposes on the main app, so the real UI test can address elements
/// by ground truth rather than guesswork.
final class RepLogUIDiagTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "im.eamon.replog")
        app.terminate()
        app.launchArguments = ["-ResetRepLog", "YES"]
        app.launch()
    }

    @MainActor
    func testDumpTree() async {
        // onboarding
        let next = app.buttons["onboarding-next"]
        if next.waitForExistence(timeout: 10) { next.tap() }
        if next.waitForExistence(timeout: 5) { next.tap() }
        if next.waitForExistence(timeout: 5) { next.tap() }
        // Get Started may reuse onboarding-next id
        let gs = app.buttons["onboarding-next"]
        if gs.waitForExistence(timeout: 5) { gs.tap() }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("=== BUTTONS (id | label) ===")
        for el in app.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== TABBAR BUTTONS (id | label) ===")
        for el in app.tabBars.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== STATIC TEXT (first 20) ===")
        for el in app.staticTexts.allElementsBoundByIndex.prefix(20) { print("  text=\(el.label)") }
    }
}
