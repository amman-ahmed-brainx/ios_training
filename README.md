# TaskManager

A production-style iOS task manager in SwiftUI (iOS 17+, iPhone, Swift 6 with strict concurrency):
Firebase Auth, real-time Firestore sync over an offline-first SwiftData cache, attachments with
background uploads, collaboration, deadline reminders and FCM push.

## Features → requirements

| Brief | Where |
| --- | --- |
| 2.1 Auth, session gate, token refresh, auto-logout | `Core/Auth` (`AuthService`, `SessionController`, `SessionExpiryPolicy`), `Features/Auth` |
| 2.2 Task CRUD, search, filters, sort, swipe actions, states | `Features/Tasks`, `Core/Domain/TaskQuery.swift` |
| 2.3 Real-time Firestore + rules | `Core/Remote/FirestoreTaskRemote.swift`, `firebase/*.rules`, `firebase/tests` |
| 2.4 Offline-first sync, outbox, conflicts | `Core/Persistence/TaskStore.swift`, `Core/Sync` |
| 2.5 Attachments, compression, QuickLook | `Core/Media`, `Core/Uploads`, `Features/Attachments` |
| 2.6 Invites, reminders, FCM, Cloud Function, deep links | `Features/Collaboration`, `Core/Notifications`, `functions/`, `App/NotificationCoordinator.swift` |
| 2.7 Background: scene phases, BGTaskScheduler, background URLSession, JSON export/import | `App/BackgroundSync.swift`, `Core/Uploads/BackgroundUploadManager.swift`, `Features/Settings` |
| 2.8 Design system, Liquid Glass fallback, accessibility, en + de | `DesignSystem/`, `Resources/Localizable.xcstrings` |

## Architecture

```mermaid
flowchart LR
  subgraph UI[MainActor]
    V[SwiftUI views] --> VM[@Observable view models]
  end
  VM -->|protocols| R[TaskRepository]
  R --> S[TaskStore @ModelActor]
  S --> D[(SwiftData)]
  E[SyncEngine actor] -->|merge| S
  E -->|push outbox| F[(Firestore)]
  F -->|snapshot listener| E
  U[BackgroundUploadManager] --> ST[(Cloud Storage)]
  CF[Cloud Function] -->|FCM| Device
```

Details, concurrency model, conflict policy and trade-offs: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Xcode 27.2+ (Swift 6.4), iOS 17.0+ simulator or device
- `brew install xcodegen swiftlint`; Node 22 and the Firebase CLI for rules/functions

## Setup and running

1. `xcodegen generate`, open `TaskManager.xcodeproj`, run the `TaskManager` scheme.
   Without `GoogleService-Info.plist` the app runs but sign-in is unavailable; run with the
   `-uitest` launch argument (Debug) to use the built-in fake backend (`test@example.com` / `Password1`).
2. Firebase from zero (project, Auth, Firestore, Storage, rules, APNs key, Blaze, functions):
   [docs/SETUP.md](docs/SETUP.md).

## Tests

```bash
scripts/verify.sh                          # force-unwrap check, SwiftLint, Release build, all tests, coverage
(cd functions && npm ci && npm test)       # Cloud Function message builder (Jest)
(cd firebase && npm ci && npm test)        # security rules (Firestore emulator)
```

Results and Instruments notes: [docs/QUALITY.md](docs/QUALITY.md). Release: [docs/RELEASE.md](docs/RELEASE.md).
Demo script: [docs/DEMO.md](docs/DEMO.md).

## Known limitations and follow-ups

- **Profiles are readable by any signed-in user** so invite-by-email can query by email. They hold
  only email and display name; push tokens are in owner-only `userTokens/{uid}`. A callable Cloud
  Function for lookups would close this.
- Signing out while offline discards changes that haven't synced (Settings warns about this).
- A write the backend rejects (for example after access is revoked) stays parked in the outbox
  with its reason instead of being retried or discarded.
- Analytics and Crashlytics are linked but their collection is disabled until thin wrappers exist.
- Not yet covered by unit tests: `TaskStore.applyRemote`/outbox branches, `SyncEngine`'s push loop,
  the Firebase adapters (verified on device) and the Cloud Function trigger (needs the emulator).
- Phases 4–10 were verified by building only; the full suite and Instruments runs are listed as
  manual checks in `docs/QUALITY.md`.
