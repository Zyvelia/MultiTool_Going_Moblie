#!/usr/bin/env python3
"""Adds the screen-security channel to the scaffolded AppDelegate.swift.

CI regenerates ios/ with `flutter create` on every run, so this re-applies the
native half of `lib/services/screen_security_service.dart`.

iOS cannot prevent screen capture the way Android's FLAG_SECURE can. All this
provides is notification *after* a screenshot, plus the live recording/mirroring
state, so Dart can hide sensitive content itself.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_DELEGATE = ROOT / "ios/Runner/AppDelegate.swift"

MARKER = "zsmultitool/screen_security"

RETURN_LINE = (
    "    return super.application(application, didFinishLaunchingWithOptions: launchOptions)"
)

# Set up after super so the storyboard's FlutterViewController definitely exists.
RETURN_REPLACEMENT = """    let didFinishLaunching = super.application(
      application, didFinishLaunchingWithOptions: launchOptions)
    setUpScreenSecurity()
    return didFinishLaunching"""

METHOD = '''
  private var screenSecurityChannel: FlutterMethodChannel?

  private func setUpScreenSecurity() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("ScreenSecurity: no FlutterViewController, skipping")
      return
    }
    let channel = FlutterMethodChannel(
      name: "zsmultitool/screen_security",
      binaryMessenger: controller.binaryMessenger
    )
    screenSecurityChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "enable", "disable":
        // No iOS equivalent of FLAG_SECURE; monitoring is always on.
        result(true)
      case "isCaptured":
        result(UIScreen.main.isCaptured)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenSecurityChannel?.invokeMethod("screenshot", arguments: nil)
    }
    NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenSecurityChannel?.invokeMethod(
        "captureChanged", arguments: UIScreen.main.isCaptured)
    }
  }
'''


def main() -> None:
    if not APP_DELEGATE.is_file():
        raise SystemExit(f"{APP_DELEGATE} missing — run flutter create first")

    text = APP_DELEGATE.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"{APP_DELEGATE} already patched")
        return

    if RETURN_LINE not in text:
        raise SystemExit(f"Could not find the launch return in {APP_DELEGATE}")
    text = text.replace(RETURN_LINE, RETURN_REPLACEMENT, 1)

    closing = text.rstrip()
    if not closing.endswith("}"):
        raise SystemExit(f"Unexpected trailing content in {APP_DELEGATE}")
    text = closing[:-1].rstrip("\n") + "\n" + METHOD + "}\n"

    APP_DELEGATE.write_text(text, encoding="utf-8")
    print(f"Patched {APP_DELEGATE}")


if __name__ == "__main__":
    main()
