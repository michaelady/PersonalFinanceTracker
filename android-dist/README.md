# Zentho Android APKs

Sideload installers for testing on a phone. Most modern phones want **`Zentho-arm64.apk`**.

## Install

1. Download the APK onto the phone (this folder on GitHub, or the **zentho-android-apk** artifact from the *Build Android APK* GitHub Action).
2. Open the file. If Android blocks it, allow installs from that app (Files, Chrome, Drive, etc.).
3. Open **Zentho** from the launcher.

The app works offline with local storage. Google sign-in on this APK talks to Firebase project `zentho-db83e` over Identity Toolkit (same accounts as the website). Unsigned-in use does not need a Google account.

Rebuild with `./scripts/build-android-apk.sh` from a machine with Flutter and the Android SDK.
