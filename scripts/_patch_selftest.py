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
    overlay = HERE / "android_overlay" / "kotlin" / "MainActivity.kt"
    kt = overlay.read_text(encoding="utf-8")
    assert "AudioServiceActivity" in kt
    assert "screen_security" not in kt
    assert "StepsGlanceWidget" in kt
    print("--- MainActivity.kt (overlay) ---")
    print(kt)


def test_ios() -> None:
    pi = load("patch_ios_appdelegate")
    text = APP_DELEGATE
    assert pi.RETURN_LINE in text
    out = text.replace(pi.RETURN_LINE, pi.RETURN_REPLACEMENT, 1)
    out = out.replace("import Flutter\n", "import Flutter\nimport FirebaseCore\n", 1)
    assert pi.MARKER in out
    assert "screen_security" not in out
    assert out.count("@objc class AppDelegate") == 1
    print("--- AppDelegate.swift ---")
    print(out)


if __name__ == "__main__":
    test_android()
    test_ios()
    print("Both native patches applied cleanly.")
