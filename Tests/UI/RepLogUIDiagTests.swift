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

        print("=== BUTTON IDENTIFIERS ===")
        for id in app.buttons.allElementsIdentifiers { print("  id: \(id)") }
        print("=== BUTTON LABELS ===")
        for l in app.buttons.allLabels { print("  label: \(l)") }
        print("=== TABBAR BUTTON IDENTIFIERS ===")
        for id in app.tabBars.buttons.allElementsIdentifiers { print("  id: \(id)") }
        print("=== TABBAR BUTTON LABELS ===")
        for l in app.tabBars.buttons.allLabels { print("  label: \(l)") }
        print("=== STATICTEXT LABELS ===")
        for l in app.staticTexts.allLabels.prefix(20) { print("  text: \(l)") }
    }
}
