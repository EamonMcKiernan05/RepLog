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
        // Complete onboarding robustly: keep tapping the onboarding button
        // (id onboarding-next) while it exists, up to 6 times.
        let next = app.buttons["onboarding-next"]
        for _ in 0..<6 {
            if next.waitForExistence(timeout: 4) {
                next.tap()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } else {
                break
            }
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        print("=== ONBOARDING STILL PRESENT? ===")
        print("  onboarding-next exists: \(next.exists)")
        print("=== BUTTONS (id | label) ===")
        for el in app.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== TABBAR BUTTONS (id | label) ===")
        for el in app.tabBars.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== NAVBAR BUTTONS (id | label) ===")
        for el in app.navigationBars.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== STATIC TEXT (first 25) ===")
        for el in app.staticTexts.allElementsBoundByIndex.prefix(25) { print("  text=\(el.label)") }
    }
}
