#!/usr/bin/env python3
"""Raise iOS deployment target for Runner, CocoaPods, and SPM plugin aggregator.

`FlutterGeneratedPluginSwiftPackage` is generated during `flutter build ios
--config-only`. On some Flutter versions its Package.swift still declares iOS
13 while firebase/file_picker SPM products require 15+.

Run once before config-only (pbxproj/Podfile) and again after with --verify.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
MIN = "15.0"
MARKER = "ZS_IOS_DEPLOYMENT"
GENERATED_PLUGIN_PKG = (
    IOS
    / "Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
)
_IOS_PLATFORM_RE = re.compile(r"\.iOS\([^)]*\)")


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


def _ios_platform_at_least_15(match: re.Match[str]) -> str:
    token = match.group(0)
    if re.search(r'\.iOS\(\s*"1[5-9]\.', token):
        return token
    if re.search(r"\.iOS\(\s*\.v1[5-9]", token):
        return token
    return f'.iOS("{MIN}")'


def _bump_ios_platform_in_package(text: str) -> str:
    return _IOS_PLATFORM_RE.sub(_ios_platform_at_least_15, text)


def patch_spm_package_swift() -> None:
    patched = 0
    if not IOS.is_dir():
        return
    for path in IOS.rglob("Package.swift"):
        text = path.read_text(encoding="utf-8")
        new_text = _bump_ios_platform_in_package(text)
        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            print(f"Patched iOS platform in {path}")
            patched += 1
    if patched == 0:
        print("No ios/**/Package.swift needed iOS platform bump")


def force_generated_plugin_package() -> None:
    """Ensure the SPM aggregator that Xcode builds declares iOS 15+."""
    if not GENERATED_PLUGIN_PKG.is_file():
        print(
            f"ERROR: {GENERATED_PLUGIN_PKG} missing — run after "
            "`flutter build ios --config-only`",
            file=sys.stderr,
        )
        sys.exit(1)

    text = GENERATED_PLUGIN_PKG.read_text(encoding="utf-8")
    new_text = _bump_ios_platform_in_package(text)
    if new_text != text:
        GENERATED_PLUGIN_PKG.write_text(new_text, encoding="utf-8")
        print(f"Forced iOS {MIN} in {GENERATED_PLUGIN_PKG}")

    if not re.search(r'\.iOS\("15\.', new_text) and ".iOS(.v15)" not in new_text:
        print(
            "ERROR: FlutterGeneratedPluginSwiftPackage still has no iOS 15+ platform:",
            file=sys.stderr,
        )
        for line in new_text.splitlines():
            if ".iOS(" in line:
                print(f"  {line.strip()}", file=sys.stderr)
        sys.exit(1)


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
    verify = "--verify" in sys.argv
    bump_pbxproj_deployment_target()
    patch_podfile()
    patch_spm_package_swift()
    patch_generated_xcconfig()
    if verify:
        force_generated_plugin_package()


if __name__ == "__main__":
    main()
