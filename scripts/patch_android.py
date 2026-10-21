#!/usr/bin/env python3
"""Patches the scaffolded android/ folder after `flutter create`.

Run once after generating platform folders (CI does this automatically):
    python scripts/patch_android.py
"""
from __future__ import annotations

import glob
import re
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent.parent


def patch_manifest() -> None:
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    xml = path.read_text(encoding="utf-8")
    perms = (
        '    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n'
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
        '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>\n'
        '    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>\n'
        '    <uses-permission android:name="android.permission.USE_EXACT_ALARM"/>\n'
        '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
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


def patch_notification_receivers() -> None:
    """flutter_local_notifications needs boot + scheduled receivers or alarms
    never fire after reboot / package update."""
    path = ROOT / "android/app/src/main/AndroidManifest.xml"
    xml = path.read_text(encoding="utf-8")
    marker = "ZS_FLUTTER_LOCAL_NOTIFICATIONS"
    if marker in xml:
        print(f"Notification receivers already in {path}")
        return
    block = (
        f"        <!-- {marker} -->\n"
        '        <receiver android:exported="false" '
        'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n'
        '        <receiver android:exported="false" '
        'android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n'
        "            <intent-filter>\n"
        '                <action android:name="android.intent.action.BOOT_COMPLETED"/>\n'
        '                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>\n'
        '                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>\n'
        '                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>\n'
        "            </intent-filter>\n"
        "        </receiver>\n"
    )
    xml, n = re.subn(r"(</application>)", block + r"\1", xml, count=1)
    if n == 0:
        raise SystemExit(f"Could not add notification receivers in {path}")
    path.write_text(xml, encoding="utf-8")
    print(f"Patched notification receivers in {path}")


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
    if re.search(r"compileSdk\s*=\s*37\b", gradle):
        print(f"compileSdk already 37 in {path}")
        return
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
            # Current `flutter create` templates don't always emit an
            # empty `dependencies {}` stub — nothing to inject into, so
            # append a fresh block at the end of the file instead of
            # hard-failing.
            gradle = gradle.rstrip() + "\n\ndependencies {\n" + dep_line + "}\n"
            print(f"No dependencies {{}} block found in {path} - appended a new one")

    if gradle != original:
        path.write_text(gradle, encoding="utf-8")
        print(f"Enabled core library desugaring in {path}")


def _set_gradle_property(props_path: Path, key: str, value: str) -> None:
    lines = [
        ln
        for ln in props_path.read_text(encoding="utf-8").splitlines()
        if not ln.startswith(f"{key}=")
    ]
    lines.append(f"{key}={value}")
    props_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def _strip_zs_compile_sdk_patch(text: str) -> str:
    for marker in ("// ZS_PLUGIN_COMPILE_SDK_PATCH", "// ZS_PLUGIN_COMPILE_SDK_APPLY"):
        if marker in text:
            text = text[: text.index(marker)].rstrip() + "\n"
    lines = [
        ln
        for ln in text.splitlines()
        if 'apply(from = "zs_plugin_compile_sdk.gradle")' not in ln
    ]
    return "\n".join(lines).strip() + "\n"


_ZS_PLUGIN_COMPILE_SDK_GRADLE = """\
// ZS_PLUGIN_COMPILE_SDK_PATCH — Groovy (settings.gradle.kts cannot use Kotlin beforeProject).
gradle.beforeProject { project ->
    if (project == project.rootProject) {
        return
    }
    project.pluginManager.withPlugin("com.android.library") {
        def android = project.extensions.findByName("android")
        if (android != null) {
            try {
                android.compileSdk = 37
            } catch (Throwable ignored) {
                try {
                    android.compileSdkVersion = 37
                } catch (Throwable ignored2) {
                }
            }
        }
    }
}
"""

_BUILD_GRADLE_HEADER = '''@file:Suppress("DEPRECATION")

import com.android.build.gradle.LibraryExtension

// ZS_PLUGIN_COMPILE_SDK_PATCH
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<LibraryExtension>("android") {
            compileSdk = 37
        }
    }
}

'''


def patch_plugin_compile_sdk() -> None:
    """Raise compileSdk for Android library plugins (flutter_webrtc still uses API 31)."""
    gradle_helper = ROOT / "android/zs_plugin_compile_sdk.gradle"
    gradle_helper.write_text(_ZS_PLUGIN_COMPILE_SDK_GRADLE, encoding="utf-8")

    settings = ROOT / "android/settings.gradle.kts"
    if not settings.is_file():
        raise SystemExit(f"Missing {settings} — run flutter create first.")
    st = _strip_zs_compile_sdk_patch(settings.read_text(encoding="utf-8"))
    if "// ZS_PLUGIN_COMPILE_SDK_APPLY" not in st:
        st = st.rstrip() + "\n\n// ZS_PLUGIN_COMPILE_SDK_APPLY\n"
        st += 'apply(from = "zs_plugin_compile_sdk.gradle")\n'
    settings.write_text(st, encoding="utf-8")

    build_gradle = ROOT / "android/build.gradle.kts"
    if not build_gradle.is_file():
        raise SystemExit(f"Missing {build_gradle} — run flutter create first.")
    text = _strip_zs_compile_sdk_patch(build_gradle.read_text(encoding="utf-8"))
    if "// ZS_PLUGIN_COMPILE_SDK_PATCH" not in text:
        text = _BUILD_GRADLE_HEADER + text.lstrip()
    build_gradle.write_text(text, encoding="utf-8")
    print("Patched plugin compileSdk (zs_plugin_compile_sdk.gradle + build.gradle.kts)")


def patch_agp_kotlin_compat() -> None:
    """AGP 9+ defaults to built-in Kotlin; many Flutter plugins still apply kotlin-android.

    Flutter's template already sets android.builtInKotlin=false. An older version of
    this patch script flipped it to true, which breaks audio_service / WebRTC builds.
    """
    props_path = ROOT / "android/gradle.properties"
    if not props_path.is_file():
        raise SystemExit(f"Missing {props_path} — run flutter create first.")
    _set_gradle_property(props_path, "android.builtInKotlin", "false")
    _set_gradle_property(props_path, "android.newDsl", "false")
    print(f"Set android.builtInKotlin=false in {props_path}")

    app_gradle = ROOT / "android/app/build.gradle.kts"
    text = app_gradle.read_text(encoding="utf-8")
    # Remove legacy built-in-Kotlin block if a previous patch run added it.
    text = re.sub(
        r"\nkotlin\s*\{\s*compilerOptions\s*\{[^}]*\}\s*\}\s*",
        "\n",
        text,
        flags=re.DOTALL,
    )
    app_gradle.write_text(text, encoding="utf-8")

    settings = ROOT / "android/settings.gradle.kts"
    if settings.is_file():
        st = settings.read_text(encoding="utf-8")
        if "org.jetbrains.kotlin.android" not in st and "plugins {" in st:
            st = st.replace(
                "plugins {\n",
                'plugins {\n    id("org.jetbrains.kotlin.android") version "2.4.0" apply false\n',
                1,
            )
            settings.write_text(st, encoding="utf-8")
            print(f"Added Kotlin Gradle plugin to {settings}")


def patch_firebase() -> None:
    source = ROOT / "firebase/google-services.json"
    destination = ROOT / "android/app/google-services.json"
    if not source.is_file():
        print(f"Firebase config missing: {source}. FCM will remain disabled until it is added.")
        return

    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)

    settings = ROOT / "android/settings.gradle.kts"
    if settings.is_file():
        text = settings.read_text(encoding="utf-8")
        if 'id("com.google.gms.google-services")' not in text and "plugins {" in text:
            text = text.replace(
                "plugins {\n",
                'plugins {\n    id("com.google.gms.google-services") version "4.4.4" apply false\n',
                1,
            )
            settings.write_text(text, encoding="utf-8")

    app = ROOT / "android/app/build.gradle.kts"
    if app.is_file():
        text = app.read_text(encoding="utf-8")
        if 'id("com.google.gms.google-services")' not in text and "plugins {" in text:
            text = text.replace(
                "plugins {\n",
                'plugins {\n    id("com.google.gms.google-services")\n',
                1,
            )
            app.write_text(text, encoding="utf-8")

    print(f"Installed Firebase Android config at {destination}")


def main() -> None:
    patch_firebase()
    patch_manifest()
    patch_notification_receivers()
    patch_main_activity()
    patch_compile_sdk()
    patch_plugin_compile_sdk()
    patch_core_library_desugaring()
    patch_agp_kotlin_compat()
    print("Android patches applied.")


if __name__ == "__main__":
    main()
