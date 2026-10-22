#!/usr/bin/env python3
"""Patch pub iOS plugins after `flutter pub get` (CI Xcode 16 compatibility)."""
from __future__ import annotations

import os
import re
from pathlib import Path

MARKER = "ZS_DEVICE_INFO_VISION_XCODE16"


def _pub_cache() -> Path:
    return Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))


def patch_device_info_plus() -> None:
    """device_info_plus 12.4+ references isiOSAppOnVision (Xcode 26.1+ SDK only).

    GitHub Actions uses Xcode 16.x — strip the call so Objective-C compiles.
    The field stays false / omitted; harmless for step counting and sideload builds.
    """
    root = _pub_cache() / "hosted/pub.dev"
    paths = sorted(
        root.glob(
            "device_info_plus-*/ios/device_info_plus/Sources/device_info_plus/FPPDeviceInfoPlusPlugin.m"
        )
    )
    if not paths:
        print("device_info_plus iOS source not found in pub cache — skip")
        return

    vision_line = re.compile(
        r"\s*isiOSAppOnVision = \[NSNumber numberWithBool:\[info isiOSAppOnVision\]\];\n"
    )

    for path in paths:
        text = path.read_text(encoding="utf-8")
        if MARKER in text:
            print(f"Already patched {path}")
            continue
        if "isiOSAppOnVision" not in text:
            print(f"No isiOSAppOnVision in {path} — skip")
            continue

        new_text = vision_line.sub(
            f"\n      // {MARKER}: omitted — requires Xcode 26.1+ SDK\n",
            text,
            count=1,
        )
        if new_text == text:
            print(f"Could not patch vision selector in {path}")
            continue
        path.write_text(new_text, encoding="utf-8")
        print(f"Patched {path}")


def main() -> None:
    patch_device_info_plus()


if __name__ == "__main__":
    main()
