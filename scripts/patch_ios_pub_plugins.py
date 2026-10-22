#!/usr/bin/env python3
"""Patch pub iOS plugins after `flutter pub get` (CI Xcode 16 compatibility)."""
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKER = "ZS_DEVICE_INFO_VISION_XCODE16"

VISION_LINE = re.compile(
    r"\s*isiOSAppOnVision = \[NSNumber numberWithBool:\[info isiOSAppOnVision\]\];\n"
)


def _pub_cache() -> Path:
    return Path(os.environ.get("PUB_CACHE", Path.home() / ".pub-cache"))


def _device_info_plugin_sources() -> list[Path]:
    patterns = [
        _pub_cache().glob(
            "hosted/pub.dev/device_info_plus-*/ios/device_info_plus/Sources/device_info_plus/FPPDeviceInfoPlusPlugin.m"
        ),
        ROOT.glob(
            "ios/Flutter/ephemeral/**/device_info_plus*/**/FPPDeviceInfoPlusPlugin.m"
        ),
        ROOT.glob(
            "ios/Flutter/ephemeral/Packages/**/FPPDeviceInfoPlusPlugin.m"
        ),
    ]
    found: list[Path] = []
    seen: set[Path] = set()
    for gen in patterns:
        for path in gen:
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            if path.is_file():
                found.append(path)
    return sorted(found)


def _patch_one_device_info_file(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"Already patched {path}")
        return False
    if "isiOSAppOnVision" not in text:
        print(f"No isiOSAppOnVision in {path} — skip")
        return False

    new_text = VISION_LINE.sub(
        f"\n      // {MARKER}: omitted — requires Xcode 26.1+ SDK\n",
        text,
        count=1,
    )
    if new_text == text:
        print(f"Could not patch vision selector in {path}")
        return False
    path.write_text(new_text, encoding="utf-8")
    print(f"Patched {path}")
    return True


def patch_device_info_plus() -> None:
    """device_info_plus 12.4+ references isiOSAppOnVision (Xcode 26.1+ SDK only)."""
    paths = _device_info_plugin_sources()
    if not paths:
        print("device_info_plus iOS source not found — skip")
        return
    for path in paths:
        _patch_one_device_info_file(path)


def main() -> None:
    patch_device_info_plus()


if __name__ == "__main__":
    main()
