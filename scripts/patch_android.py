#!/usr/bin/env python3
"""Patches the scaffolded android/ folder after `flutter create`.

Run once after generating platform folders (CI does this automatically):
    python scripts/patch_android.py
"""
from __future__ import annotations

import glob
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def patch_manifest() -> None:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    xml = path.read_text(encoding="utf-8")
    perms = (
        '    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n'
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>\n'
    )
    xml, n = re.subn(r"(<manifest[^>]*>\n)", r"\1" + perms, xml, count=1)
    if n == 0:
        raise SystemExit(f"Could not patch permissions in {path}")
    path.write_text(xml, encoding="utf-8")
    print(f"Patched {path}")


def patch_main_activity() -> None:
    matches = glob.glob(str(ROOT / "android/app/src/main/kotlin/**/MainActivity.kt"), recursive=True)
    if not matches:
        raise SystemExit("Could not find MainActivity.kt")
    path = Path(matches[0])
    kt = path.read_text(encoding="utf-8")
    kt = kt.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import com.ryanheise.audioservice.AudioServiceActivity",
    )
    kt = kt.replace("class MainActivity: FlutterActivity()", "class MainActivity: AudioServiceActivity()")
    kt = kt.replace("class MainActivity : FlutterActivity()", "class MainActivity : AudioServiceActivity()")
    path.write_text(kt, encoding="utf-8")
    print(f"Patched {path}")


def patch_compile_sdk() -> None:
    path = ROOT / "android/app/build.gradle.kts"
    gradle = path.read_text(encoding="utf-8")
    gradle, n = re.subn(
        r"compileSdk\s*=\s*flutter\.compileSdkVersion",
        "compileSdk = 36",
        gradle,
    )
    if n == 0:
        raise SystemExit(f"Could not patch compileSdk in {path}")
    path.write_text(gradle, encoding="utf-8")
    print(f"Patched compileSdk in {path}")


def patch_built_in_kotlin() -> None:
    """Migrate the app module off the legacy kotlin-android plugin (AGP 9+)."""
    app_gradle = ROOT / "android/app/build.gradle.kts"
    text = app_gradle.read_text(encoding="utf-8")
    original = text

    text = re.sub(r'\s*id\("kotlin-android"\)\n', "\n", text)
    text = re.sub(r'\s*id\("org\.jetbrains\.kotlin\.android"\)\n', "\n", text)
    text = re.sub(
        r"\s*kotlinOptions\s*\{\s*jvmTarget\s*=\s*JavaVersion\.VERSION_17\.toString\(\)\s*\}\s*",
        "\n",
        text,
        flags=re.MULTILINE,
    )

    if "kotlin {" not in text and "compilerOptions" not in text:
        kotlin_block = """
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
"""
        text = text.rstrip() + "\n" + kotlin_block

    if text != original:
        app_gradle.write_text(text, encoding="utf-8")
        print(f"Migrated {app_gradle} to built-in Kotlin")

    props_path = ROOT / "android/gradle.properties"
    props = props_path.read_text(encoding="utf-8")
    lines = [ln for ln in props.splitlines() if not ln.startswith("android.builtInKotlin=")]
    lines.append("android.builtInKotlin=true")
    if not any(ln.startswith("android.newDsl=") for ln in lines):
        lines.append("android.newDsl=false")
    props_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Set android.builtInKotlin=true in {props_path}")


def main() -> None:
    patch_manifest()
    patch_main_activity()
    patch_compile_sdk()
    patch_built_in_kotlin()
    print("Android patches applied.")


if __name__ == "__main__":
    main()
