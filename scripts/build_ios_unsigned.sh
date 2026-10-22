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

python3 scripts/patch_ios_firebase.py
python3 scripts/patch_ios_plist.py
if [[ "${PATCH_IOS_HEALTHKIT:-0}" == "1" ]]; then
  python3 scripts/patch_ios_healthkit.py
else
  echo "Skipping HealthKit patch (Steps on iOS uses motion only). Set PATCH_IOS_HEALTHKIT=1 if you have a paid Apple Developer HealthKit App ID."
fi
python3 scripts/patch_ios_appdelegate.py
python3 scripts/patch_ios_unsigned.py
python3 scripts/patch_ios_pub_plugins.py

echo "--- Flutter config (no codesign / no team check) ---"
flutter build ios --release --config-only --no-codesign
python3 scripts/patch_ios_pub_plugins.py

echo "--- Dart analysis (fail fast before xcodebuild Run Script) ---"
rm -rf _ci_test_android _gradle_probe
flutter analyze lib test --no-fatal-infos --no-fatal-warnings

echo "--- Prepare Xcode dependency state ---"
# A stale/corrupt SwiftPM Package.resolved can produce misleading JSON/
# project parse errors after Flutter regenerates ios/. Let Xcode regenerate it.
find ios -path "*/swiftpm/Package.resolved" -type f -delete 2>/dev/null || true

echo "--- xcodebuild (unsigned) ---"
xattr -cr . 2>/dev/null || true
rm -rf "$DERIVED"
mkdir -p "$DERIVED"

# Build the workspace, not the bare .xcodeproj, whenever CocoaPods is in
# play (e.g. the `printing` plugin) — the workspace is what pulls in the
# Pods static library. `flutter build ios --config-only` above creates/
# updates ios/Runner.xcworkspace via `pod install` when a Podfile exists.
if [ -d "ios/Runner.xcworkspace" ]; then
  XC_TARGET=(-workspace ios/Runner.xcworkspace)
else
  XC_TARGET=(-project ios/Runner.xcodeproj)
fi

echo "--- Validate Xcode project ---"
xcodebuild "${XC_TARGET[@]}" -scheme Runner -configuration Release -sdk iphoneos -showBuildSettings >/dev/null

XC_LOG="$ROOT/build/ios-derived/xcodebuild.log"
set +e
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
  CODE_SIGN_ENTITLEMENTS="$ROOT/ios/Runner/Runner.entitlements" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  EXPANDED_CODE_SIGN_IDENTITY="-" \
  build 2>&1 | tee "$XC_LOG"
XC_STATUS=${PIPESTATUS[0]}
set -e
if [ "$XC_STATUS" -ne 0 ]; then
  echo "=== xcodebuild failed (exit $XC_STATUS) — last 80 lines ===" >&2
  if [ -f "$XC_LOG" ]; then
    tail -n 80 "$XC_LOG" >&2
  else
    echo "(no log at $XC_LOG)" >&2
  fi
  echo "=== Flutter / Dart errors in log (if any) ===" >&2
  grep -E "Error:|error:|FAILED|PhaseScriptExecution" "$XC_LOG" | tail -n 40 >&2 || true
  exit "$XC_STATUS"
fi

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
