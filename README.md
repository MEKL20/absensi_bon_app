# Absensi & Bon

Installed Flutter mobile app for an owner and employees, backed by Cloudflare Workers, D1 and private R2.

- **Owner:** employee account management, current work sessions, private attendance photos, bon approval/rejection, recorded disbursements and repayments.
- **Employee:** selfie check-in/check-out, attendance history, photo-free bon amount/note requests, request status and personal debt summary.
- **Bon never requires a photo.** Approval does not create debt; recorded disbursement does. The app records money events and does not transfer funds.

## Run the mobile app

Use Flutter 3.32.8 / Dart 3.8.1 or a compatible newer Flutter SDK with Dart 3.8+. On first launch the app opens the workspace gate: the owner creates or joins a customer-owned Cloudflare workspace, and employees scan the workspace QR. A build-time endpoint is only an optional pre-pairing hint:

```powershell
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter run --dart-define=API_BASE_URL=https://your-api.example.com
```

The endpoint is build-time configuration, not a secret. Without a paired workspace the app explains onboarding and disables sign-in; no production account, fake login, or sample employee data is included. Normal HTTPS certificate validation remains enabled. See [owner onboarding](<docs/ONBOARDING.md>) for the Cloudflare/GitHub steps each business completes in their own account.

On this Windows environment, an isolated SDK is available under the ignored `.tools/flutter` directory. Package resolution succeeded, but plugin symlink creation requires Windows Developer Mode; system settings were not changed. `flutter analyze --no-pub` and `flutter test --no-pub --concurrency=1` run with the resolved packages. Android SDK/iOS build tooling and real-device qualification are still required for release.

## GitHub Actions builds

The [automatic mobile workflow](<.github/workflows/mobile-ci.yml>) builds Android debug APK and iOS simulator artifacts on pull requests and pushes to main. The [manual signed workflow](<.github/workflows/mobile-release.yml>) builds Android APK/AAB and iOS IPA using repository signing secrets. See the [CI/CD setup guide](<docs/CI_CD.md>) for variables, signing credentials, artifact downloads, and platform requirements.

## Backend setup and migration

Follow the [backend guide](<cloudflare/README.md>) for local tests, schema migration, private bucket bindings and owner provisioning. Follow the [migration guide](<docs/MIGRATION.md>) before switching existing users/data. No live Cloudflare resources were provisioned or deployed. No historical employee or financial data was imported.

Cloudflare free allowances are a usage target, not a zero-cost guarantee. Strong password hashing must be measured against the Workers CPU allowance before production. R2 bills overages; attendance photo retention is disabled until explicitly configured.

## Documentation and previews

- [Documentation guide](<docs/README.md>)
- [Product Requirements Document](<docs/PRD.md>)
- [Technical Specification Document](<docs/TSD.md>)
- [Software Design Document](<docs/SDD.md>)
- [Owner onboarding and workspace pairing](<docs/ONBOARDING.md>)
- [Owner overview preview](<docs/previews/owner-home.png>) and [employee bon preview](<docs/previews/employee-bon.png>)

Previews are actual Flutter widget-renderer captures using empty-state test fixtures; they are not device screenshots or live business records.
