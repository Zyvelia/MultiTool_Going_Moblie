#!/usr/bin/env python3
"""Raise iOS deployment target after `flutter build ios --config-only`.

Runner's pbxproj is patched earlier, but Flutter's SPM aggregator
`FlutterGeneratedPluginSwiftPackage` is generated during config-only and still
defaults to iOS 13. Several plugins (firebase, health, file_picker) require 14+.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
MIN = "15.0"
MARKER = "ZS_IOS_DEPLOYMENT"


def bump_pbxproj_deployment_target() -> None:
    path = IOS / "Runner.xcodeproj/project.pbxproj"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    original = text
    text = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET = \d+(?:\.\d+)?;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {MIN};",
        text,
    )
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Set IPHONEOS_DEPLOYMENT_TARGET = {MIN} in {path}")


def patch_podfile() -> None:
    path = IOS / "Podfile"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    original = text
    text = re.sub(
        r"^platform\s*:ios,\s*['\"]?\d+(?:\.\d+)?['\"]?\s*$",
        f"platform :ios, '{MIN}'",
        text,
        flags=re.MULTILINE,
    )
    text = re.sub(
        r"^#\s*platform\s*:ios,\s*['\"]?\d+(?:\.\d+)?['\"]?\s*$",
        f"platform :ios, '{MIN}'",
        text,
        flags=re.MULTILINE,
    )
    if not re.search(rf"^platform\s*:ios,\s*['\"]{MIN}['\"]", text, re.MULTILINE):
        text = f"platform :ios, '{MIN}'\n" + text

    hook = f"""
  # {MARKER}
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '{MIN}'
    end
  end
"""
    if MARKER not in text and "post_install do |installer|" in text:
        text = text.replace(
            "post_install do |installer|",
            "post_install do |installer|" + hook,
            1,
        )

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Patched {path}")


def _bump_ios_platform_in_package(text: str) -> str:
    text = re.sub(r"\.iOS\(\.v1[0-4]\)", ".iOS(.v15)", text)
    text = re.sub(r'\.iOS\("1[0-4]\.0"\)', '.iOS("15.0")', text)
    return text


def patch_spm_package_swift() -> None:
    patched = 0
    for path in IOS.rglob("Package.swift"):
        text = path.read_text(encoding="utf-8")
        new_text = _bump_ios_platform_in_package(text)
        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            print(f"Patched iOS platform in {path}")
            patched += 1
    if patched == 0:
        print("No ios/**/Package.swift needed iOS platform bump")


def patch_generated_xcconfig() -> None:
    for path in IOS.rglob("*.xcconfig"):
        if "Flutter" not in path.parts and path.name not in (
            "Debug.xcconfig",
            "Release.xcconfig",
        ):
            continue
        text = path.read_text(encoding="utf-8")
        original = text
        if "IPHONEOS_DEPLOYMENT_TARGET" in text:
            text = re.sub(
                r"IPHONEOS_DEPLOYMENT_TARGET\s*=\s*\d+(?:\.\d+)?",
                f"IPHONEOS_DEPLOYMENT_TARGET={MIN}",
                text,
            )
        if text != original:
            path.write_text(text, encoding="utf-8")
            print(f"Patched deployment in {path}")


def main() -> None:
    bump_pbxproj_deployment_target()
    patch_podfile()
    patch_spm_package_swift()
    patch_generated_xcconfig()


if __name__ == "__main__":
    main()
