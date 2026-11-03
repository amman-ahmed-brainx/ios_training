import Testing
@testable import TaskManager

@MainActor
struct SessionControllerTests {
    private let auth = MockAuthService()
    private let profiles = MockUserProfileStore()

    private func makeController() -> (SessionController, MockSessionObserver) {
        let controller = SessionController(auth: auth, profiles: profiles)
        let observer = MockSessionObserver(auth: auth)
        controller.register(observer)
        controller.start()
        return (controller, observer)
    }

    private func signedIn(as session: AuthSession = .ada) async -> (SessionController, MockSessionObserver) {
        let (controller, observer) = makeController()
        auth.emit(.signedIn(session))
        await eventually { controller.state == .signedIn(session) }
        return (controller, observer)
    }

    @Test func startsUnknownAndResolvesToSignedOut() async {
        let (controller, _) = makeController()
        #expect(controller.state == .unknown)

        auth.emit(.signedOut(nil))

        await eventually { controller.state == .signedOut(nil) }
        controller.stop()
    }

    @Test func persistedSessionLandsSignedInAndEnsuresProfileOnce() async {
        let (controller, _) = await signedIn()

        // A token refresh re-emits the same user; the profile must not be rewritten each time.
        auth.emit(.signedIn(.ada))
        await eventually { await profiles.ensuredSessions.count == 1 }

        #expect(controller.currentSession == .ada)
        #expect(await profiles.ensuredSessions == [.ada])
        controller.stop()
    }

    @Test func switchingUsersEnsuresTheNewProfile() async {
        let (controller, _) = await signedIn()

        auth.emit(.signedIn(.grace))

        await eventually { await profiles.ensuredSessions == [.ada, .grace] }
        controller.stop()
    }

    @Test func profileFailureDoesNotAffectTheSession() async {
        await profiles.fail(with: AuthError.network)
        let (controller, _) = await signedIn()

        await eventually { await profiles.ensuredSessions.count == 1 }

        #expect(controller.state == .signedIn(.ada))
        controller.stop()
    }

    @Test func signOutRunsCleanupBeforeTheBackendSignOut() async {
        let (controller, observer) = await signedIn()

        await controller.signOut()

        #expect(await observer.events == [.init(uid: "uid-ada", reason: .userInitiated, signOutsBefore: 0)])
        #expect(await auth.signOutCount == 1)
        controller.stop()
    }

    @Test func signOutKeepsItsReasonWhenTheStreamCatchesUp() async {
        let (controller, _) = await signedIn()

        await controller.signOut()
        // The mock re-emits `.signedOut(nil)` after sign-out, as Firebase does.
        try? await Task.sleep(for: .milliseconds(50))

        #expect(controller.state == .signedOut(.userInitiated))
        controller.stop()
    }

    @Test func backendDroppingTheSessionIsReportedAsExpired() async {
        let (controller, observer) = await signedIn()

        auth.emit(.signedOut(nil))

        await eventually { controller.state == .signedOut(.sessionExpired) }
        #expect(await observer.events.map(\.reason) == [.sessionExpired])
        controller.stop()
    }

    @Test func unrecoverableErrorLogsOutAndCleansUp() async {
        let (controller, observer) = await signedIn()

        let action = await controller.handle(.userTokenExpired)

        #expect(action == .logout)
        #expect(controller.state == .signedOut(.sessionExpired))
        #expect(await observer.events.map(\.reason) == [.sessionExpired])
        #expect(await auth.signOutCount == 1)
        controller.stop()
    }

    @Test func sensitiveActionNeedingRecentLoginAsksToReauthenticate() async {
        let (controller, _) = await signedIn()

        let action = await controller.handle(.requiresRecentLogin, isSensitiveAction: true)

        #expect(action == .reauthenticate)
        #expect(controller.state == .signedOut(.reauthenticationRequired))
        controller.stop()
    }

    @Test func transientErrorKeepsTheSession() async {
        let (controller, observer) = await signedIn()

        let action = await controller.handle(.network)

        #expect(action == .retry)
        #expect(controller.state == .signedIn(.ada))
        #expect(await observer.events.isEmpty)
        controller.stop()
    }

    @Test func validateSessionLogsOutWhenTokenRefreshFails() async {
        await auth.failToken(with: .userDisabled)
        let (controller, _) = await signedIn()

        await controller.validateSession()

        #expect(await auth.tokenRequests == [false])
        #expect(controller.state == .signedOut(.sessionExpired))
        controller.stop()
    }

    @Test func validateSessionIsANoOpWhenSignedOut() async {
        let (controller, _) = makeController()
        auth.emit(.signedOut(nil))
        await eventually { controller.state == .signedOut(nil) }

        await controller.validateSession()

        #expect(await auth.tokenRequests.isEmpty)
        controller.stop()
    }
}
