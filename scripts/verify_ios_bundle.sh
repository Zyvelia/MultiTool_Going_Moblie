#!/usr/bin/env bash
# Verify a Runner.app is complete enough to sideload / package as IPA.
set -euo pipefail

APP="${1:?Usage: verify_ios_bundle.sh path/to/Runner.app}"

if [ ! -d "$APP" ]; then
  echo "ERROR: not a directory: $APP" >&2
  exit 1
fi

if [ ! -f "$APP/Info.plist" ]; then
  echo "ERROR: Info.plist missing in $APP" >&2
  exit 1
fi

EXEC_NAME="$(python3 - <<PY
import plistlib
from pathlib import Path
with (Path("$APP") / "Info.plist").open("rb") as f:
    print(plistlib.load(f).get("CFBundleExecutable", "Runner"))
PY
)"

if [ ! -f "$APP/$EXEC_NAME" ]; then
  echo "ERROR: main binary missing — expected $APP/$EXEC_NAME" >&2
  echo "Bundle contents:" >&2
  ls -la "$APP" >&2 || true
  exit 1
fi

if [ ! -d "$APP/Frameworks/App.framework" ]; then
  echo "ERROR: App.framework not embedded in $APP/Frameworks" >&2
  ls -la "$APP/Frameworks" 2>/dev/null >&2 || true
  exit 1
fi

echo "Bundle OK — $EXEC_NAME + App.framework present in $APP"
