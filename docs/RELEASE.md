# Release

## Signing and versioning

- Automatic signing; teams per configuration in `project.yml`.
- `MARKETING_VERSION` (user-facing, e.g. 1.0.0) and `CURRENT_PROJECT_VERSION` (build number) in
  `project.yml`. The `beta` lane bumps the build number from TestFlight's latest.

## Archive and upload

```bash
export ASC_KEY_ID=…  ASC_ISSUER_ID=…  ASC_KEY_PATH=/secure/path/AuthKey_XXXX.p8
fastlane test     # regenerate, unit + UI tests with coverage
fastlane beta     # bump build, archive Release, upload to TestFlight
```

Credentials only come from the environment; `.p8` files are gitignored. Manual alternative:
Product → Archive → Distribute App → App Store Connect → Upload.

## TestFlight

- **Internal testing:** up to 100 team members, available as soon as processing finishes.
- **External testing:** up to 10,000 testers by email or public link; the first build of a version
  needs Beta App Review (provide the demo account and notes below).

## App Store Connect checklist

- App Privacy answers matching `PrivacyInfo.xcprivacy`: email, name, user content (tasks, files),
  device ID (push token); all linked to the user, for app functionality, no tracking.
- Export compliance: `ITSAppUsesNonExemptEncryption = NO` (only HTTPS/standard encryption).
- Screenshots: 6.9" and 6.5" iPhone, light mode, with sample tasks.
- Review notes: demo account email/password, how to see a shared task (invite the reviewer account),
  and that notifications are optional.
- Support URL, privacy policy URL, age rating, category (Productivity).
