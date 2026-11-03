import Testing
@testable import TaskManager

/// Retain-cycle tests: each drops the last strong reference and checks the object is actually freed.
@MainActor
struct AuthMemoryLeakTests {
    @Test func loginViewModelIsReleasedAfterSubmitting() async {
        weak var weakModel: LoginViewModel?
        do {
            let model = LoginViewModel(auth: MockAuthService())
            model.email = "ada@example.com"
            model.password = "Password1"
            await model.submit()
            weakModel = model
        }
        #expect(weakModel == nil)
    }

    @Test func sessionControllerIsReleasedAfterStop() async {
        let auth = MockAuthService()
        weak var weakController: SessionController?
        do {
            let controller = SessionController(auth: auth, profiles: MockUserProfileStore())
            controller.start()
            auth.emit(.signedIn(.ada))
            await eventually { controller.state == .signedIn(.ada) }
            controller.stop()
            weakController = controller
        }
        await eventually { weakController == nil }
    }
}
