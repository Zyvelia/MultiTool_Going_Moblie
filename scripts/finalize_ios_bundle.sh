#!/usr/bin/env bash
# Finalize Runner.app after unsigned xcodebuild — embed Flutter frameworks,
# ensure Info.plist, and verify the main executable exists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/ios-derived/Build/Products/Release-iphoneos/Runner.app}"

if [ ! -d "$APP" ]; then
  echo "Runner.app not found at: $APP" >&2
  exit 1
fi

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

echo "Running Flutter embed_and_thin (required even when Info.plist already exists)..."
set +e
/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" embed_and_thin
EMBED_EXIT=$?
set -e
if [ "$EMBED_EXIT" -ne 0 ]; then
  echo "WARNING: embed_and_thin exited $EMBED_EXIT — continuing with fallbacks" >&2
fi

if [ ! -f "$APP/Info.plist" ]; then
  echo "Info.plist still missing — trying Xcode intermediates..."

  INTERMEDIATE="$ROOT/build/ios-derived/Build/Intermediates.noindex/Runner.build/Release-iphoneos/Runner.build"
  for candidate in \
    "$INTERMEDIATE/Preprocessed-Info.plist" \
    "$INTERMEDIATE/assetcatalog_generated_info.plist"; do
    if [ -f "$candidate" ]; then
      cp "$candidate" "$APP/Info.plist"
      echo "Copied Info.plist from $(basename "$candidate")"
      break
    fi
  done
fi

if [ ! -f "$APP/Info.plist" ] && [ -f "$ROOT/ios/Runner/Info.plist" ]; then
  echo "Generating Info.plist from ios/Runner/Info.plist template..."
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
fi

if [ ! -f "$APP/Info.plist" ]; then
  echo "ERROR: Runner.app has no Info.plist after finalize" >&2
  exit 1
fi

EXEC_NAME="$(python3 - <<PY
import plistlib
from pathlib import Path
p = Path("$APP") / "Info.plist"
with p.open("rb") as f:
    data = plistlib.load(f)
print(data.get("CFBundleExecutable", "Runner"))
PY
)"

if [ ! -f "$APP/$EXEC_NAME" ]; then
  echo "ERROR: main binary missing — expected $APP/$EXEC_NAME" >&2
  echo "Bundle contents:" >&2
  ls -la "$APP" >&2 || true
  if [ -d "$APP/Frameworks" ]; then
    echo "Frameworks:" >&2
    ls -la "$APP/Frameworks" >&2 || true
  fi
  exit 1
fi

if [ ! -x "$APP/$EXEC_NAME" ]; then
  chmod +x "$APP/$EXEC_NAME"
fi

if [ ! -d "$APP/Frameworks/App.framework" ]; then
  echo "ERROR: App.framework not embedded in $APP/Frameworks" >&2
  exit 1
fi

echo "Bundle OK — Info.plist present, executable $EXEC_NAME, App.framework embedded"
