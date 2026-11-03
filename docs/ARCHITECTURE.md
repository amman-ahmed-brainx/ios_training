# Architecture

This document grows phase by phase. Sections still to come (data flow, sync and conflict policy,
background uploads) are added when the corresponding phase lands.

## Toolchain (Phase 1)

| Tool | Version |
| --- | --- |
| Xcode | 27.2 (27B52) |
| Swift | 6.4.2, Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete` |
| Primary simulator | iPhone 18 Pro, iOS 27.2 |
| Fallback check | iPhone 15, iOS 17.2 (minimum deployment target) |
| XcodeGen | 2.46.0 |
| SwiftLint | 0.50.1 |
| Firebase iOS SDK | 13.1.1, pinned with `exactVersion` |
| Firebase CLI | 14.26.0 |
| Node | 24.18.0 |

## Layers

```
Features (SwiftUI views + @MainActor @Observable view models)
    │  depend only on protocols
Core (Auth, Persistence, Remote, Sync, Uploads, Notifications, Media, Utilities)
    │  Firebase types appear only in Core/Auth, Core/Remote and Core/Uploads
DesignSystem (tokens, button styles, reusable components)
```

`AppEnvironment` (App/) is the composition root. It is created once by `AppDelegate`, chooses a
mode, and builds every service for that mode:

| Mode | Selected by | Services |
| --- | --- | --- |
| `live` | normal launch | Firebase when `GoogleService-Info.plist` is bundled, otherwise local-only |
| `preview` | SwiftUI previews, unit-test host (`XCTestConfigurationFilePath`) | in-memory fakes |
| `uiTest` | `-uitest` launch argument | deterministic offline fakes, never a real backend |

## Authentication and session (Phase 2)

```
FirebaseAuthService ──AsyncStream<SessionState>──▶ SessionController (@MainActor) ──▶ RootView gate
   (state + ID-token listeners)                        │                              splash / auth flow / app
                                                        ├─ UserProfileStore.ensureProfile (users/{uid})
                                                        ├─ SessionExpiryPolicy (error → retry / reauthenticate / logout)
                                                        └─ SessionLifecycleObservers (cleanup on session end)
```

- `AuthService` is the only auth API the app sees. It exposes an `AsyncStream<SessionState>` (fed by
  Firebase's auth-state **and** ID-token listeners, so token refreshes are observable),
  `currentIDToken(forceRefresh:)` for the background uploader, and typed `AuthError`s.
- `SessionController` owns the session state. Launch starts at `.unknown` (splash) until the first
  stream value resolves the persisted session.
- **Auto-logout.** Firebase signs the user out itself when a refresh fails with
  `userTokenExpired`/`userDisabled`; the controller sees a sign-out it didn't ask for and reports it
  as `.sessionExpired`. Errors surfaced by our own calls go through `SessionExpiryPolicy`, and the
  controller validates the token every time the app becomes active.
- **Cleanup order.** On user sign-out, `SessionLifecycleObserver`s run *before* the backend sign-out,
  so remote cleanup (removing this device's FCM token) still has credentials. On expiry only local
  cleanup is possible. Later phases register the sync engine, local cache and push registrar here.
- **Profile.** `users/{uid}` is written with `setData(merge:)` after every new sign-in, seeding
  `createdAt` and `fcmTokens` only when the document doesn't exist. It is not awaited inline because
  an offline Firestore write only completes on reconnect.
- **Fakes.** `FakeAuthService` (Debug only) backs previews and `-uitest`; the UI test signs in as
  `test@example.com`. `UnconfiguredAuthService` keeps live mode usable without the Firebase plist.

## Decisions and trade-offs

- **The project lives at the repository root** (`ios_training/`), not in a nested `TaskManager/`
  folder: the repository exists only for this app.
- **`AppDelegate` owns `AppEnvironment`.** UIKit callbacks (APNs token, background `URLSession`
  events) can arrive before any SwiftUI scene exists, so the graph must live on the delegate.
  The `App` struct reads it through `@UIApplicationDelegateAdaptor`.
- **`GoogleService-Info.plist` is optional at build time.** It is gitignored and copied into the
  bundle by a build phase only when present. Without it `live` mode runs on local data, and
  every test uses fakes, so the project builds and tests green on a fresh clone.
- **`AppClock` instead of `Clock`.** The brief asks for a `Clock` protocol; that name would shadow
  the standard library's `Clock`, so ours is `AppClock`.
- **Colours come from the asset catalog** with light and dark variants, accessed through generated
  asset symbols (`Color(.statusDone)`) wrapped in `Palette`, so a typo is a compile error.
- **`ENABLE_USER_SCRIPT_SANDBOXING = NO`** so the SwiftLint and Firebase-config build phases can read
  the source tree. Both scripts only read from `SRCROOT` and write into the build products.
- **Release treats warnings as errors** (`SWIFT_TREAT_WARNINGS_AS_ERRORS`); Debug does not, so a
  warning never blocks a local debugging session but always blocks a release.
- **Force unwraps are enforced twice.** SwiftLint (`force_unwrapping`, `force_try`, `force_cast` as
  errors) runs in a build phase when installed; `scripts/check_no_force_unwraps.sh` is a
  dependency-free fallback that `scripts/verify.sh` always runs.
- **`-uitest` is honoured only in Debug builds** (`#if DEBUG`), so fake auth and backends can never
  ship in Release or TestFlight. UI tests run the Debug configuration.
- **Analytics and Crashlytics collection is off** (`FIREBASE_ANALYTICS_COLLECTION_ENABLED`,
  `FirebaseCrashlyticsCollectionEnabled` = `false`) until their optional wrappers and the privacy
  manifest land, so adding `GoogleService-Info.plist` never starts collection by surprise.
- **No photo-library usage string.** `PhotosPicker` runs out of process and needs no permission.
- **Team ID is blank** in `project.yml` for now. Simulator builds and tests do not need it; set
  `DEVELOPMENT_TEAM` before building for a device or TestFlight.
