# Zentho

Personal finance tracker with household budgets, multi-currency conversion, shared + private sections, and an investments foresight area. One Flutter codebase for **Android**, **Windows**, and **Web**.

## Highlights

- Offline-first local storage (no cloud login in v1)
- Same-device household profiles with **Shared** / **Private** visibility
- Main currency + per-account / per-transaction currency (**USD, EUR, GBP, JPY, CAD, AUD, CHF, RON**)
- Online FX refresh at app/site start (Frankfurter → open.er-api fallback), offline defaults otherwise
- Hybrid budgeting, **Available to spend**, end-of-month/year predictions, and multi-horizon forecast chart

- Manual transactions + CSV import
- Goals, recurring/subscription tracking, reports
- Stock/ETF holdings with Yahoo Finance quotes (Finnhub optional on web), allocation, and P/L
- Responsive UI (phone bottom nav / desktop rail) with widget + unit tests

## Live web app

https://michaelady.github.io/PersonalFinanceTracker/

Deployed automatically via GitHub Actions (`.github/workflows/deploy-web.yml`) on pushes to `main`.

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
