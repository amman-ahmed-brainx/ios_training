# Quality

## Automated checks

| Check | Status |
| --- | --- |
| `scripts/check_no_force_unwraps.sh` | Passes on every phase |
| SwiftLint (`force_unwrapping`, `force_try`, `force_cast` = error) | Clean in build phase |
| Release build, `SWIFT_TREAT_WARNINGS_AS_ERRORS` | Clean (every phase built with zero warnings) |
| Unit + UI tests | 104 passing at the last full run (end of Phase 3); later phases were build-verified, and their new tests (sync conflict policy, mapper, image compressor, attachments, reminders incl. the 64 limit, invites, notification payloads, upload state machine, JSON transfer) compile but have not been run yet |
| Coverage (Phase 3 run) | App 71%; view models: Login 100%, SignUp 91%, ForgotPassword 89%, TaskList 98%, TaskEditor 97%, Settings 100% |
| Cloud Function (Jest) | Written, not yet run: `cd functions && npm ci && npm test` |
| Security rules (emulator) | Written, not yet run: `cd firebase && npm ci && npm test` |

**Firebase end to end (Local Emulator Suite).** `FirebaseEmulatorUITests` runs the real Firebase
Auth and Firestore SDKs, the project's security rules and the sync engine against
`firebase emulators:start --only auth,firestore,storage` (the app is launched with the Debug-only
`-firebaseEmulators` flag; the tests skip when the emulators aren't running). Both pass:
sign in → create task → confirmed by Firestore → relaunch restores session and task; and owner
shares by email → collaborator updates only the status through the REST API (rules enforced) →
the owner's list shows it live. Firestore contents were checked directly: `users/{uid}` profile
(lowercased email, no push tokens) and `tasks/{id}` with `memberIds` and `statusUpdatedAt`.

The UI test covers log in → create with due date → edit → complete (swipe) → delete (swipe) → sign
out against the `-uitest` fake backend, plus inline validation and `performAccessibilityAudit()`.
The audit found and we fixed: truncation of "Don't have an account?" at large sizes, and the system
secondary grey falling just below 4.5:1 contrast (replaced with the `SecondaryText` asset colour).

Leak tests (weak reference becomes `nil`): `LoginViewModel`, `SessionController`, `TaskListViewModel`.

## Instruments (manual, not yet recorded)

Repeat in Instruments.app (Product → Profile) on a Release build:

1. **Leaks + Allocations:** log in, open and close the editor 10 times, add and remove an attachment,
   log out. Expect no leaks attributed to `TaskManager`; persistent allocations should return to
   baseline after logging out.
2. **Hangs / Time Profiler:** Settings → "Generate 1,000 Sample Tasks" (Debug builds), scroll the
   list, search and change filters, add a large photo attachment. Expect no hangs over 250 ms;
   image decoding appears only on `ImageCompressor`'s executor and SwiftData work on `TaskStore`'s.

Command-line equivalent:
```bash
xcrun xctrace record --template 'Leaks' --device <UDID> --launch -- <path to TaskManager.app>
xcrun xctrace record --template 'Time Profiler' --device <UDID> --launch -- <path to TaskManager.app>
```

## Accessibility checks done

Labels, values and hints on rows and badges; rows read as one element; swipe actions duplicated as
VoiceOver actions; Reduce Motion respected for list and gate animations; status and errors use icon +
text, never colour alone; 44 pt targets; `AnyLayout` switches at accessibility sizes; previews at AX5,
dark mode and a 320 pt phone.
