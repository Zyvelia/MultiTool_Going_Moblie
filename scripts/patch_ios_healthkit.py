#!/usr/bin/env python3
"""HealthKit entitlements for the Steps tab (no manual Xcode capability click).

Writes Runner/Runner.entitlements and wires CODE_SIGN_ENTITLEMENTS in
Runner.xcodeproj. Info.plist usage strings live in patch_ios_plist.py.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IOS = ROOT / "ios"
ENTITLEMENTS = IOS / "Runner/Runner.entitlements"
PBXPROJ = IOS / "Runner.xcodeproj/project.pbxproj"

# Stable ID for pbxproj file reference (must be unique in project).
_ENTITLEMENTS_FILE_REF = "ZS7HKENT2D6B9E4300551983"

_ENTITLEMENTS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
\t<key>com.apple.developer.healthkit</key>
\t<true/>
</dict>
</plist>
"""


def write_entitlements() -> None:
    ENTITLEMENTS.parent.mkdir(parents=True, exist_ok=True)
    ENTITLEMENTS.write_text(_ENTITLEMENTS_XML, encoding="utf-8")
    print(f"Wrote {ENTITLEMENTS}")


def patch_pbxproj() -> None:
    if not PBXPROJ.is_file():
        print(f"Skip HealthKit pbxproj (no {PBXPROJ})")
        return
    text = PBXPROJ.read_text(encoding="utf-8")
    original = text

    if "Runner.entitlements" not in text:
        file_ref = (
            f"\t\t{_ENTITLEMENTS_FILE_REF} /* Runner.entitlements */ = "
            "{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; "
            "path = Runner.entitlements; sourceTree = \"<group>\"; };\n"
        )
        text, n = re.subn(
            r"/\* End PBXFileReference section \*/",
            file_ref + "/* End PBXFileReference section */",
            text,
            count=1,
        )
        if n == 0:
            raise SystemExit(f"Could not add Runner.entitlements file ref in {PBXPROJ}")

        # Add to Runner group (first group with path = Runner).
        runner_group = re.search(
            r"(/\* Runner \*/ = \{\s*isa = PBXGroup;\s*children = \(\s*)",
            text,
        )
        if not runner_group:
            raise SystemExit(f"Could not find Runner PBXGroup in {PBXPROJ}")
        insert = f"{runner_group.group(1)}\n\t\t\t\t{_ENTITLEMENTS_FILE_REF} /* Runner.entitlements */,"
        text = text[: runner_group.start()] + insert + text[runner_group.end() :]

    entitlements_line = "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n"

    def _add_entitlements_to_runner_target(match: re.Match[str]) -> str:
        block = match.group(0)
        if "CODE_SIGN_ENTITLEMENTS" in block:
            return block
        if "INFOPLIST_FILE = Runner/Info.plist" not in block:
            return block
        return block.replace(
            "INFOPLIST_FILE = Runner/Info.plist;\n",
            "INFOPLIST_FILE = Runner/Info.plist;\n" + entitlements_line,
        )

    text = re.sub(
        r"\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = \{.*?\n\t\t\t\};",
        _add_entitlements_to_runner_target,
        text,
        flags=re.DOTALL,
    )

    if text != original:
        PBXPROJ.write_text(text, encoding="utf-8")
        print(f"Patched HealthKit entitlements path in {PBXPROJ}")
    else:
        print(f"HealthKit pbxproj already configured ({PBXPROJ})")


def main() -> None:
    write_entitlements()
    patch_pbxproj()
    print("iOS HealthKit patch applied.")


if __name__ == "__main__":
    main()
