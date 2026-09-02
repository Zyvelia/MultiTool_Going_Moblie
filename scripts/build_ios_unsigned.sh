#!/usr/bin/env bash
# Build an unsigned IPA for sideloading (SideStore / AltStore / etc.).
#
# Why not plain `flutter build ios --no-codesign`?
#   Flutter stable still fails CI with "requires a Development Team" even when
#   codesigning is disabled. Xcode itself is fine with signing off — so we:
#     1. flutter build ios --config-only  (Generated.xcconfig, no team check)
#     2. xcodebuild with CODE_SIGNING_ALLOWED=NO (Flutter Run Script phases run)
#
# CocoaPods:
#   Plugin resolution is hybrid. Plugins with a Package.swift use SPM;
#   plugins without one (e.g. `printing`) still fall back to CocoaPods.
#   `flutter build ios --config-only` below drives that whole flow itself
#   (including `pod install` when needed) — do not deintegrate CocoaPods
#   or touch the Podfile/Pods/workspace before this runs.
#
# Prerequisites (CI or local): flutter create, flutter pub get, launcher icons.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="$ROOT/build/ios-derived"
APP="$DERIVED/Build/Products/Release-iphoneos/Runner.app"
STAGE="$ROOT/build/ios/iphoneos/Runner.app"
IPA="$ROOT/build/ios/iphoneos/MultiToolRemote-unsigned.ipa"

echo "=== iOS unsigned build ==="

python3 scripts/patch_ios_plist.py
python3 scripts/patch_ios_appdelegate.py
python3 scripts/patch_ios_unsigned.py

echo "--- Flutter config (no codesign / no team check) ---"
flutter build ios --release --config-only --no-codesign

echo "--- xcodebuild (unsigned) ---"
xattr -cr . 2>/dev/null || true
rm -rf "$DERIVED"

# Build the workspace, not the bare .xcodeproj, whenever CocoaPods is in
# play (e.g. the `printing` plugin) — the workspace is what pulls in the
# Pods static library. `flutter build ios --config-only` above creates/
# updates ios/Runner.xcworkspace via `pod install` when a Podfile exists.
if [ -d "ios/Runner.xcworkspace" ]; then
  XC_TARGET=(-workspace ios/Runner.xcworkspace)
else
  XC_TARGET=(-project ios/Runner.xcodeproj)
fi

xcodebuild \
  "${XC_TARGET[@]}" \
  -scheme Runner \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_ENTITLEMENTS="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  EXPANDED_CODE_SIGN_IDENTITY="-" \
  build

if [ ! -d "$APP" ]; then
  echo "ERROR: xcodebuild did not produce $APP" >&2
  exit 1
fi

chmod +x scripts/verify_ios_bundle.sh
scripts/verify_ios_bundle.sh "$APP"

echo "--- stage + IPA ---"
mkdir -p "$(dirname "$STAGE")"
rm -rf "$STAGE"
rsync -a "$APP/" "$STAGE/"

rm -rf "$ROOT/build/ios/iphoneos/Payload" "$IPA"
mkdir -p "$ROOT/build/ios/iphoneos/Payload"
cp -R "$STAGE" "$ROOT/build/ios/iphoneos/Payload/Runner.app"
(
  cd "$ROOT/build/ios/iphoneos"
  zip -rq MultiToolRemote-unsigned.ipa Payload
)

echo "=== Done: $IPA ==="
