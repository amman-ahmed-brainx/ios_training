import XCTest

/// Auth flow against the fake backend (`-uitest`): no network, deterministic.
final class AuthFlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
        return app
    }

    @MainActor
    func testInvalidLoginShowsInlineErrors() {
        let app = launchApp()
        let submit = app.buttons["login.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))

        submit.tap()

        XCTAssertTrue(app.staticTexts["This field is required."].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testLogInAndSignOut() {
        let app = launchApp()
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("test@example.com")

        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("Password1")
        app.buttons["login.submit"].tap()

        let signOut = app.buttons["home.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 10))
        signOut.tap()

        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLoginScreenPassesAccessibilityAudit() throws {
        let app = launchApp()
        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit { issue in
            // Name the element so a failure is actionable without re-running in Accessibility Inspector.
            let element = issue.element.map { "\($0.elementType.rawValue) '\($0.label)' id=\($0.identifier)" } ?? "none"
            XCTFail("\(issue.compactDescription) – element: \(element)")
            return true
        }
    }
}
