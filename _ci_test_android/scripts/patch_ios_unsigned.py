#!/usr/bin/env python3
"""Patches for unsigned iOS CI builds (no Apple Developer team).

Flutter's iOS plugin resolution is hybrid: plugins that ship a
`Package.swift` are pulled in via Swift Package Manager, and plugins that
don't (e.g. `printing`, which still only publishes a Podspec/Podfile hook)
fall back to CocoaPods automatically. `flutter build ios --config-only`
drives that whole hybrid flow itself (including `pod install` when a
Podfile is present), so this script must NOT deintegrate CocoaPods or
delete the Podfile/Pods/workspace — doing so removes the only build path
for the CocoaPods-only plugins and breaks `GeneratedPluginRegistrant`
imports like `PrintingPlugin.h`. This script only disables code signing.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
IOS_DEPLOYMENT_TARGET = "15.0"


def bump_pbxproj_deployment_target() -> None:
    path = IOS / "Runner.xcodeproj/project.pbxproj"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    original = text
    text = re.sub(
        r"IPHONEOS_DEPLOYMENT_TARGET = \d+(?:\.\d+)?;",
        f"IPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET};",
        text,
    )
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Set IPHONEOS_DEPLOYMENT_TARGET = {IOS_DEPLOYMENT_TARGET} in {path}")


def patch_pbxproj_code_signing() -> None:
    """Disable signing on Runner target configs (not just strip DEVELOPMENT_TEAM)."""
    path = IOS / "Runner.xcodeproj/project.pbxproj"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    original = text

    text = re.sub(r"\t\t\t\tCODE_SIGN_STYLE = Automatic;\n", "", text)
    text = re.sub(r"\t\t\t\tCODE_SIGN_STYLE = Manual;\n", "", text)
    text = re.sub(r'\t\t\t\t"CODE_SIGN_IDENTITY\[sdk=iphoneos\*\]" = .*;\n', "", text)
    text = re.sub(r"\t\t\t\tCODE_SIGN_IDENTITY = .*;\n", "", text)

    signing_lines = (
        "\t\t\t\tCODE_SIGNING_ALLOWED = NO;\n"
        "\t\t\t\tCODE_SIGNING_REQUIRED = NO;\n"
        "\t\t\t\tCODE_SIGN_IDENTITY = \"\";\n"
        "\t\t\t\tEXPANDED_CODE_SIGN_IDENTITY = \"-\";\n"
    )

    def _inject_signing(match: re.Match[str]) -> str:
        block = match.group(0)
        if "PRODUCT_BUNDLE_IDENTIFIER" not in block:
            return block
        if "CODE_SIGNING_ALLOWED = NO" in block:
            return block
        return block.replace("\t\t\t};", signing_lines + "\t\t\t};", 1)

    text = re.sub(
        r"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{.*?\n\t\t\t\};",
        _inject_signing,
        text,
        flags=re.DOTALL,
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Patched Runner code signing in {path}")


def strip_pbxproj_signing() -> None:
    path = IOS / "Runner.xcodeproj/project.pbxproj"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    original = text
    text = re.sub(r"\t\t\t\tDEVELOPMENT_TEAM = .*;\n", "", text)
    text = re.sub(r'\t\t\t\t"DEVELOPMENT_TEAM\[sdk=iphoneos\*\]" = .*;\n', "", text)
    text = re.sub(r"\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = .*;\n", "", text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Stripped signing from {path}")


def main() -> None:
    bump_pbxproj_deployment_target()
    strip_pbxproj_signing()
    patch_pbxproj_code_signing()
    # Deliberately no CocoaPods deintegration here — see module docstring.
    # `flutter build ios --config-only` (run right after this script, in
    # build_ios_unsigned.sh) handles the hybrid SPM+CocoaPods resolution,
    # including `pod install` for plugins like `printing` that still only
    # ship a Podspec. Ripping out the Podfile/Pods/workspace here breaks
    # that plugin's build.
    print("iOS unsigned-build patches applied.")


if __name__ == "__main__":
    main()
