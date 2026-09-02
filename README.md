# Zentho

Personal finance tracker with household budgets, multi-currency conversion, shared + private sections, and an investments foresight area. One Flutter codebase for **Android**, **Windows**, and **Web**.

## Highlights

- Offline-first local storage (SharedPreferences). Optional **Google sign-in** stores the same ledger in Cloud Firestore so it syncs across devices
- Same-device household profiles with **Shared** / **Private** visibility
- Main currency + per-account / per-transaction currency (**USD, EUR, GBP, JPY, CAD, AUD, CHF, RON**)
- Online FX refresh at app/site start (Frankfurter → open.er-api fallback), offline defaults otherwise
- Hybrid budgeting, **Available to spend**, end-of-period predictions, and multi-horizon forecast chart

- Manual transactions + CSV import
- Goals, recurring/subscription tracking, reports
- Stock/ETF holdings with Yahoo Finance quotes (Finnhub optional on web), allocation, and P/L
- Responsive UI (phone bottom nav / desktop rail) with widget + unit tests

## Live web app

https://michaelady.github.io/PersonalFinanceTracker/

Deployed automatically via GitHub Actions (`.github/workflows/deploy-web.yml`) on pushes to `main`.

## Accounts (Google / Firebase)

Unsigned-in use stays fully local. Signing in with Google (Settings or User) writes `FinanceSnapshot` JSON to Firestore at `users/{uid}/data/snapshot` plus `updatedAt`. Quote API tokens and the quote cache stay on the device only.

Household invite links (jsonblob) are **not** identity and keep working without Firebase.

### Client config

Public web SDK values live in `lib/firebase_options.dart` (project `zentho-db83e`). The web `apiKey` is not a secret. **Never commit a service-account JSON.** Analytics is off.

Firebase console setup is already done on Spark: Google sign-in, authorized domains `michaelady.github.io` and `localhost`, Firestore (`eur3`, production mode), and `firestore.rules` published (`request.auth.uid == userId` on `users/{userId}/{document=**}`). Do not recreate those. Spark is enough — do not enable Blaze.

On sign-in: if cloud has a snapshot and it is newer (or this device has no ledger yet), cloud is loaded into local storage. If only this device has data, it is uploaded. Sign-out does not wipe the local copy.

## Run locally

```bash
flutter pub get

# Web
flutter run -d chrome

# Windows (on a Windows machine)
flutter run -d windows

# Android (device/emulator with Android SDK)
flutter run -d android
```


## Test

```bash
flutter test
flutter analyze
```

## CSV import format

```csv
date,amount,type,category,account,note,currency,visibility
2026-08-01,42.50,expense,Groceries,Checking,Market,USD,shared
```

`type`: `income` | `expense`  
`visibility`: `shared` | `private` (optional)

## Brand

Zentho — teal / mint light modern finance UI. App icon lives in `assets/branding/zentho_app_icon.png`.
