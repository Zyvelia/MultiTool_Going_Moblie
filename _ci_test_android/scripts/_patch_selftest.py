#!/usr/bin/env python3
"""Dry-run the native patches against the stock `flutter create` templates."""
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent

MAIN_ACTIVITY = """package com.zsmultitool.multi_tool_remote

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
"""

APP_DELEGATE = """import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
"""


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def test_android() -> None:
    pa = load("patch_android")
    kt = MAIN_ACTIVITY
    kt = kt.replace(
        "import io.flutter.embedding.android.FlutterActivity",
        "import com.ryanheise.audioservice.AudioServiceActivity",
    )
    kt = kt.replace(
        "class MainActivity : FlutterActivity()",
        "class MainActivity : AudioServiceActivity()",
    )
    out = pa._add_screen_security(kt, Path("MainActivity.kt"))
    assert "zsmultitool/screen_security" in out
    assert "FLAG_SECURE" in out
    assert "import android.view.WindowManager" in out
    assert out.count("class MainActivity") == 1
    assert out.rstrip().endswith("}")
    # Re-running must be a no-op.
    assert pa._add_screen_security(out, Path("MainActivity.kt")) == out
    print("--- MainActivity.kt ---")
    print(out)


def test_ios() -> None:
    pi = load("patch_ios_appdelegate")
    text = APP_DELEGATE
    assert pi.RETURN_LINE in text
    text = text.replace(pi.RETURN_LINE, pi.RETURN_REPLACEMENT, 1)
    closing = text.rstrip()
    assert closing.endswith("}")
    out = closing[:-1].rstrip("\n") + "\n" + pi.METHOD + "}\n"
    assert pi.MARKER in out
    assert out.count("func setUpScreenSecurity") == 1
    assert out.count("@objc class AppDelegate") == 1
    assert out.rstrip().endswith("}")
    print("--- AppDelegate.swift ---")
    print(out)


if __name__ == "__main__":
    test_android()
    test_ios()
    print("Both native patches applied cleanly.")
