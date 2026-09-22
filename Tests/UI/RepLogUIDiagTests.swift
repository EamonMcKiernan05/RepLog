import XCTest

/// Temporary diagnostic: complete onboarding, then dump the main app's tab bar
/// and toolbar so the real UI test can address elements by ground truth.
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
        // Complete onboarding exactly like the real test: fresh query each tap.
        for _ in 0..<3 {
            let next = app.buttons["onboarding-next"]
            if next.waitForExistence(timeout: 6) {
                next.tap()
            } else {
                break
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        let still = app.buttons["onboarding-next"]
        print("=== ONBOARDING STILL PRESENT? ===")
        print("  onboarding-next exists: \(still.exists)")
        print("=== TABBAR BUTTONS (id | label) ===")
        for el in app.tabBars.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== NAVBAR BUTTONS (id | label) ===")
        for el in app.navigationBars.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
        print("=== ALL BUTTONS (id | label) ===")
        for el in app.buttons.allElementsBoundByIndex { print("  id=\(el.identifier) label=\(el.label)") }
    }
}
