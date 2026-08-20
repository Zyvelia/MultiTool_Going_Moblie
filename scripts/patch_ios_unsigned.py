#!/usr/bin/env python3
"""Patches for unsigned iOS CI builds (no Apple Developer team).

Flutter 3.47+ ships iOS plugins as Swift Packages. Legacy CocoaPods
integration from `flutter create` triggers Manifest.lock drift on CI.
This script deintegrates CocoaPods and disables code signing on Runner.
"""
from __future__ import annotations

import re
import shutil
import subprocess
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


def _scrub_cocoapods_from_pbxproj() -> None:
    """Remove CocoaPods build phases + xcconfig refs left after deintegrate."""
    path = IOS / "Runner.xcodeproj/project.pbxproj"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    original = text

    text = re.sub(
        r"\t\t[A-F0-9]{24} /\* \[CP\] [^\n]+ \*/ = \{.*?\n\t\t\};\n",
        "",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(
        r"\t\t\t\t[A-F0-9]{24} /\* \[CP\] [^\n]+ \*/,\n",
        "",
        text,
    )
    text = re.sub(
        r'\t\t\tbaseConfigurationReference = [A-F0-9]{24} /\* Pods-Runner\.[^"]+\.xcconfig \*/;\n',
        "",
        text,
    )
    text = re.sub(
        r'\t\t\tbaseConfigurationReference = [A-F0-9]{24} /\* Pods-RunnerTests\.[^"]+\.xcconfig \*/;\n',
        "",
        text,
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Scrubbed CocoaPods references from {path}")


def deintegrate_cocoapods() -> None:
    """Drop CocoaPods — Flutter 3.47+ plugins here are Swift Packages."""
    podfile = IOS / "Podfile"
    if not podfile.is_file():
        _scrub_cocoapods_from_pbxproj()
        return

    try:
        result = subprocess.run(
            ["pod", "deintegrate"],
            cwd=IOS,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            print("pod deintegrate OK")
        else:
            print(f"pod deintegrate exit {result.returncode}: {result.stderr or result.stdout}")
    except FileNotFoundError:
        print("pod CLI not found — scrubbing project manually")

    _scrub_cocoapods_from_pbxproj()

    for rel in ("Podfile", "Podfile.lock"):
        p = IOS / rel
        if p.is_file():
            p.unlink()
            print(f"Removed {p}")

    pods_dir = IOS / "Pods"
    if pods_dir.is_dir():
        shutil.rmtree(pods_dir)
        print(f"Removed {pods_dir}")

    workspace = IOS / "Runner.xcworkspace"
    if workspace.is_dir():
        shutil.rmtree(workspace)
        print(f"Removed {workspace}")


def main() -> None:
    bump_pbxproj_deployment_target()
    strip_pbxproj_signing()
    patch_pbxproj_code_signing()
    deintegrate_cocoapods()
    print("iOS unsigned-build patches applied.")


if __name__ == "__main__":
    main()
