import XCTest

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
    func testTapOnboarding() async {
        let next = app.buttons["onboarding-next"]
        _ = next.waitForExistence(timeout: 10)
        print("BEFORE: exists=\(next.exists) frame=(\(next.frame.origin.x),\(next.frame.origin.y),\(next.frame.size.width),\(next.frame.size.height))")
        app.screenshot().saveToFile(named: "/tmp/ob-before.png")
        next.tap()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let after = app.buttons["onboarding-next"]
        print("AFTER TAP1: exists=\(after.exists) label=\(after.label ?? "?")")
        app.screenshot().saveToFile(named: "/tmp/ob-after1.png")
        if after.exists {
            after.tap()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let after2 = app.buttons["onboarding-next"]
        print("AFTER TAP2: exists=\(after2.exists) label=\(after2.label ?? "?")")
        app.screenshot().saveToFile(named: "/tmp/ob-after2.png")
        // Is the main app showing now?
        print("plus exists: \(app.buttons["plus"].exists)")
        print("tabbar count: \(app.tabBars.buttons.allElementsBoundByIndex.count)")
    }
}
