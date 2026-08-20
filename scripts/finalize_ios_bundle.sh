#!/usr/bin/env bash
# Finalize Runner.app after unsigned xcodebuild (embed frameworks + Info.plist).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/ios-derived/Build/Products/Release-iphoneos/Runner.app}"

if [ ! -d "$APP" ]; then
  echo "Runner.app not found at: $APP" >&2
  exit 1
fi

if [ -f "$APP/Info.plist" ]; then
  echo "Info.plist already present in Runner.app"
  exit 0
fi

echo "Info.plist missing — running Flutter embed_and_thin..."

XC_CONFIG="$ROOT/ios/Flutter/Generated.xcconfig"
if [ ! -f "$XC_CONFIG" ]; then
  echo "Missing $XC_CONFIG (run flutter pub get first)" >&2
  exit 1
fi

FLUTTER_ROOT="$(grep '^FLUTTER_ROOT=' "$XC_CONFIG" | cut -d= -f2- | tr -d ' ')"
if [ -z "$FLUTTER_ROOT" ] || [ ! -d "$FLUTTER_ROOT" ]; then
  echo "Could not resolve FLUTTER_ROOT from $XC_CONFIG" >&2
  exit 1
fi

APP_DIR="$(cd "$(dirname "$APP")" && pwd)"
WRAPPER="$(basename "$APP")"

export FLUTTER_ROOT
export FLUTTER_APPLICATION_PATH="$ROOT"
export SRCROOT="$ROOT/ios"
export PROJECT_DIR="$ROOT/ios"
export BUILT_PRODUCTS_DIR="$APP_DIR"
export TARGET_BUILD_DIR="$APP_DIR"
export WRAPPER_NAME="$WRAPPER"
export PRODUCT_NAME="${WRAPPER%.app}"
export CONFIGURATION="Release"
export PLATFORM_NAME="iphoneos"
export EFFECTIVE_PLATFORM_NAME="-iphoneos"
export CODE_SIGNING_ALLOWED=NO
export CODE_SIGNING_REQUIRED=NO
export CODE_SIGN_IDENTITY="-"
export EXPANDED_CODE_SIGN_IDENTITY="-"
export VERBOSE_SCRIPT_LOGGING=YES
export CODESIGNING_FOLDER_PATH="$APP"
export ARCHS="arm64"
export BUILD_DIR="$ROOT/build/ios-derived/Build/Products"
export UNLOCALIZED_RESOURCES_FOLDER_PATH="$APP"
export INFOPLIST_PATH="Info.plist"
export INFOPLIST_FILE="$ROOT/ios/Runner/Info.plist"

/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" embed_and_thin \
  || echo "embed_and_thin returned non-zero — trying fallbacks..."

if [ -f "$APP/Info.plist" ]; then
  echo "Info.plist created by embed_and_thin"
  exit 0
fi

# Fallback: copy preprocessed plist from Xcode intermediates if present.
INTERMEDIATE="$ROOT/build/ios-derived/Build/Intermediates.noindex/Runner.build/Release-iphoneos/Runner.build"
for candidate in \
  "$INTERMEDIATE/Preprocessed-Info.plist" \
  "$INTERMEDIATE/assetcatalog_generated_info.plist"; do
  if [ -f "$candidate" ]; then
    cp "$candidate" "$APP/Info.plist"
    echo "Copied Info.plist from $(basename "$candidate")"
    exit 0
  fi
done

# Last resort: expand ios/Runner/Info.plist template variables from Generated.xcconfig.
if [ -f "$ROOT/ios/Runner/Info.plist" ]; then
  ROOT="$ROOT" APP="$APP" python3 - <<'PY'
import os
import pathlib

root = pathlib.Path(os.environ["ROOT"])
app = pathlib.Path(os.environ["APP"])
xc = {}
for line in (root / "ios/Flutter/Generated.xcconfig").read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("//") or "=" not in line:
        continue
    key, value = line.split("=", 1)
    xc[key.strip()] = value.strip()

subs = {
    "EXECUTABLE_NAME": "Runner",
    "PRODUCT_NAME": "Runner",
    "PRODUCT_BUNDLE_IDENTIFIER": xc.get("PRODUCT_BUNDLE_IDENTIFIER", "com.zsmultitool.multiToolRemote"),
    "FLUTTER_BUILD_NAME": xc.get("FLUTTER_BUILD_NAME", "1.0.0"),
    "FLUTTER_BUILD_NUMBER": xc.get("FLUTTER_BUILD_NUMBER", "1"),
    "DEVELOPMENT_LANGUAGE": "en",
}
text = (root / "ios/Runner/Info.plist").read_text(encoding="utf-8")
for key, value in subs.items():
    text = text.replace(f"$({key})", value)
(app / "Info.plist").write_text(text, encoding="utf-8")
print("Generated Info.plist from ios/Runner/Info.plist template")
PY
  if [ -f "$APP/Info.plist" ]; then
    exit 0
  fi
fi

echo "ERROR: Runner.app still has no Info.plist after finalize" >&2
exit 1
