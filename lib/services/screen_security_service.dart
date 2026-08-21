import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Screen-capture protection for sensitive screens.
///
/// The two platforms can offer genuinely different guarantees, and this class
/// does not paper over that:
///
///  * Android can actually *prevent* capture. [protect] sets `FLAG_SECURE`, so
///    screenshots and screen recordings are blocked outright.
///  * iOS has no equivalent. Nothing can stop a screenshot, so the best
///    available option is to notice it after the fact ([onScreenshot]) and to
///    know while a recording or AirPlay mirror is running ([isCaptured] /
///    [onCaptureChanged]) so the UI can hide itself.
///
/// Every call degrades to a no-op when the native side is missing, so the app
/// still runs against an unpatched platform project.
class ScreenSecurityService {
  ScreenSecurityService._();

  static final ScreenSecurityService instance = ScreenSecurityService._();

  static const _channel = MethodChannel('zsmultitool/screen_security');

  final _screenshot = StreamController<void>.broadcast();
  final _captureChanged = StreamController<bool>.broadcast();

  bool _handlerInstalled = false;
  bool _unavailable = false;

  /// Fires after the user takes a screenshot. iOS only — on Android capture is
  /// blocked instead, so there is nothing to report.
  Stream<void> get onScreenshot => _screenshot.stream;

  /// Fires when screen recording or mirroring starts or stops. iOS only.
  Stream<bool> get onCaptureChanged => _captureChanged.stream;

  void _ensureHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'screenshot':
          _screenshot.add(null);
        case 'captureChanged':
          _captureChanged.add(call.arguments == true);
      }
      return null;
    });
  }

  Future<T?> _invoke<T>(String method, [dynamic args]) async {
    if (_unavailable) return null;
    try {
      _ensureHandler();
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      // Platform project was generated without the patch; carry on unprotected.
      _unavailable = true;
      debugPrint('ScreenSecurity: native side unavailable, running unprotected');
      return null;
    } catch (e) {
      debugPrint('ScreenSecurity.$method failed: $e');
      return null;
    }
  }

  /// Blocks capture on Android. On iOS this only starts capture monitoring.
  Future<void> protect() async {
    await _invoke<bool>('enable');
  }

  /// Releases the Android block so the rest of the app stays screenshottable.
  Future<void> unprotect() async {
    await _invoke<bool>('disable');
  }

  /// Whether the screen is being recorded or mirrored right now. Always false
  /// on Android, where capture is prevented rather than observed.
  Future<bool> isCaptured() async => await _invoke<bool>('isCaptured') ?? false;
}
