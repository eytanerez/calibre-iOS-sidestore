#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/build/DerivedData"
APP="$DERIVED_DATA/Build/Products/Release-iphoneos/Calibre.app"
IPA="$ROOT/build/Calibre.ipa"

xcodebuild \
  -project "$ROOT/Calibre.xcodeproj" \
  -scheme Calibre \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$ROOT/build/Payload" "$IPA"
mkdir -p "$ROOT/build/Payload"
cp -R "$APP" "$ROOT/build/Payload/Calibre.app"
(
  cd "$ROOT/build"
  /usr/bin/zip -qry Calibre.ipa Payload
)
rm -rf "$ROOT/build/Payload"
printf 'Created %s (%s bytes)\n' "$IPA" "$(stat -f %z "$IPA")"
