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
    # flutter_secure_storage v10+ — Google Drive backup can break key unwrap.
    xml, n2 = re.subn(
        r'(<application)(\s[^>]*)?>',
        r'\1\2 android:allowBackup="false">',
        xml,
        count=1,
    )
    if n2 == 0:
        raise SystemExit(f"Could not patch allowBackup in {path}")
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
    kt = kt.replace("class MainActivity: FlutterActivity()", "class MainActivity : AudioServiceActivity()")
    kt = kt.replace("class MainActivity : FlutterActivity()", "class MainActivity : AudioServiceActivity()")

    kt = _add_screen_security(kt, path)
    path.write_text(kt, encoding="utf-8")
    print(f"Patched {path}")


# FLAG_SECURE is a window-level flag, so it is toggled per screen from Dart
# rather than pinned on at launch -- otherwise the whole app, games included,
# becomes unscreenshottable.
_SECURITY_BODY = """ {
    private val screenSecurityChannel = "zsmultitool/screen_security"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            screenSecurityChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enable" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                "disable" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(true)
                }
                // Android blocks capture outright, so there is never anything
                // in progress to report back.
                "isCaptured" -> result.success(false)
                else -> result.notImplemented()
            }
        }
    }
}
"""


def _add_screen_security(kt: str, path: Path) -> str:
    if "screen_security" in kt:
        return kt

    imports = (
        "import android.view.WindowManager\n"
        "import io.flutter.embedding.engine.FlutterEngine\n"
        "import io.flutter.plugin.common.MethodChannel\n"
    )
    kt, n = re.subn(
        r"(import com\.ryanheise\.audioservice\.AudioServiceActivity\n)",
        r"\1" + imports,
        kt,
        count=1,
    )
    if n == 0:
        raise SystemExit(f"Could not add screen-security imports to {path}")

    # `flutter create` emits a bodyless class; give it one.
    kt, n = re.subn(
        r"class MainActivity : AudioServiceActivity\(\)\s*(\{\s*\})?\s*$",
        "class MainActivity : AudioServiceActivity()" + _SECURITY_BODY,
        kt.rstrip() + "\n",
        count=1,
        flags=re.MULTILINE,
    )
    if n == 0:
        raise SystemExit(f"Could not add screen-security channel to {path}")
    return kt


def patch_compile_sdk() -> None:
    path = ROOT / "android/app/build.gradle.kts"
    gradle = path.read_text(encoding="utf-8")
    gradle, n = re.subn(
        r"compileSdk\s*=\s*flutter\.compileSdkVersion",
        "compileSdk = 37",
        gradle,
    )
    if n == 0:
        raise SystemExit(f"Could not patch compileSdk in {path}")
    path.write_text(gradle, encoding="utf-8")
    print(f"Patched compileSdk in {path}")


def patch_core_library_desugaring() -> None:
    """flutter_local_notifications requires Java 8+ core library desugaring
    to be enabled on :app, or the release build fails at
    :app:checkReleaseAarMetadata with "requires core library desugaring to
    be enabled". Two parts: flip the compileOptions flag, and add the
    desugar_jdk_libs dependency that flag needs at compile time."""
    path = ROOT / "android/app/build.gradle.kts"
    gradle = path.read_text(encoding="utf-8")
    original = gradle

    if "isCoreLibraryDesugaringEnabled" not in gradle:
        gradle, n = re.subn(
            r"(compileOptions\s*\{)",
            r"\1\n        isCoreLibraryDesugaringEnabled = true",
            gradle,
            count=1,
        )
        if n == 0:
            raise SystemExit(f"Could not enable core library desugaring in {path}")

    if "desugar_jdk_libs" not in gradle:
        dep_line = '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n'
        gradle, n = re.subn(
            r"(dependencies\s*\{)",
            r"\1\n" + dep_line,
            gradle,
            count=1,
        )
        if n == 0:
            raise SystemExit(f"Could not add coreLibraryDesugaring dependency in {path}")

    if gradle != original:
        path.write_text(gradle, encoding="utf-8")
        print(f"Enabled core library desugaring in {path}")


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
    patch_core_library_desugaring()
    patch_built_in_kotlin()
    print("Android patches applied.")


if __name__ == "__main__":
    main()
