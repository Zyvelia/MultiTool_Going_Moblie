#!/usr/bin/env python3
"""Install and safely register Firebase's iOS plist in the generated Runner project."""
from __future__ import annotations
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "firebase/GoogleService-Info.plist"
DEST = ROOT / "ios/Runner/GoogleService-Info.plist"
PBX = ROOT / "ios/Runner.xcodeproj/project.pbxproj"

RUBY_SCRIPT = r'''
require 'xcodeproj'
project_path = ARGV.fetch(0)
plist_name = ARGV.fetch(1)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }
abort 'Runner target not found' unless target
runner_group = project.main_group.groups.find { |g| g.path.to_s == 'Runner' || g.name == 'Runner' }
runner_group ||= project.main_group
file_ref = runner_group.files.find { |f| f.path.to_s == plist_name }
file_ref ||= runner_group.new_file(plist_name)
resources = target.resources_build_phase
unless resources.files.any? { |bf| bf.file_ref && bf.file_ref.path.to_s == plist_name }
  resources.add_file_reference(file_ref)
end
project.save
puts "Registered #{plist_name} in Runner resources."
'''

def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Firebase config missing: {SOURCE}")
    if not PBX.is_file():
        raise SystemExit(f"{PBX} missing — run flutter create first")
    DEST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE, DEST)
    with tempfile.NamedTemporaryFile("w", suffix=".rb", delete=False, encoding="utf-8") as f:
        f.write(RUBY_SCRIPT)
        ruby_file = f.name
    try:
        result = subprocess.run(
            ["ruby", ruby_file, str(ROOT / "ios/Runner.xcodeproj"), "GoogleService-Info.plist"],
            cwd=ROOT, text=True, capture_output=True,
        )
        if result.returncode != 0:
            sys.stderr.write(result.stdout)
            sys.stderr.write(result.stderr)
            raise SystemExit("Could not register GoogleService-Info.plist with Xcode project")
        print(result.stdout.strip())
    finally:
        Path(ruby_file).unlink(missing_ok=True)
    print(f"Installed Firebase iOS config at {DEST}")

if __name__ == "__main__":
    main()
