#!/usr/bin/env python3
"""Installs and registers Firebase's iOS client plist in the generated Runner project."""
from pathlib import Path
import re
import shutil
import secrets

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "firebase/GoogleService-Info.plist"
DEST = ROOT / "ios/Runner/GoogleService-Info.plist"
PBX = ROOT / "ios/Runner.xcodeproj/project.pbxproj"


def _uuid() -> str:
    return secrets.token_hex(12).upper()


def register_bundle_resource() -> None:
    if not PBX.is_file():
        raise SystemExit(f"{PBX} missing — run flutter create first")

    text = PBX.read_text(encoding="utf-8")
    if "GoogleService-Info.plist in Resources" in text:
        return

    file_ref = _uuid()
    build_file = _uuid()

    marker = "/* Begin PBXFileReference section */"
    start = text.find(marker)
    end = text.find("/* End PBXFileReference section */")
    if start < 0 or end < 0:
        raise SystemExit("Could not find PBXFileReference section")
    entry = (
        f"\t\t{file_ref} /* GoogleService-Info.plist */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = text.plist.xml; path = GoogleService-Info.plist; "
        f"sourceTree = \"<group>\"; }};\n"
    )
    text = text[:end] + entry + text[end:]

    marker = "/* Begin PBXBuildFile section */"
    start = text.find(marker)
    end = text.find("/* End PBXBuildFile section */")
    if start < 0 or end < 0:
        raise SystemExit("Could not find PBXBuildFile section")
    entry = (
        f"\t\t{build_file} /* GoogleService-Info.plist in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {file_ref} /* GoogleService-Info.plist */; }};\n"
    )
    text = text[:end] + entry + text[end:]

    # Add the file to the Runner group.
    runner_group = re.search(
        r'([0-9A-F]{24}) /\* Runner \*/ = \{\n'
        r'\s*isa = PBXGroup;\n'
        r'\s*children = \(\n(.*?)\n\s*\);\n'
        r'\s*path = Runner;',
        text,
        flags=re.DOTALL,
    )
    if not runner_group:
        raise SystemExit("Could not find the Runner PBXGroup")
    children = runner_group.group(2)
    replacement = runner_group.group(0).replace(
        children,
        children + f"\n\t\t\t\t{file_ref} /* GoogleService-Info.plist */;",
        1,
    )
    text = text[:runner_group.start()] + replacement + text[runner_group.end():]

    # Add it to the Runner Resources build phase.
    resource_phase = re.search(
        r'([0-9A-F]{24}) /\* Resources \*/ = \{\n'
        r'\s*isa = PBXResourcesBuildPhase;\n'
        r'\s*buildActionMask = 2147483647;\n'
        r'\s*files = \(\n(.*?)\n\s*\);',
        text,
        flags=re.DOTALL,
    )
    if not resource_phase:
        raise SystemExit("Could not find the Runner Resources build phase")
    files = resource_phase.group(2)
    replacement = resource_phase.group(0).replace(
        files,
        files + f"\n\t\t\t\t{build_file} /* GoogleService-Info.plist in Resources */;",
        1,
    )
    text = text[:resource_phase.start()] + replacement + text[resource_phase.end():]

    PBX.write_text(text, encoding="utf-8")
    print("Registered GoogleService-Info.plist in Runner resources.")


def main() -> None:
    if not SOURCE.is_file():
        print(f"Firebase config missing: {SOURCE}. FCM will remain disabled until it is added.")
        return

    DEST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE, DEST)
    register_bundle_resource()
    print(f"Installed Firebase iOS config at {DEST}")


if __name__ == "__main__":
    main()
