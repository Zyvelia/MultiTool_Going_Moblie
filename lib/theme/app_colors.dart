import 'package:flutter/material.dart';

/// Palette sampled from the cyberpunk HUD artwork: near-black void,
/// dark wine midtones, and glowing neon magenta.
class AppColors {
  AppColors._();

  /// Sky / scaffold — almost black with a wine undertone.
  static const Color bg = Color(0xFF070309);

  /// App bars, nav bar, mini players.
  static const Color surface = Color(0xFF10060C);

  /// Cards, search fields, dialogs.
  static const Color card = Color(0xFF1A0A12);

  /// HUD-style hairline borders.
  static const Color border = Color(0xFF3A1524);

  /// Moon / neon-sign magenta.
  static const Color accent = Color(0xFFFF2D95);

  /// Brighter bloom for labels and highlights.
  static const Color accentGlow = Color(0xFFFF4DA8);

  /// Selected surfaces (nav indicator, pressed tiles).
  static const Color wine = Color(0xFF4A0A28);

  /// Dim magenta wash behind selected cards.
  static const Color accentMuted = Color(0xFF2A0C1A);

  static const Color onSurface = Color(0xFFF5E6EE);
  static const Color muted = Color(0xFFC9A3B4);
}
