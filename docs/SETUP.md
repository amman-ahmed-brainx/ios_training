# Setup from zero

1. **Firebase project.** console.firebase.google.com → Add project.
2. **iOS app.** Add an Apple app with bundle ID `com.brainxtech.taskmanager`. Download
   `GoogleService-Info.plist` into `TaskManager/Resources/` (it is gitignored; a build phase copies it).
3. **Auth.** Authentication → Sign-in method → enable Email/Password.
4. **Firestore and Storage.** Create a Firestore database and a Storage bucket (production mode).
5. **Rules.**
   ```bash
   firebase login
   firebase use --add            # pick the project
   firebase deploy --only firestore:rules,firestore:indexes,storage
   ```
6. **Push.** In the Apple Developer portal create an APNs auth key (`.p8`); in Firebase → Project
   settings → Cloud Messaging upload it with its Key ID and your Team ID. In Xcode the target already
   has the Push Notifications entitlement (`aps-environment`) and background modes.
7. **Cloud Functions** (needs the Blaze plan):
   ```bash
   (cd functions && npm ci && npm run build)
   firebase deploy --only functions
   ```
   Without Blaze, test pushes with `payloads/` (`xcrun simctl push …`) or the console's "Send test
   message" — see `payloads/README.md`.
8. **Signing.** Team IDs are set per configuration in `project.yml` (`DEVELOPMENT_TEAM`).
   Run `xcodegen generate` after changing it.
9. **Push on a device.** Run on an iPhone, sign in, allow notifications. Sign in as a second user
   on another device, share a task with them (Share → email), change its status on one device and
   the other receives "<name> updated <task>". Tapping it opens the task.
