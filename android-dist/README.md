# Zentho Android APKs

Sideload installers for testing on a phone. Most modern phones want **`Zentho-arm64.apk`**.

## Install

1. Download the APK onto the phone (this folder on GitHub, or the **zentho-android-apk** artifact from the *Build Android APK* GitHub Action).
2. Open the file. If Android blocks it, allow installs from that app (Files, Chrome, Drive, etc.).
3. Open **Zentho** from the launcher.

The app works offline with local storage. Google sign-in on Android also needs an Android app + this debug SHA-1 in the Firebase console (`zentho-db83e`); unsigned-in use does not:

```
SHA-1: 44:50:52:5F:B6:E3:96:28:EC:5A:03:C8:26:E4:46:EB:37:2D:F2:AF
```

These APKs are debug-signed for sideload testing (`com.zentho.zentho`, minSdk 24). Rebuild with `./scripts/build-android-apk.sh` from a machine with Flutter and the Android SDK.
