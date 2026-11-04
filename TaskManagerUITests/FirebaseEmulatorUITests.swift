import XCTest

/// End-to-end against the Firebase Local Emulator Suite: real Firebase Auth, Firestore (with the
/// project's security rules) and the app's sync engine, without touching production.
///
/// Run `firebase emulators:start --only auth,firestore,storage` first; otherwise the test skips.
final class FirebaseEmulatorUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func emulatorsAreRunning() -> Bool {
        guard let url = URL(string: "http://127.0.0.1:9099/") else { return false }
        let done = expectation(description: "Auth emulator reachable")
        var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = response != nil
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 3)
        return reachable
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-firebaseEmulators"]
        app.launch()
        return app
    }

    @MainActor
    private func dismissPasswordPrompt(in app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 6) { notNow.tap() }
    }

    private static let documents = "http://127.0.0.1:8080/v1/projects/task-manager-3d000/databases/(default)/documents"

    /// Sends a JSON request and returns the decoded body; fails the test on a non-2xx status.
    private func send(_ method: String, _ urlString: String, token: String? = nil,
                      body: [String: Any]? = nil) throws -> [String: Any] {
        var request = URLRequest(url: try XCTUnwrap(URL(string: urlString)))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let done = expectation(description: "\(method) \(urlString)")
        var status = 0
        var payload = Data()
        URLSession.shared.dataTask(with: request) { data, response, _ in
            status = (response as? HTTPURLResponse)?.statusCode ?? 0
            payload = data ?? Data()
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        XCTAssertTrue((200..<300).contains(status), "\(method) \(urlString) returned \(status): \(String(decoding: payload, as: UTF8.self))")
        return (try? JSONSerialization.jsonObject(with: payload) as? [String: Any]) ?? [:]
    }

    /// Creates an account directly in the Auth emulator (sign-up typing is unreliable in the simulator
    /// because Strong Password AutoFill swallows keystrokes in `.newPassword` fields).
    /// - Returns: the new user's uid and ID token.
    @discardableResult
    private func createEmulatorAccount(email: String, password: String, name: String) throws -> (uid: String, token: String) {
        let body = try send("POST", "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator",
                            body: ["email": email, "password": password, "displayName": name, "returnSecureToken": true])
        return (try XCTUnwrap(body["localId"] as? String), try XCTUnwrap(body["idToken"] as? String))
    }

    /// A previous test's Firebase session survives relaunch; start from the login screen.
    @MainActor
    private func signOutIfNeeded(_ app: XCUIApplication) {
        let settings = app.buttons["taskList.settings"]
        guard !app.textFields["login.email"].waitForExistence(timeout: 8), settings.exists else { return }
        dismissPasswordPrompt(in: app)
        settings.tap()
        let signOut = app.buttons["settings.signOut"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        let confirm = app.buttons["settings.confirmSignOut"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
    }

    @MainActor
    private func signIn(_ app: XCUIApplication, email: String) {
        signOutIfNeeded(app)
        let emailField = app.textFields["login.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 15))
        emailField.tap()
        emailField.typeText(email)
        let password = app.secureTextFields["login.password"]
        password.tap()
        password.typeText("Password1")
        app.buttons["login.submit"].tap()
        XCTAssertTrue(app.staticTexts["No Tasks"].waitForExistence(timeout: 20), "Sign-in did not reach the task list")
        dismissPasswordPrompt(in: app)
    }

    @MainActor
    private func createTask(_ app: XCUIApplication, title: String) {
        let add = app.buttons["taskList.add"]
        add.tap()
        let titleField = app.descendants(matching: .any)["taskEditor.title"].firstMatch
        if !titleField.waitForExistence(timeout: 3) {
            dismissPasswordPrompt(in: app)
            add.tap()
        }
        XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.typeText(title)
        app.buttons["taskEditor.save"].tap()
        XCTAssertTrue(app.staticTexts["All changes synced"].waitForExistence(timeout: 20), "The task was not confirmed by Firestore")
    }

    @MainActor
    private func row(_ app: XCUIApplication, title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'taskRow.' AND label == %@", title)).firstMatch
    }

    @MainActor
    func testSignInCreateTaskSyncAndRestoreSession() throws {
        try XCTSkipUnless(emulatorsAreRunning(), "Firebase emulators are not running")
        let email = "owner-\(UUID().uuidString.prefix(8).lowercased())@example.com"
        let title = "Synced task \(UUID().uuidString.prefix(4))"
        try createEmulatorAccount(email: email, password: "Password1", name: "Emulator Owner")

        var app = launch()
        signIn(app, email: email)
        createTask(app, title: title)

        // Relaunch: the Firebase session is restored and the task comes back.
        app.terminate()
        app = launch()
        XCTAssertTrue(row(app, title: title).waitForExistence(timeout: 20), "Session or task was not restored after relaunch")
    }

    /// Owner shares a task in the app; the collaborator (acting through Firestore's REST API, so the
    /// security rules apply) marks it done; the owner's app shows the change live.
    @MainActor
    func testCollaboratorStatusChangeReachesOwnerLive() throws {
        try XCTSkipUnless(emulatorsAreRunning(), "Firebase emulators are not running")
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let ownerEmail = "owner-\(suffix)@example.com"
        let collaboratorEmail = "collab-\(suffix)@example.com"
        let title = "Shared task \(suffix.prefix(4))"
        try createEmulatorAccount(email: ownerEmail, password: "Password1", name: "Emulator Owner")
        let collaborator = try createEmulatorAccount(email: collaboratorEmail, password: "Password1", name: "Grace Collab")
        // The collaborator's profile, as the app writes it on their first sign-in.
        try send("PATCH", "\(Self.documents)/users/\(collaborator.uid)", token: collaborator.token, body: ["fields": [
            "email": ["stringValue": collaboratorEmail], "displayName": ["stringValue": "Grace Collab"]
        ]])

        let app = launch()
        signIn(app, email: ownerEmail)
        createTask(app, title: title)

        // Share it through the app's invite sheet (email lookup in users/, then memberIds update).
        row(app, title: title).tap()
        var share = app.buttons["taskDetail.share"]
        if !share.waitForExistence(timeout: 3) {
            // Secondary actions live in the overflow menu, where items lose their identifiers.
            app.navigationBars.buttons["More"].firstMatch.tap()
            share = app.buttons["Share"].firstMatch
        }
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let inviteEmail = app.textFields["invite.email"]
        XCTAssertTrue(inviteEmail.waitForExistence(timeout: 5))
        inviteEmail.tap()
        inviteEmail.typeText(collaboratorEmail)
        app.buttons["invite.submit"].tap()
        let invited = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "can now see this task")).firstMatch
        XCTAssertTrue(invited.waitForExistence(timeout: 15), "Invite by email failed")
        app.buttons["Done"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["All changes synced"].waitForExistence(timeout: 20), "Sharing was not pushed")

        // As the collaborator: find the task through the member query, then change only the status fields.
        let documentName = try sharedTaskName(token: collaborator.token, uid: collaborator.uid)
        let now = ISO8601DateFormatter().string(from: Date())
        let mask = ["status", "statusUpdatedAt", "updatedAt", "updatedBy"].map { "updateMask.fieldPaths=\($0)" }.joined(separator: "&")
        try send("PATCH", "http://127.0.0.1:8080/v1/\(documentName)?\(mask)", token: collaborator.token, body: ["fields": [
            "status": ["stringValue": "done"],
            "statusUpdatedAt": ["timestampValue": now],
            "updatedAt": ["timestampValue": now],
            "updatedBy": ["stringValue": collaborator.uid]
        ]])

        // The owner's list follows the listener: the row now reads Done.
        let sharedRow = row(app, title: title)
        expectation(for: NSPredicate(format: "value CONTAINS[c] %@", "Done"), evaluatedWith: sharedRow)
        waitForExpectations(timeout: 20)
    }

    /// The document name of the one task shared with `uid`, found the way the app finds it.
    private func sharedTaskName(token: String, uid: String) throws -> String {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "\(Self.documents):runQuery")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": [
            "from": [["collectionId": "tasks"]],
            "where": ["fieldFilter": ["field": ["fieldPath": "memberIds"], "op": "ARRAY_CONTAINS",
                                      "value": ["stringValue": uid]]]
        ]])
        let done = expectation(description: "runQuery")
        var payload = Data()
        URLSession.shared.dataTask(with: request) { data, _, _ in
            payload = data ?? Data()
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
        let rows = try XCTUnwrap(try JSONSerialization.jsonObject(with: payload) as? [[String: Any]])
        let document = try XCTUnwrap(rows.compactMap { $0["document"] as? [String: Any] }.first, "Collaborator can't see the task")
        return try XCTUnwrap(document["name"] as? String)
    }
}
