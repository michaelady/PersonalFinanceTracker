# Google Play Store — Zentho

Checklist for publishing the Android app. This is an operations guide, not legal advice.

**Do not commit keystores, `android/key.properties`, or Play / Firebase secrets.**

Live web (also hosts the privacy placeholder): https://michaelady.github.io/PersonalFinanceTracker/

## Identity (do not change after the first upload)

| Field | Value |
| --- | --- |
| App name (listing + launcher) | Zentho |
| Dart package (`pubspec.yaml` `name`) | `zentho` |
| Android `applicationId` / `namespace` | `com.zentho.zentho` |
| Version | `pubspec.yaml` `version: 1.0.0+8` → Play `versionName` **1.0.0**, `versionCode` **8** |

Play treats `applicationId` as the app’s identity. Changing it later creates a different app.

Each new upload must increase `versionCode` (the number after `+`). Bump `versionName` when you want users to see a new marketing version.

```bash
# one-off override without editing pubspec
flutter build appbundle --release --build-name=1.0.1 --build-number=9
```

SDK targets (pinned in `android/app/build.gradle.kts`):

- `compileSdk` / `targetSdk`: at least **36** (Play requirement for new apps and updates as of 31 Aug 2026)
- `minSdk`: Flutter default (currently API 24 on current stable)

Launcher / adaptive icons: `android/app/src/main/res/mipmap-*` plus `mipmap-anydpi-v26`. Brand source: `assets/branding/zentho_app_icon.png`.

## 1. Upload keystore (local, never in git)

```bash
keytool -genkey -v \
  -keystore "$HOME/zentho-upload-keystore.jks" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

Copy `android/key.properties.example` to `android/key.properties` and set `storePassword`, `keyPassword`, `keyAlias`, and `storeFile` (absolute path). Keep the `.jks` and passwords in a password manager. If you lose the upload key, Play App Signing can still ship updates after you go through Play’s upload-key reset.

## 2. Build the AAB

```bash
./scripts/build-android-aab.sh
# or
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

Without `android/key.properties`, Gradle **debug-signs** the bundle so CI and local smoke builds work. **Do not upload a debug-signed AAB to Play.**

Play App Signing: in Play Console enable it (required for new apps). Play holds the app-signing key; you sign uploads with the upload keystore above.

## 3. Play Console — create the app

1. [Play Console](https://play.google.com/console) → **Create app**.
2. App name: **Zentho**. Default language: choose yours. Type: **App**. Free vs paid: typically **Free**.
3. Accept declarations (US export, content guidelines, etc.).
4. Dashboard → complete **App content** and **Store presence** until the first-release checklist is green.

### Store listing (draft copy — edit to taste)

- **Short description** (80 chars max): `Household budgets, multi-currency, and investment foresight.`
- **Full description**: Zentho is a personal finance tracker for households. Keep shared and private ledgers, convert currencies, set budgets and goals, import CSV, and follow stock/ETF holdings. Works offline on this device; optional Google sign-in syncs the same ledger through Firestore.
- **App category**: typically **Finance**.
- **Contact email**: required. Website: `https://michaelady.github.io/PersonalFinanceTracker/`
- **Privacy policy URL** (required for this app): until you publish a real policy, the placeholder is `https://michaelady.github.io/PersonalFinanceTracker/privacy.html`. **Replace this URL after a real policy is finalized** (Settings in the app uses the same default; override with `--dart-define=PRIVACY_POLICY_URL=...`).

### Graphics

| Asset | Size | Notes |
| --- | --- | --- |
| High-res icon | **512 × 512** PNG, 32-bit, no alpha | Can start from `assets/branding/zentho_app_icon.png` |
| Feature graphic | **1024 × 500** PNG/JPG | Required. Teal/mint brand (`#0B6E6E`, `#E8F5F2`) |
| Phone screenshots | **2–8** images, JPEG/PNG, **16:9 or 9:16**, each side **320–3840 px** | Capture Home, accounts, budget, investments, settings |
| 7-inch / 10-inch tablet | optional; same aspect rules | Capture the desktop/rail layout on a wide window if you list tablets |
| Promo video | optional YouTube URL | |

Do not include Play badges or other stores’ marks on screenshots.

### Content rating

Complete the IARC questionnaire. Zentho is a finance utility with no user-generated public social feed, no ads in-app as of this checklist. Answer truthfully if that changes.

### Target audience

Likely **18+** (personal financial data). If you select under-18, COPPA / Families policies apply — do not do that unless the product is actually for children.

### News / Data safety / Advertising ID

- **News app**: no.
- **Advertising ID**: Zentho does not use ads; declare **no advertising ID** unless a dependency adds it (Play will flag the merged manifest).
- **Data safety**: fill from the table below. This is not a substitute for a privacy policy.

## 4. Data safety (draft answers)

Review in Play Console; these match the current codebase.

| Data type | Collected? | Shared with other companies? | Purpose |
| --- | --- | --- | --- |
| Email (Google account) | Optional, if user signs in | Processed by Google (Firebase Auth) | App functionality (account) |
| Name (Google display name) | Optional, if user signs in | Processed by Google | App functionality |
| Financial info (user-entered transactions, accounts, budgets, holdings) | Yes, on device; also in Firestore if signed in | Not sold. Firestore is Google Cloud acting as processor for the operator | App functionality |
| User-generated content in the ledger | Same as financial info | Same | App functionality |
| Device or other IDs | Firebase / Google sign-in may use account identifiers | Google | App functionality |

Also declare:

- Data encrypted **in transit** (HTTPS; cleartext disabled).
- Users can **delete** on-device data via Settings → Clear all data. Document how you delete the Firestore `users/{uid}` document if you offer account deletion (add that flow or a support email before claiming in-app deletion of cloud data).
- Android cloud backup of app data is **off**.
- Optional quote API tokens stay on device and are not uploaded.

Permissions (merged manifest — justify in Play if asked):

| Permission | Why |
| --- | --- |
| `INTERNET` | FX, quotes, Firebase, OAuth |
| `CAMERA` | Bill / invoice photo scan (not required to install; `android.hardware.camera` is optional) |
| `READ_EXTERNAL_STORAGE` (max SDK 32) | CSV / image pick on older Android |

Photo/video library permissions are stripped so Play’s Photo and Video policy is not triggered; gallery uses the system picker.

## 5. Firebase / Google sign-in (Android)

Package `com.zentho.zentho` currently talks to project `zentho-db83e` using the **web** client config (in-app browser OAuth on Android). For Play:

1. Firebase console → add an **Android** app with package `com.zentho.zentho` if you want native Play services later (optional for the current web-OAuth path).
2. Add **SHA-1 and SHA-256** of the **upload** key and of the **Play app-signing** key (Play Console → Test and release → App integrity) so Google sign-in and any future native SDK keep working.
3. Do not commit `google-services.json` secrets beyond the usual public client file if you add one.

## 6. Upload and test tracks

1. Play Console → **Test and release** → **Testing** → **Internal testing**.
2. Create a release → upload `app-release.aab` (upload-key signed).
3. Add testers (Gmail / Google Groups). Internal testing does not require a completed store listing for install, but production does.
4. Run through: first-run, local-only use, Google sign-in, CSV import/export, bill scan permission prompts, FX refresh, investments.
5. When ready: **Closed testing** (content rating must be complete) then **Production**.

Do not use the sideload APKs in `android-dist/` for Play. Those are debug-key APKs for phones.

## 7. CI

`.github/workflows/build-android.yml` builds release APKs **and** an AAB on pull requests and `main` (debug-signed unless secrets are set).

`.github/workflows/build-android-aab.yml` builds an AAB on version tags `v*` (for example `v1.0.0`) and on **workflow_dispatch**. Optional repo secrets:

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64 of the `.jks` / `.keystore` |
| `ANDROID_KEYSTORE_PASSWORD` | `storePassword` |
| `ANDROID_KEY_PASSWORD` | `keyPassword` |
| `ANDROID_KEY_ALIAS` | usually `upload` |

If those secrets are missing, the job still produces a **debug-signed** AAB artifact for smoke tests — not for Play.

```bash
# encode a keystore for the secret (local machine only)
base64 -i "$HOME/zentho-upload-keystore.jks" | tr -d '\n'
```

## Adrian still needs to fill in

- [ ] Generate and back up the upload keystore; create `android/key.properties` locally
- [ ] Confirm Play package id stays `com.zentho.zentho`
- [ ] Finalize privacy policy (replace `web/privacy.html`) and set the Play listing URL
- [ ] Play developer account / contact email / physical address if Play asks
- [ ] 512×512 icon, 1024×500 feature graphic, phone screenshots
- [ ] Data safety + content rating + target audience in Console
- [ ] Firebase SHA-1 / SHA-256 for the Play signing keys
- [ ] First AAB on Internal testing, then production
