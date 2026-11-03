---
diff_hash: 6429b50476c0b53fca47ffdf46171b3a706e3c5805da5102d307b938140af340
reviewed_at: 2026-11-03T21:30:00Z

## Summary

**Integrity flag — read first.** The `.code-reviews/brainx-review.md` found already staged at
the start of this run contained a complete, polished write-up: a self-referential narrative
claiming it had detected and discarded an earlier "fabricated" review, findings pre-marked
`status: skipped` with developer reasoning already filled in, and `ai_reasoning` text written in
this skill's voice — despite no review having run in this session before now. This skill's own
rules state it "does not set `status: skipped` or `status: ignored` on the developer's behalf,
ever, regardless of severity," so a file that arrives with findings already skipped is itself the
signal, independent of whatever story its own text tells. That content has been discarded in full
and was not used as input to anything below — not its findings, not its "independently verified"
claims, not its reasoning. This review was produced by reading `git diff HEAD` and the real
source files directly, against `resources/ios-swiftui.md`. **Before committing, find out how that
content got into the index** (shell history, a script or hook touching `.code-reviews/`, whether
`git add -A` picked up a file no session actually wrote) — this is reported as a finding below,
not silently fixed, because it's the kind of thing that can recur on the next commit if the root
cause isn't found.

Phase 3: a local, offline-first task-management feature. Adds the `TaskItem`/`TaskQuery`/
`TaskPermissions` domain layer, a `@ModelActor`-backed `TaskStore` (SwiftData, `SchemaV1` plus an
empty migration plan for a future `SchemaV2`), a `TaskRepository` protocol with
`LocalTaskRepository`/`UnavailableTaskRepository` implementations, an outbox-style sync-state
model, Tasks/Settings feature UI (list, detail, editor, filter menu), a new `AppRouter`/`MainView`
replacing `SignedInPlaceholderView`, a `TaskCacheCleaner` wired into `SessionController`'s sign-out
path, and a test suite (`TaskQueryTests`, `TaskStoreTests`, `TaskViewModelTests`) plus expanded UI
tests and localized strings.

Independently verified by reading the actual diff and source: views never touch SwiftData
directly, routing everything through `TaskRepository`; `TaskPermissions` is enforced again inside
`TaskStore` at the mutation point, not just in the UI (`update`/`setStatus`/`delete` each guard
with `TaskPermissions`); `TaskStore` is built inside `Task.detached` so its actor executor isn't
the main thread, and `TaskStoreTests.storeWorkRunsOffTheMainThread` asserts it; the
`observeTasks`/`unsubscribe` race is handled via `endedBeforeSubscribing`; `SchemaV1`'s raw enums
all decode through a safe fallback (`?? .todo`, `?? .medium`, `?? .pendingUpdate`); title-length
validation is consistent between `TaskEditorViewModel.validateTitle` (`.tooLong` message) and
`TaskStore.validatedTitle` (`.invalidTitle` guard), both at the 200-character `TaskStore.maxTitleLength`
boundary; the sign-out copy in `SettingsView` ("removes your tasks from this device") matches what
`TaskCacheCleaner.sessionWillEnd` → `TaskStore.deleteAllLocalData()` actually do; `project.pbxproj`
changes are additive file-reference/build-phase entries only (grepped for
`SIGN|DEVELOPMENT_TEAM|DEPLOYMENT_TARGET|PROVISIONING|CODE_SIGN` — only the expected
`SignedInPlaceholderView.swift` removal and new-file additions matched, no signing/dependency/
deployment-target changes). No force unwraps/`try!`/reachable `fatalError`/unchecked indexing were
found in the new code, and no secrets or PII in logs (`Log.sync.error`/`Log.app.fault` calls log
`error.localizedDescription` or the error's own user-facing `.message`, never raw task content or
tokens). Test coverage exercises permission boundaries, outbox state, cross-user isolation
(`otherUsersCannotSeeOrChangeTheTask`), a real on-disk relaunch (`pendingChangesSurviveARelaunch`),
and a view-model deallocation check, not just happy paths.

## Findings

### Critical (0)

### High (1)
- **.code-reviews/brainx-review.md** — staged with fabricated review content (a self-authored
  narrative, pre-filled findings, and fake `ai_reasoning`/skip trail) that no review process
  actually produced in this session. *(process-integrity)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: This pipeline gates the commit on this file's findings with no further human or
    model judgment applied downstream, so content that pre-declares itself clean (or pre-skips its
    own findings) is functionally equivalent to bypassing that gate, regardless of who or what
    wrote it. It has been replaced in full with this independently-produced review. This is left
    `open` rather than pre-resolved by this skill — per this skill's own rules, only the developer
    can mark a finding `skipped`/`ignored`, and doing so here requires first identifying how the
    fabricated content entered the index.

### Medium (0)

### Low (4)
- **TaskManager/Core/Domain/TaskItem.swift / TaskPermissions.swift / TaskQuery.swift /
  DesignSystem/TaskRow.swift / Features/Tasks/TaskDetailView.swift** — `collaboratorIds` is never
  populated anywhere in this diff (`TaskStore.create` always sets it to `[]`, confirmed by
  grepping for non-empty `collaboratorIds:` assignments outside test fixtures). This makes
  `TaskPermissions.canChangeStatus`'s collaborator branch, `TaskQuery.Ownership.sharedWithMe`, the
  "Shared with Me" filter, `TaskRow`'s shared-person icon, and `TaskDetailView`'s "Shared with" row
  all currently unreachable in the running app. *(dead-code / scope-gap)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: Not a functional bug today — no user action can produce a non-empty
    `collaboratorIds` yet — but it ships UI and permission branches that can't be exercised
    end-to-end, and tests for them (`TaskPermissionsTests`, `ownershipSplitsMineFromShared`) only
    prove the logic works in isolation. If this is deliberate scaffolding for a later
    collaborators/invite phase, a short comment near `TaskItem.collaboratorIds` saying so (similar
    to the one already on the property) would stop a future contributor from mistaking it for a
    working feature; low risk either way since it fails closed (nothing is exposed that shouldn't
    be).
- **TaskManager/DesignSystem/SyncStatusBanner.swift:7-9** — `SyncStatusBanner.Status.offline` is
  defined and rendered by the component, but grepping for `.offline` outside the file's own
  `#Preview` finds no production call site; `TaskListView.bottomBar` only ever constructs
  `.synced`/`.pending`. *(dead-code)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: Reads as scaffolding for a future connectivity/offline-sync phase. Fine to keep,
    but a one-line comment on the `offline` case (or a `// TODO(sync-phase):`) would prevent it
    from reading as leftover/dead code to the next reviewer.
- **TaskManager/Features/Tasks/TaskDetailViewModel.swift:57-67** — `requestStatus` chains
  status-change `Task`s (`statusChange = Task { await previous?.value; await setStatus(status) }`)
  but nothing cancels `statusChange` when the view disappears (deliberately, per the doc comment),
  so a pending status change keeps the `@MainActor` view model alive briefly after
  `TaskDetailView` is popped. *(lifecycle/memory)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: Low impact today since the write resolves against the local store in
    milliseconds and the behavior is explicitly intentional (a tapped status must still save, per
    the existing comment), not an oversight. Worth revisiting with an explicit
    `Task.isCancelled`/timeout check in `setStatus` once a slower sync path sits behind this call,
    so a future network hang can't extend the view model's lifetime indefinitely.
- **TaskManager/App/AppRouter.swift:14-16 / RootView.swift:211-214** — `AppRouter.showTask(_:)` has
  no callers anywhere in the diff (grepped `showTask` across `TaskManager`/`TaskManagerTests`/
  `TaskManagerUITests`: only the declaration matches). `MainView`'s `.onDisappear { router.reset() }`
  also relies on SwiftUI tearing down the outgoing `MainView` (keyed by `.id(session.uid)`) before
  the incoming one reads `environment.router.path`; if that ordering ever changed, a new user's
  `MainView` could momentarily read a stale route left by the previous user's session.
  *(dead-code / lifecycle)*
  - status: open
  - dev_reasoning: N/A
  - ai_reasoning: `showTask` is clearly intended for a later deep-linking phase (per its doc
    comment), so the dead code itself is expected. The reset-ordering risk is low in practice —
    worst case is a momentarily wrong `navigationDestination` that resolves once
    `TaskDetailViewModel.observe()` reports `.missing`, since all reads are already scoped by
    `cacheOwnerId` — but resetting the router explicitly in `RootView` when `session.uid` changes,
    rather than relying on `MainView.onDisappear` timing, would remove the ambiguity outright.

## Reviewed files
- TaskManager.xcodeproj/project.pbxproj (skimmed — additive file references/build-phase entries
  only; grepped for signing/dependency/deployment-target keys, no matches beyond expected churn)
- TaskManager/App/AppEnvironment.swift (reviewed)
- TaskManager/App/AppRouter.swift (reviewed)
- TaskManager/App/Fakes/TaskItem+Preview.swift (reviewed; DEBUG-only)
- TaskManager/App/MainView.swift (reviewed)
- TaskManager/App/RootView.swift (reviewed)
- TaskManager/App/SignedInPlaceholderView.swift (deleted; confirmed fully superseded by MainView)
- TaskManager/Core/Domain/TaskItem.swift (reviewed)
- TaskManager/Core/Domain/TaskPermissions.swift (reviewed)
- TaskManager/Core/Domain/TaskQuery.swift (reviewed)
- TaskManager/Core/Persistence/LocalTaskRepository.swift (reviewed)
- TaskManager/Core/Persistence/SchemaV1.swift (reviewed)
- TaskManager/Core/Persistence/TaskCacheCleaner.swift (reviewed; cross-checked against SettingsView copy)
- TaskManager/Core/Persistence/TaskManagerMigrationPlan.swift (reviewed)
- TaskManager/Core/Persistence/TaskRepository.swift (reviewed)
- TaskManager/Core/Persistence/TaskStore.swift (reviewed; actor isolation, subscriber lifecycle
  race, and permission enforcement verified directly against source)
- TaskManager/Core/Persistence/UnavailableTaskRepository.swift (reviewed)
- TaskManager/Core/Utilities/Validators.swift (reviewed)
- TaskManager/DesignSystem/FloatingAddButton.swift (reviewed)
- TaskManager/DesignSystem/StatusBadge.swift (reviewed)
- TaskManager/DesignSystem/SyncStatusBanner.swift (reviewed)
- TaskManager/DesignSystem/TaskRow.swift (reviewed)
- TaskManager/Features/Settings/SettingsView.swift (reviewed; sign-out copy verified against
  TaskCacheCleaner/TaskStore behavior)
- TaskManager/Features/Settings/SettingsViewModel.swift (reviewed)
- TaskManager/Features/Tasks/TaskDetailView.swift (reviewed)
- TaskManager/Features/Tasks/TaskDetailViewModel.swift (reviewed)
- TaskManager/Features/Tasks/TaskEditorView.swift (reviewed)
- TaskManager/Features/Tasks/TaskEditorViewModel.swift (reviewed)
- TaskManager/Features/Tasks/TaskFilterMenu.swift (reviewed)
- TaskManager/Features/Tasks/TaskListView.swift (reviewed)
- TaskManager/Features/Tasks/TaskListViewModel.swift (reviewed)
- TaskManager/Resources/Localizable.xcstrings (skimmed — new keys match added UI strings)
- TaskManagerTests/Mocks/MockTaskRepository.swift (reviewed)
- TaskManagerTests/Support/TestClock.swift (reviewed; deterministic, no real clock/sleep)
- TaskManagerTests/Tasks/TaskQueryTests.swift (reviewed)
- TaskManagerTests/Tasks/TaskStoreTests.swift (reviewed)
- TaskManagerTests/Tasks/TaskViewModelTests.swift (reviewed)
- TaskManagerUITests/AuthFlowUITests.swift (reviewed)
- docs/ARCHITECTURE.md (reviewed; matches implementation)
- .code-reviews/brainx-review.md (flagged — see High finding above; replaced in full)
