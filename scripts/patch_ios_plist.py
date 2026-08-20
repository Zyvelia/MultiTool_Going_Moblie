#!/usr/bin/env python3
"""One-shot Info.plist patches for the mobile app (CI scaffolds ios/ each run)."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / "ios/Runner/Info.plist"


def _insert_after_dict_open(text: str, block: str) -> str:
    needle = "<dict>\n"
    if block.strip() in text:
        return text
    if needle not in text:
        raise SystemExit(f"Could not patch {PLIST}")
    return text.replace(needle, needle + block, 1)


def main() -> None:
    if not PLIST.is_file():
        raise SystemExit(f"{PLIST} missing — run flutter create first")

    text = PLIST.read_text(encoding="utf-8")

    text = _insert_after_dict_open(
        text,
        "\t<key>UIBackgroundModes</key>\n"
        "\t<array>\n"
        "\t\t<string>audio</string>\n"
        "\t</array>\n",
    )

    text = _insert_after_dict_open(
        text,
        "\t<key>NSLocalNetworkUsageDescription</key>\n"
        "\t<string>Used to find printers on your Wi-Fi network so notes can be printed.</string>\n"
        "\t<key>NSBonjourServices</key>\n"
        "\t<array>\n"
        "\t\t<string>_ipp._tcp</string>\n"
        "\t\t<string>_ipps._tcp</string>\n"
        "\t</array>\n",
    )

    text = _insert_after_dict_open(
        text,
        "\t<key>NSPhotoLibraryAddUsageDescription</key>\n"
        "\t<string>Save photos and videos received from your PC via Quick Send.</string>\n"
        "\t<key>NSPhotoLibraryUsageDescription</key>\n"
        "\t<string>Pick photos to send to your PC via Quick Send.</string>\n",
    )

    PLIST.write_text(text, encoding="utf-8")
    print(f"Patched {PLIST}")


if __name__ == "__main__":
    main()
