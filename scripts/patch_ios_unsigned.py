#!/usr/bin/env python3
"""Minimal iOS patches for unsigned CI builds (no flutter build ios)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS_DEPLOYMENT_TARGET = "15.0"

_PODFILE_TEMPLATE = f"""platform :ios, '{IOS_DEPLOYMENT_TARGET}'

ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {{
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{{generated_xcode_build_settings_path}} must exist. Run flutter pub get first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{{generated_xcode_build_settings_path}}"
end

require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)

flutter_ios_podfile_setup

target 'Runner' do
  use_frameworks!
  use_modular_headers!

  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '{IOS_DEPLOYMENT_TARGET}'
    end
  end
end
"""

_POD_SIGNING_HOOK = """
    # Unsigned CI — pods must not require a Development Team.
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
        config.build_settings['CODE_SIGNING_IDENTITY'] = ''
        config.build_settings['EXPANDED_CODE_SIGN_IDENTITY'] = '-'
      end
    end
"""

_DEPLOYMENT_TARGET_HOOK = f"""
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '{IOS_DEPLOYMENT_TARGET}'
      end
    end
"""


def ensure_podfile() -> None:
    path = ROOT / "ios/Podfile"
    if not path.is_file():
        if not (ROOT / "ios/Flutter/Generated.xcconfig").is_file():
            raise SystemExit("ios/Podfile missing — run flutter pub get first")
        path.write_text(_PODFILE_TEMPLATE, encoding="utf-8")
        print(f"Created {path}")
        return

    text = path.read_text(encoding="utf-8")
    original = text

    # Raise platform floor — Flutter stable requires >= 15.0 on recent Xcode.
    text = re.sub(
        r"^#?\s*platform\s+:ios,\s*['\"]?\d+(?:\.\d+)?['\"]?\s*$",
        f"platform :ios, '{IOS_DEPLOYMENT_TARGET}'",
        text,
        count=1,
        flags=re.MULTILINE,
    )
    if not re.search(r"^platform\s+:ios,", text, flags=re.MULTILINE):
        text = f"platform :ios, '{IOS_DEPLOYMENT_TARGET}'\n\n" + text

    if "IPHONEOS_DEPLOYMENT_TARGET" not in text and "post_install do |installer|" in text:
        text = text.replace(
            "post_install do |installer|",
            "post_install do |installer|" + _DEPLOYMENT_TARGET_HOOK,
            1,
        )

    if "Unsigned CI" not in text and "post_install do |installer|" in text:
        text = text.replace(
            "post_install do |installer|",
            "post_install do |installer|" + _POD_SIGNING_HOOK,
            1,
        )

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Patched {path} (platform {IOS_DEPLOYMENT_TARGET})")


def bump_pbxproj_deployment_target() -> None:
    path = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
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
    path = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    text = path.read_text(encoding="utf-8")
    original = text

    text = re.sub(r"\t\t\t\tCODE_SIGN_STYLE = Automatic;\n", "", text)
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
        return block.replace(
            "\t\t\t};",
            signing_lines + "\t\t\t};",
            1,
        )

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
    path = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    text = path.read_text(encoding="utf-8")
    original = text
    text = re.sub(r"\t\t\t\tDEVELOPMENT_TEAM = .*;\n", "", text)
    text = re.sub(r'\t\t\t\t"DEVELOPMENT_TEAM\[sdk=iphoneos\*\]" = .*;\n', "", text)
    text = re.sub(r"\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = .*;\n", "", text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Stripped signing from {path}")


def main() -> None:
    ensure_podfile()
    bump_pbxproj_deployment_target()
    strip_pbxproj_signing()
    patch_pbxproj_code_signing()
    print("iOS unsigned-build patches applied.")


if __name__ == "__main__":
    main()
