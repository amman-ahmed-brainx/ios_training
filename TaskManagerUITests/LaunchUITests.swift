import XCTest

final class LaunchUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchesIntoFakeEnvironment() {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["root.placeholder"].waitForExistence(timeout: 10))
    }
}
