#!/usr/bin/env python3
"""Patches the scaffolded ios/ folder after `flutter create`.

Run once after generating platform folders (CI does this automatically):
    python scripts/patch_ios.py
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def patch_info_plist() -> None:
    path = ROOT / "ios/Runner/Info.plist"
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


def patch_podfile() -> None:
    path = ROOT / "ios/Podfile"
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
    """Keep Runner on Automatic signing — xcodebuild overrides handle CI."""
    path = ROOT / "ios/Runner.xcodeproj/project.pbxproj"
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
    patch_info_plist()
    patch_podfile()
    patch_pbxproj()
    print("iOS patches applied.")


if __name__ == "__main__":
    main()
