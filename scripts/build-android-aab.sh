#!/usr/bin/env bash
# Build a Play-uploadable Android App Bundle (AAB).
# Signs with android/key.properties when present; otherwise the debug key
# (smoke only — do not upload a debug-signed AAB to Play).
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f android/key.properties ]]; then
  echo "Note: android/key.properties is missing. The AAB will be debug-signed." >&2
  echo "Copy android/key.properties.example → android/key.properties before Play upload." >&2
fi

flutter pub get
flutter build appbundle --release

out="build/app/outputs/bundle/release/app-release.aab"
echo "AAB written to $out"
ls -lh "$out"
