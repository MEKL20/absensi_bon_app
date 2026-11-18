# GitHub Actions mobile builds

The [automatic workflow](<../.github/workflows/mobile-ci.yml>) validates Flutter and builds Android/iOS test artifacts on pull requests, pushes to main, and manual runs. The [signed workflow](<../.github/workflows/mobile-release.yml>) builds signed Android APK/AAB and iOS IPA artifacts on manual dispatch. Neither workflow publishes to Google Play, TestFlight, App Store, or Cloudflare.

## Automatic CI

1. Push the repository, including the workflows, to GitHub.
2. Open **Actions → Mobile CI**. A pull request or push to main triggers it automatically; **Run workflow** also works once the workflow is on the default branch.
3. The validation job installs Flutter 3.32.8, enforces the committed Dart lockfile, checks formatting, runs the analyzer and mobile tests, and tests the signing helper validation.
4. After validation, Android builds a debug APK on Ubuntu 24.04 with Java 17. iOS builds an unsigned debug simulator application on macOS 15 with Xcode 16.4 and CocoaPods 1.16.2.
5. Download artifacts from the workflow run summary. Test artifacts are retained seven days.

| Artifact | Use |
| --- | --- |
| android-debug-* | Install the APK on an Android phone for testing; debug signed, not a production upload. |
| ios-simulator-* | Extract Runner.app and install into an Xcode simulator on a Mac. Not installable on an iPhone. |

No signing secrets are needed. Set repository variable API_BASE_URL to the HTTPS Worker API endpoint to enable login in the builds. Without it, CI still builds but the app displays its existing unconfigured-service message. Fork pull requests do not receive signing secrets. No pull_request_target workflow is used. Tokens have contents:read only and checkout does not retain Git credentials.

## Signed build configuration

Under **Settings → Secrets and variables → Actions**, configure these repository variables:

| Variable | Required for | Value |
| --- | --- | --- |
| API_BASE_URL | All signed builds | HTTPS backend base URL, without credentials/query/fragment. This is public build configuration. |
| ANDROID_APPLICATION_ID | Android distribution identity | Your chosen application ID, such as com.yourbusiness.absensi. If omitted, the existing com.example.absensi_bon_app identifier remains; replace it before store registration. |
| IOS_TEAM_ID | Signed iOS | Ten-character Apple Developer team ID. |
| IOS_BUNDLE_ID | Signed iOS | Explicit app identifier registered with Apple, exactly matching the provisioning profile. |

Configure these secrets:

| Secret | Description |
| --- | --- |
| ANDROID_KEYSTORE_BASE64 | Base64 of your Android upload keystore, retaining its private key. |
| ANDROID_KEYSTORE_PASSWORD | Keystore password. |
| ANDROID_KEY_ALIAS | Key alias inside the keystore. |
| ANDROID_KEY_PASSWORD | Private key password. |
| IOS_CERTIFICATE_BASE64 | Base64 of an exported Apple signing certificate/private-key .p12. |
| IOS_CERTIFICATE_PASSWORD | Password for that .p12; an empty password is supported. |
| IOS_PROFILE_BASE64 | Base64 of the matching .mobileprovision profile. |

On PowerShell, create a base64 value from a local signing file and copy it directly into the corresponding GitHub secret; do not commit it:

PowerShell example:

~~~powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\secure\upload-keystore.jks')) | Set-Clipboard
~~~

Use the same operation for the .p12 and provisioning profile. Keep the Android upload key stable for future updates. Signed iOS distribution needs the appropriate Apple Developer membership, certificate, explicit App ID and provisioning profile. Store registration/submission are outside these workflows.

## Run signed builds

Open **Actions → Mobile signed builds → Run workflow** on a trusted branch. Choose android, ios or both. Select the iOS export method matching the uploaded profile:

| Method | Certificate/profile | Output use |
| --- | --- | --- |
| app-store-connect | Apple distribution + App Store profile | IPA for a later App Store Connect/TestFlight upload. |
| release-testing | Apple distribution + Ad Hoc profile with registered devices | Install on the registered iPhones using your chosen distribution mechanism. |
| debugging | Apple development + development profile with registered devices | Development IPA for registered devices. |

The workflow validates source before accessing signing material in platform jobs. Android decodes its keystore into runner temporary storage and builds release APK and AAB; Gradle requires all signing values and never substitutes the debug key for a release. iOS imports the certificate into a temporary keychain, validates team/bundle/expiration/export type and matching certificate, configures only the Runner Release target, then archives/exports the IPA. CocoaPods targets do not inherit the app provisioning profile. Temporary signing material is removed in always-run cleanup steps.

Signed artifacts are downloadable from the run summary for fourteen days. Restrict repository Actions/artifact access as appropriate. The workflows do not create a public GitHub Release. Use only trusted workflow branches when signing; repository secrets are available to authorized manual runs on those branches. Optionally add a protected GitHub Environment to signed jobs according to your release policy.

## Versioning and platform setup

The marketing version comes from the [package manifest](<../pubspec.yaml>). Both workflows use github.run_number as build number. Increase the version before store releases; if migrating an existing published app, choose build numbers above the published value. Re-running the same workflow run retains its number; create a new run for a new upload. CI and signed workflows have independent counters; only signed artifacts are intended for production upload.

Android signing supports environment variables in CI or an ignored local key.properties file with storeFile, storePassword, keyAlias and keyPassword. A local release without signing material is unsigned. The existing Android namespace/Kotlin package can remain independent of its configured applicationId.

iOS now has a [Podfile](<../ios/Podfile>) and Pods xcconfig includes; minimum supported iOS is 13.0 across the project and Flutter framework metadata. Flutter resolves/install pods during the iOS build. The first macOS build produces Podfile.lock; review and commit it for repeatable native dependency resolution, then rerun CI. Dart dependencies are already lockfile-enforced. No native lockfile is fabricated on Windows.

## Validation and limits

Local validation covers Python signing-helper tests, workflow validation with actionlint, Flutter formatting/analyzer/tests, and diff review. These local checks do not execute Xcode, Gradle signing, certificate import, or GitHub-hosted runners. This Windows workspace has no Android SDK or Xcode, and no production signing credentials were provided. The first GitHub run supplies actual Android/iOS build evidence; inspect its logs and artifacts before distribution. GitHub Actions macOS minutes/storage may incur charges depending on repository visibility and account allowance; this is separate from Cloudflare free usage.

Xcode 16.4 is selected explicitly from the macOS 15 image; when GitHub retires it, update the pinned Xcode/Flutter combination deliberately. Current store SDK submission requirements may require a newer Xcode than this compile baseline. A successful simulator build or signed export is not an App Store acceptance guarantee.
