#!/usr/bin/env bash
# Build sideloadable Zentho APKs (arm64 for most phones, plus 32-bit and x86).
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
flutter build apk --release --split-per-abi

mkdir -p android-dist
cp -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk android-dist/Zentho-arm64.apk
cp -f build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk android-dist/Zentho-arm32.apk
cp -f build/app/outputs/flutter-apk/app-x86_64-release.apk android-dist/Zentho-x86_64.apk

echo "APKs written to android-dist/"
ls -lh android-dist/*.apk
