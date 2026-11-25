# Expleo Test Bank - iOS (SwiftUI)

Native SwiftUI port of the Android app in `../app`. Same screens, same backend
(`http://20.67.48.181/`), same automation identifiers (`accessibilityIdentifier` = Android `testTag`).

## Getting an installable IPA (no Mac needed)

The IPA is built on a GitHub-hosted macOS runner (`.github/workflows/build-ios.yml`).

1. Push this folder to a GitHub repo (folder root must contain `project.yml`).
2. Open **Actions -> Build iOS IPA -> Run workflow** (it also runs on every push to `main`).
3. When it finishes, download the artifact **ExpleoTestBank-unsigned-ipa** -> `ExpleoTestBank-unsigned.ipa`.
4. Upload it to pCloudy (**Apps -> Upload**). pCloudy re-signs unsigned iOS builds for its devices.
   If your pCloudy plan asks for a signed IPA, use its *Re-sign* option for iOS apps.

The Xcode project is generated from `project.yml` by XcodeGen, so there is no `.xcodeproj` in git.

## Appium / XCUITest

Locators are `accessibilityIdentifier`s identical to the Android `testTag`s
(`login_username`, `login_password`, `login_submit`, `otp_code`, `payment_amount`, ...).
With Settings -> Chaos lab -> "Alternate locator fields" they get a `chaos_` prefix, as on Android.

## Layout

- `Sources/Core` - models, API client, stores (session, settings, MPIN, Keychain, KYC), localisation, biometrics, notifications
- `Sources/UI` - theme, design components, shared widgets
- `Sources/Screens` - feature screens
- `Resources` - assets, `en`/`ar` `Localizable.strings` (generated from Android strings by `scripts/gen_strings.py`)
