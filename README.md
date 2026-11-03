# TaskManager

A production-quality iOS task manager in SwiftUI: Firebase auth, real-time Firestore sync,
offline-first SwiftData cache, attachments, collaboration, reminders and push notifications.

This README is completed in the final phase. For now:

## Requirements

- Xcode 27.2 or newer, iOS 17.0+ (iPhone only)
- `brew install xcodegen swiftlint`

## Build and test

```bash
xcodegen generate
scripts/verify.sh
```

`scripts/verify.sh` regenerates the project, runs the force-unwrap check and SwiftLint, builds
Release (warnings are errors), and runs all tests with coverage.

The app builds and runs without `GoogleService-Info.plist`; Firebase setup is documented in
`docs/SETUP.md` (added in a later phase).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for structure and decisions.
