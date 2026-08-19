#!/usr/bin/env python3
"""Patches the scaffolded ios/ folder after `flutter create`.

Run after `flutter pub get` (Podfile may not exist until then on newer Flutter):
    python scripts/patch_ios.py
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Standard Flutter Podfile — written when `flutter create` skips it (newer templates).
_PODFILE_TEMPLATE = """# Generated for CI when the scaffold omits ios/Podfile.
platform :ios, '13.0'

ENV['COCOAPODS_DISABLE_STATS'] = 'true'

project 'Runner', {
  'Debug' => :debug,
  'Profile' => :release,
  'Release' => :release,
}

def flutter_root
  generated_xcode_build_settings_path = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  unless File.exist?(generated_xcode_build_settings_path)
    raise "#{generated_xcode_build_settings_path} must exist. Run flutter pub get first"
  end

  File.foreach(generated_xcode_build_settings_path) do |line|
    matches = line.match(/FLUTTER_ROOT=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found in #{generated_xcode_build_settings_path}"
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
  end
end
"""


def patch_info_plist() -> None:
    path = ROOT / "ios/Runner/Info.plist"
    if not path.is_file():
        print(f"Skip Info.plist — not found: {path}")
        return

    plist = path.read_text(encoding="utf-8")

    blocks = [
        (
            "\t<key>UIBackgroundModes</key>\n"
            "\t<array>\n"
            "\t\t<string>audio</string>\n"
            "\t</array>\n"
        ),
        (
            "\t<key>NSLocalNetworkUsageDescription</key>\n"
            "\t<string>Used to find printers on your Wi-Fi network so notes can be printed.</string>\n"
            "\t<key>NSBonjourServices</key>\n"
            "\t<array>\n"
            "\t\t<string>_ipp._tcp</string>\n"
            "\t\t<string>_ipps._tcp</string>\n"
            "\t</array>\n"
        ),
    ]

    for block in blocks:
        if block.strip().split("\n")[0] in plist:
            continue
        plist, n = re.subn(r"(<dict>\n)", r"\1" + block, plist, count=1)
        if n == 0:
            raise SystemExit(f"Could not patch Info.plist block in {path}")

    path.write_text(plist, encoding="utf-8")
    print(f"Patched {path}")


def ensure_podfile() -> Path | None:
    path = ROOT / "ios/Podfile"
    if path.is_file():
        return path

    ios_dir = ROOT / "ios"
    if not ios_dir.is_dir():
        print("Skip Podfile — ios/ folder missing")
        return None

    generated = ROOT / "ios/Flutter/Generated.xcconfig"
    if not generated.is_file():
        print(
            "Skip Podfile — ios/Podfile missing and Flutter/Generated.xcconfig "
            "not found (run flutter pub get first)"
        )
        return None

    path.write_text(_PODFILE_TEMPLATE, encoding="utf-8")
    print(f"Created {path}")
    return path


def patch_podfile() -> None:
    path = ensure_podfile()
    if path is None:
        return

    text = path.read_text(encoding="utf-8")

    hook = """
    # Unsigned CI builds — pods must not require a Development Team.
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
        config.build_settings['CODE_SIGNING_IDENTITY'] = ''
      end
    end
"""

    if "pods must not require" in text:
        print(f"Podfile already patched: {path}")
        return

    marker = "post_install do |installer|"
    if marker not in text:
        raise SystemExit(f"Could not find {marker!r} in {path}")

    text = text.replace(marker, marker + hook, 1)
    path.write_text(text, encoding="utf-8")
    print(f"Patched {path}")


def patch_pbxproj() -> None:
    path = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    if not path.is_file():
        print(f"Skip pbxproj — not found: {path}")
        return

    text = path.read_text(encoding="utf-8")
    original = text

    text = re.sub(r"\t\t\t\tDEVELOPMENT_TEAM = .*;\n", "", text)
    text = re.sub(
        r"\t\t\t\t\"DEVELOPMENT_TEAM\[sdk=iphoneos\*\]\" = .*;\n",
        "",
        text,
    )
    text = re.sub(
        r"\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = .*;\n",
        "",
        text,
    )

    if text != original:
        path.write_text(text, encoding="utf-8")
        print(f"Patched {path}")
    else:
        print(f"No pbxproj signing changes needed: {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Patch scaffolded ios/ for CI builds")
    parser.add_argument(
        "--podfile-only",
        action="store_true",
        help="Only ensure/patch ios/Podfile (run after flutter pub get)",
    )
    args = parser.parse_args()

    if args.podfile_only:
        patch_podfile()
    else:
        patch_info_plist()
        patch_pbxproj()
        patch_podfile()

    print("iOS patches applied.")


if __name__ == "__main__":
    main()
