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
        let environment = AppEnvironment(mode: .uiTest)
        environment.bootstrap()
        #expect(environment.backendStatus == .fake)
    }

    @Test func bootstrapIsIdempotent() {
        let environment = AppEnvironment(mode: .preview)
        environment.bootstrap()
        environment.bootstrap()
        #expect(environment.backendStatus == .fake)
    }
}
