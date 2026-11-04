import Foundation
import Testing
@testable import TaskManager

@MainActor
struct AppEnvironmentTests {
    @Test func uiTestArgumentSelectsUITestMode() {
        let mode = AppEnvironment.Mode.resolve(arguments: ["TaskManager", "-uitest"], environment: [:])
        #expect(mode == .uiTest)
    }

    @Test func unitTestHostSelectsPreviewMode() {
        let mode = AppEnvironment.Mode.resolve(
            arguments: ["TaskManager"],
            environment: ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"]
        )
        #expect(mode == .preview)
    }

    @Test func normalLaunchSelectsLiveMode() {
        let mode = AppEnvironment.Mode.resolve(arguments: ["TaskManager"], environment: [:])
        #expect(mode == .live)
    }

    @Test func fakeModesNeverTouchTheBackend() {
        #expect(AppEnvironment(mode: .uiTest).backendStatus == .fake)
        #expect(AppEnvironment(mode: .preview).backendStatus == .fake)
    }

    @Test func uiTestModeStartsSignedOut() async {
        let environment = AppEnvironment(mode: .uiTest)
        environment.bootstrap()
        await eventually { environment.session.state == .signedOut(nil) }
        environment.session.stop()
    }

    @Test func uiTestAccountCanSignIn() async {
        let environment = AppEnvironment(mode: .uiTest)
        environment.bootstrap()
        let login = environment.makeLoginViewModel()
        login.email = FakeAuthService.uiTestEmail
        login.password = FakeAuthService.uiTestPassword

        await login.submit()

        await eventually { environment.session.currentSession?.email == FakeAuthService.uiTestEmail }
        environment.session.stop()
    }
}
