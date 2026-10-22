#!/usr/bin/env python3
"""Adds FirebaseApp.configure() to the scaffolded AppDelegate.swift.

CI regenerates ios/ with `flutter create` on every run, so this re-applies
Firebase startup after the template is recreated.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DELEGATE = ROOT / "ios/Runner/AppDelegate.swift"

MARKER = "FirebaseApp.configure()"

RETURN_LINE = (
    "    return super.application(application, didFinishLaunchingWithOptions: launchOptions)"
)

RETURN_REPLACEMENT = """    let didFinishLaunching = super.application(
      application, didFinishLaunchingWithOptions: launchOptions)
    FirebaseApp.configure()
    return didFinishLaunching"""


def main() -> None:
    if not APP_DELEGATE.is_file():
        raise SystemExit(f"{APP_DELEGATE} missing — run flutter create first")

    text = APP_DELEGATE.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"{APP_DELEGATE} already patched")
        return

    if RETURN_LINE not in text:
        raise SystemExit(f"Could not find the launch return in {APP_DELEGATE}")
    text = text.replace(RETURN_LINE, RETURN_REPLACEMENT, 1)
    if "import FirebaseCore" not in text:
        text = text.replace("import Flutter\n", "import Flutter\nimport FirebaseCore\n", 1)

    APP_DELEGATE.write_text(text, encoding="utf-8")
    print(f"Patched {APP_DELEGATE}")


if __name__ == "__main__":
    main()
