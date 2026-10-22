import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Syncs today's count for the Android home-screen widget (no Health signing).
class StepsWidgetBridge {
  StepsWidgetBridge._();

  static const _prefsKey = 'steps_widget_today';
  static const _channel = MethodChannel('com.zsmultitool/steps_widget');

  static Future<void> updateTodayCount(int steps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, '$steps');
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {
      // Widget optional — ignore on older builds.
    }
  }
}
