import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'brick_breaker_game.dart';
import 'brick_breaker_mode.dart';

class BrickBreakerSave {
  static const version = 1;

  static Future<void> save(BrickBreakerMode mode, BrickBreakerGame game) async {
    if (game.phase == BreakerPhase.gameOver) {
      await clear(mode);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(mode.progressSaveKey, jsonEncode(game.toProgressJson()));
  }

  static Future<void> clear(BrickBreakerMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(mode.progressSaveKey);
  }

  static Future<bool> tryRestore(BrickBreakerMode mode, BrickBreakerGame game) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(mode.progressSaveKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final data = jsonDecode(raw);
      if (data is! Map<String, dynamic>) return false;
      return game.restoreFromProgress(data);
    } catch (_) {
      return false;
    }
  }
}
