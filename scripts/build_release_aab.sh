#!/usr/bin/env bash
# Release AAB build for Play Store Internal Testing.
# Preconditions (owner provides; never committed):
#   1. app/android/key.properties        (from key.properties.template)
#   2. the upload keystore at the path it references
#   3. env.json at the repo root         (from env.json.example)
#   4. signingConfig wired for 'release' in app/android/app/build.gradle(.kts)
#      per https://docs.flutter.dev/deployment/android#signing-the-app
# This script never prints or logs secret values.
set -euo pipefail
cd "$(dirname "$0")/.."

missing=0
need() { if [ ! -f "$1" ]; then echo "MISSING: $1 — $2"; missing=1; fi }
need app/android/key.properties "copy app/android/key.properties.template (keystore credentials)"
need env.json "copy env.json.example (Supabase URL + anon key)"

if [ "$missing" -ne 0 ]; then
  echo
  echo "Provide the files above, then re-run. See docs/playstore-checklist.md section 2–3."
  exit 1
fi

if ! grep -Eq 'keyAlias|storeFile' app/android/key.properties; then
  echo "key.properties looks empty/invalid (expected keyAlias= and storeFile= lines)." >&2
  exit 1
fi

python3 scripts/prepare_offline_assets.py
cd app
flutter pub get
flutter gen-l10n
flutter analyze --no-pub
flutter test

echo "Building release appbundle (version $(grep '^version:' pubspec.yaml))..."
flutter build appbundle --release --dart-define-from-file=../env.json

AAB="build/app/outputs/bundle/release/app-release.aab"
echo "OK: app/$AAB"
if grep -qE 'signingConfigs\.debug|getByName\("debug"\)' android/app/build.gradle android/app/build.gradle.kts 2>/dev/null; then
  echo "NOTE: release currently signed with the DEBUG key (template default). It installs"
  echo "      on devices but Play Console will require the owner's upload key on first upload."
fi
