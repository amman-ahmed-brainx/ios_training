---
diff_hash: 5f4b3b4be2d8612ac96f4998c28b844a08fdc9e05edf0e8cd10632d292cb153c
reviewed_at: 2026-11-03T13:22:15Z

## Summary

Phase 2: a complete email/password authentication feature layered on the Phase 1
scaffold. Adds a backend-agnostic `AuthService`/`UserProfileStore` protocol pair
with three implementations (`FirebaseAuthService`, `UnconfiguredAuthService`,
debug-only `FakeAuthService`), a `@MainActor @Observable SessionController` driven
by an `AsyncStream<SessionState>` with a `SessionExpiryPolicy` for
retry/reauthenticate/logout decisions, and a `SessionLifecycleObserver` hook
(registered but not yet wired to any concrete cleanup). `RootView` becomes a real
session gate (splash → auth flow → signed-in placeholder), with `LoginView`,
`SignUpView`, and `ForgotPasswordView` plus view models, backed by shared
`FormField`/`MessageBanner` design-system components and `Validators`/
`InlineValidation` for client-side validation. Test coverage is substantial: unit
tests for validators, session policy, session controller ordering, view models,
and a retain-cycle check, plus UI tests against the fake backend including an
accessibility audit.

No force unwraps/force casts/`try!`/reachable `fatalError` were found in the new
auth code, no secrets or PII are logged, weak-self capture is used correctly in
long-lived closures/Tasks, the email validator regex is linear (not ReDoS-prone),
and `SessionController`'s state-then-cleanup ordering matches its tests. No new
SPM dependencies, signing, or deployment-target changes ride along in
`project.pbxproj`.

## Findings

### Medium (1)
- **TaskManager/Features/Auth/ForgotPasswordViewModel.swift:45** — On failure, `status = .failed(error.localizedDescription)` surfaces whatever `AuthError` the backend throws directly to the user. Firebase's `userNotFound` maps to `AuthError.wrongCredentials` ("Incorrect email or password."), which reads as confusing/incorrect on a screen with no password field, and differs from the neutral success message the happy path shows — creating an account-enumeration side channel if the Firebase project doesn't otherwise suppress that distinction. *(security/correctness)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: Verified in AuthError.swift that `.wrongCredentials` has a password-specific message, and ForgotPasswordViewModel.swift has no mapping from `.userNotFound`-driven errors to a neutral reset-request message before display. Fix: on failure, show a generic message (e.g. always render the same "If an account exists for that email, we've sent a reset link" regardless of outcome) instead of the raw `AuthError` description, for both the enumeration risk and the password-screen mismatch.

### Low (4)
- **TaskManagerTests/Auth/SessionControllerTests.swift:39** — `signOutKeepsItsReasonWhenTheStreamCatchesUp` uses a fixed `Task.sleep(for: .milliseconds(50))` instead of the project's own `eventually` polling helper (TaskManagerTests/Support/Eventually.swift), so it can flake under a loaded CI runner instead of deterministically waiting for the mock stream to be processed. *(test-coverage)*
  - status: skipped
  - reason: The sleep cannot cause a false failure: the asserted .signedOut(.userInitiated) state is already set before it, so the sleep only gives the mock stream time to deliver its trailing .signedOut(nil). There is no observable event to poll for 'an ignored value was processed' (the controller deliberately does nothing visible), so `eventually` has no condition to wait on, and adding a test-only hook to SessionController would put test scaffolding in production code.
  - dev_reasoning: The sleep cannot cause a false failure: the asserted .signedOut(.userInitiated) state is already set before it, so the sleep only gives the mock stream time to deliver its trailing .signedOut(nil). There is no observable event to poll for 'an ignored value was processed' (the controller deliberately does nothing visible), so `eventually` has no condition to wait on, and adding a test-only hook to SessionController would put test scaffolding in production code.
  - ai_reasoning: Confirmed the project already has an `eventually` helper used elsewhere in the same test target; this test should use it instead of a fixed sleep for determinism.
- **TaskManagerTests/Auth/AuthLeakTests.swift:1** — Despite the name, this file checks retain cycles/memory leaks, not that secrets or tokens never reach logs — no test anywhere in the diff asserts logged output never contains a password/token/OTP. The name could mislead a future reviewer into believing that coverage exists. *(consistency)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: Read the full file; all assertions are weak-reference/deinit checks. Fix: rename to something like `AuthRetainCycleTests`, or add an actual log-content assertion if "leak" was meant to include secret leakage.
- **TaskManager/Core/Auth/SessionLifecycleObserver.swift:1** — The observer protocol and `SessionController.register(_:)` exist and are exercised only by tests; no production code registers an observer yet, so sign-out currently performs no actual remote/local per-user cleanup. `docs/ARCHITECTURE.md` documents this as deferred, so this is informational rather than a defect in this diff. *(maintainability)*
  - status: skipped
  - reason: Deliberate seam, documented in docs/ARCHITECTURE.md (Authentication and session): the SwiftData cache wipe (Phase 3), SyncEngine stop (Phase 5) and FCM token removal (Phase 7) register as observers when they land. The reviewer also marks it informational with no fix required for this phase.
  - dev_reasoning: Deliberate seam, documented in docs/ARCHITECTURE.md (Authentication and session): the SwiftData cache wipe (Phase 3), SyncEngine stop (Phase 5) and FCM token removal (Phase 7) register as observers when they land. The reviewer also marks it informational with no fix required for this phase.
  - ai_reasoning: Confirmed via grep that no concrete `SessionLifecycleObserver` conformance exists yet outside tests. No fix required for this phase; tracked here so it isn't lost before the feature that needs it lands.
- **TaskManager/DesignSystem/FormField.swift:54** — `.accessibilityIdentifier(identifier ?? "")` sets an explicit empty string instead of omitting the modifier when no identifier is given, which could make multiple identifier-less fields collide under UI-test element queries. *(maintainability)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: Fix: only apply `.accessibilityIdentifier` when `identifier` is non-nil, e.g. via a conditional modifier or `ViewModifier` branch, so unset fields don't all share the same empty identifier.

## Reviewed files
- TaskManager.xcodeproj/project.pbxproj (skimmed — new file references/groups/build-phase entries only; no new dependencies, signing, or deployment-target changes)
- TaskManager/App/AppEnvironment.swift (reviewed)
- TaskManager/App/Fakes/FakeAuthService.swift (reviewed)
- TaskManager/App/RootView.swift (reviewed)
- TaskManager/App/SignedInPlaceholderView.swift (reviewed)
- TaskManager/App/SplashView.swift (reviewed)
- TaskManager/Core/Auth/AuthError.swift (reviewed)
- TaskManager/Core/Auth/AuthService.swift (reviewed)
- TaskManager/Core/Auth/FirebaseAuthService.swift (reviewed)
- TaskManager/Core/Auth/SessionController.swift (reviewed)
- TaskManager/Core/Auth/SessionExpiryPolicy.swift (reviewed)
- TaskManager/Core/Auth/SessionLifecycleObserver.swift (reviewed)
- TaskManager/Core/Auth/UnconfiguredAuthService.swift (reviewed)
- TaskManager/Core/Auth/UserProfileStore.swift (reviewed)
- TaskManager/Core/Remote/FirestoreUserProfileStore.swift (reviewed)
- TaskManager/Core/Utilities/InlineValidation.swift (reviewed)
- TaskManager/Core/Utilities/Validators.swift (reviewed)
- TaskManager/DesignSystem/DesignSystemCatalog.swift (reviewed)
- TaskManager/DesignSystem/FormField.swift (reviewed)
- TaskManager/DesignSystem/MessageBanner.swift (reviewed)
- TaskManager/DesignSystem/Tokens.swift (reviewed)
- TaskManager/Features/Auth/AuthFlowView.swift (reviewed)
- TaskManager/Features/Auth/AuthHeader.swift (reviewed)
- TaskManager/Features/Auth/ForgotPasswordView.swift (reviewed)
- TaskManager/Features/Auth/ForgotPasswordViewModel.swift (reviewed)
- TaskManager/Features/Auth/LoginView.swift (reviewed)
- TaskManager/Features/Auth/LoginViewModel.swift (reviewed)
- TaskManager/Features/Auth/SignUpView.swift (reviewed)
- TaskManager/Features/Auth/SignUpViewModel.swift (reviewed)
- TaskManager/Resources/Assets.xcassets/SecondaryText.colorset/Contents.json (skimmed — color values only)
- TaskManager/Resources/Localizable.xcstrings (skimmed — spot-checked new strings)
- TaskManagerTests/App/AppEnvironmentTests.swift (reviewed)
- TaskManagerTests/Auth/AuthLeakTests.swift (reviewed)
- TaskManagerTests/Auth/AuthViewModelTests.swift (reviewed)
- TaskManagerTests/Auth/SessionControllerTests.swift (reviewed)
- TaskManagerTests/Auth/SessionExpiryPolicyTests.swift (reviewed)
- TaskManagerTests/Auth/ValidatorsTests.swift (reviewed)
- TaskManagerTests/Mocks/MockAuthService.swift (reviewed)
- TaskManagerTests/Support/Eventually.swift (reviewed)
- TaskManagerUITests/AuthFlowUITests.swift (reviewed)
- TaskManagerUITests/LaunchUITests.swift (deleted — replaced by AuthFlowUITests.swift, reasonable 1:1 replacement)
- docs/ARCHITECTURE.md (reviewed)
- .code-reviews/brainx-review.md (deleted — prior Phase 1 review archived/removed as part of this change set)
