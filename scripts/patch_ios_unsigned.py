#!/usr/bin/env python3
"""Minimal iOS patches for unsigned CI builds (no flutter build ios)."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

_PODFILE_TEMPLATE = """platform :ios, '13.0'

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

_POD_SIGNING_HOOK = """
    # Unsigned CI — pods must not require a Development Team.
    installer.pods_project.targets.each do |target|
      target.build_configurations.each do |config|
        config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
        config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
        config.build_settings['CODE_SIGNING_IDENTITY'] = ''
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

    text = path.read_text(encoding="utf-8")
    if "Unsigned CI" in text:
        return
    marker = "post_install do |installer|"
    if marker not in text:
        raise SystemExit(f"Could not find post_install in {path}")
    path.write_text(text.replace(marker, marker + _POD_SIGNING_HOOK, 1), encoding="utf-8")
    print(f"Patched pod signing in {path}")


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
    strip_pbxproj_signing()
    print("iOS unsigned-build patches applied.")


if __name__ == "__main__":
    main()
