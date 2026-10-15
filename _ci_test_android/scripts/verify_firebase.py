#!/usr/bin/env python3
"""Validate the Firebase client files against the app IDs used by this project."""
from __future__ import annotations

import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID_CONFIG = ROOT / "firebase/google-services.json"
IOS_CONFIG = ROOT / "firebase/GoogleService-Info.plist"
ANDROID_PACKAGE = "com.zsmultitool.multi_tool_remote"
IOS_BUNDLE = "com.zsmultitool.multiToolRemote"


def fail(message: str) -> None:
    raise SystemExit(f"Firebase validation failed: {message}")


def verify_android() -> None:
    if not ANDROID_CONFIG.is_file():
        fail(f"missing {ANDROID_CONFIG}")
    try:
        data = json.loads(ANDROID_CONFIG.read_text(encoding="utf-8"))
        clients = data.get("client", [])
        packages = {
            c.get("client_info", {}).get("android_client_info", {}).get("package_name")
            for c in clients
        }
    except Exception as exc:
        fail(f"could not parse google-services.json: {exc}")

    if ANDROID_PACKAGE not in packages:
        fail(
            f"google-services.json has no Android client for {ANDROID_PACKAGE}; "
            f"found: {sorted(p for p in packages if p)}"
        )
    print(f"OK: Android Firebase client = {ANDROID_PACKAGE}")


def verify_ios() -> None:
    if not IOS_CONFIG.is_file():
        fail(f"missing {IOS_CONFIG}")
    try:
        with IOS_CONFIG.open("rb") as handle:
            data = plistlib.load(handle)
    except Exception as exc:
        fail(f"could not parse GoogleService-Info.plist: {exc}")

    bundle_id = data.get("BUNDLE_ID")
    if bundle_id != IOS_BUNDLE:
        fail(f"GoogleService-Info.plist BUNDLE_ID is {bundle_id!r}, expected {IOS_BUNDLE!r}")
    print(f"OK: iOS Firebase client = {IOS_BUNDLE}")


def main() -> None:
    verify_android()
    verify_ios()
    print("Firebase client configuration is valid.")


if __name__ == "__main__":
    main()
