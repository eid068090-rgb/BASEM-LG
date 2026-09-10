#!/usr/bin/env bash
set -euo pipefail
# Compatibility helper. The Android host is already committed in this project.
# It intentionally does not replace the checked-in host.
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Install Flutter and run: flutter pub get"
  exit 1
fi
flutter pub get
flutter analyze
flutter build apk --release
