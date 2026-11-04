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
    private func logIn(_ app: XCUIApplication) {
        let email = app.textFields["login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("test@example.com")

        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("Password1")
        app.buttons["login.submit"].tap()

        // The fake backend starts with no tasks: the empty state means the list has loaded and the
        // sign-in transition is over, so the next tap won't be swallowed by the animation.
        XCTAssertTrue(app.staticTexts["No Tasks"].waitForExistence(timeout: 10))

        // iOS offers to save the password after a login form disappears; that system prompt would
        // otherwise intercept whichever tap comes next.
        dismissPasswordPrompt(in: app, waitingUpTo: 8)
    }

    /// A task row by its visible title (row identifiers carry the task id, which the test can't know).
    @MainActor
    private func taskRow(titled title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow.' AND label == %@", title)).firstMatch
    }

    @MainActor
    private func dismissPasswordPrompt(in app: XCUIApplication, waitingUpTo timeout: TimeInterval) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: timeout) { notNow.tap() }
    }

    /// Taps `element` and waits for `expected`. If the AutoFill prompt swallowed the tap,
    /// dismisses it and taps once more.
    @MainActor
    private func tap(_ element: XCUIElement, expecting expected: XCUIElement, in app: XCUIApplication) {
        element.tap()
        if expected.waitForExistence(timeout: 3) { return }
        dismissPasswordPrompt(in: app, waitingUpTo: 5)
        element.tap()
        XCTAssertTrue(expected.waitForExistence(timeout: 5))
    }

    @MainActor
    private func signOut(_ app: XCUIApplication) {
        let signOut = app.buttons["settings.signOut"]
        tap(app.buttons["taskList.settings"], expecting: signOut, in: app)
        // Confirmation dialogs can expose the action twice (popover and sheet representations).
        let confirm = app.buttons["settings.confirmSignOut"].firstMatch
        // The sheet may still be animating in when the button first appears; retry if the tap is lost.
        tap(signOut, expecting: confirm, in: app)
        confirm.tap()

        XCTAssertTrue(app.buttons["login.submit"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testLogInAndSignOut() {
        let app = launchApp()
        logIn(app)
        signOut(app)
    }

    /// The main flow from the brief: create with a due date, edit, complete, delete, log out.
    @MainActor
    func testTaskLifecycle() {
        let app = launchApp()
        logIn(app)

        // Create
        // Multi-line (`axis: .vertical`) fields surface as text views, so match by identifier only.
        let title = app.descendants(matching: .any)["taskEditor.title"].firstMatch
        tap(app.buttons["taskList.add"], expecting: title, in: app)
        title.typeText("Buy milk")
        let dueToggle = app.switches["taskEditor.hasDueDate"]
        // Tap the switch control itself; the row's centre is only its label.
        dueToggle.switches.firstMatch.tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: dueToggle)
        waitForExpectations(timeout: 5)
        app.buttons["taskEditor.save"].tap()

        let row = taskRow(titled: "Buy milk", in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))

        // Edit
        row.tap()
        app.buttons["taskDetail.edit"].tap()
        let editTitle = app.descendants(matching: .any)["taskEditor.title"].firstMatch
        XCTAssertTrue(editTitle.waitForExistence(timeout: 5))
        // Tap past the end of the existing text so typing appends.
        editTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        editTitle.typeText(" today")
        app.buttons["taskEditor.save"].tap()
        let detailTitle = app.staticTexts["taskDetail.title"]
        XCTAssertTrue(detailTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(detailTitle.label, "Buy milk today")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // Complete with the leading swipe action
        let editedRow = taskRow(titled: "Buy milk today", in: app)
        XCTAssertTrue(editedRow.waitForExistence(timeout: 5))
        editedRow.swipeRight()
        app.buttons["Complete"].tap()
        let completed = NSPredicate(format: "value CONTAINS[c] %@", "Done")
        expectation(for: completed, evaluatedWith: editedRow)
        waitForExpectations(timeout: 5)

        // Delete with the trailing swipe action
        editedRow.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let confirmDelete = app.buttons["taskList.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5))
        confirmDelete.tap()
        XCTAssertTrue(editedRow.waitForNonExistence(timeout: 5))
        // The dialog's window lingers while it animates away and would swallow the next tap.
        XCTAssertTrue(confirmDelete.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Tasks"].waitForExistence(timeout: 5))

        signOut(app)
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
