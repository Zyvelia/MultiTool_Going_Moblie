import 'dart:io';

/// What Health / Health Connect can do on this device & build.
abstract final class StepsHealthCapabilities {
  /// Full history sync needs Health Connect (Android) or HealthKit (iOS).
  ///
  /// HealthKit requires a **paid** Apple Developer Program membership and an
  /// App ID with HealthKit — not available on free / unsigned personal builds.
  /// Step counting on iPhone still works via **Core Motion** (pedometer) without it.
  static bool get healthSyncAvailable => Platform.isAndroid;

  static bool get isIosMotionOnly => Platform.isIOS;

  static String get iosMotionOnlyMessage =>
      'No paid Apple Developer account is needed for steps. '
      'This app uses the iPhone motion sensor (like StepsApp). '
      'Apple Health import needs HealthKit on a paid developer account — '
      'not used here.';
}
