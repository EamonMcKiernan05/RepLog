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
        func shot(_ name: String) {
            if let data = app.screenshot().image.pngData() {
                try? data.write(to: URL(fileURLWithPath: "/tmp/\(name).png"))
            }
        }
        let next = app.buttons["onboarding-next"]
        _ = next.waitForExistence(timeout: 10)
        print("BEFORE: exists=\(next.exists) frame=(\(next.frame.origin.x),\(next.frame.origin.y),\(next.frame.size.width),\(next.frame.size.height))")
        shot("ob-before")
        next.tap()
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let after = app.buttons["onboarding-next"]
        print("AFTER TAP1: exists=\(after.exists) label=\(after.label ?? "?")")
        shot("ob-after1")
        if after.exists {
            after.tap()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let after2 = app.buttons["onboarding-next"]
        print("AFTER TAP2: exists=\(after2.exists) label=\(after2.label ?? "?")")
        shot("ob-after2")
        print("plus exists: \(app.buttons["plus"].exists)")
        print("tabbar count: \(app.tabBars.buttons.allElementsBoundByIndex.count)")
    }
}
