import 'package:flutter/material.dart';

/// Shared neon catalog palette: near-black charcoal, layered violet
/// surfaces and luminous accents.
class AppColors {
  AppColors._();

  /// Sky / scaffold — almost black with a wine undertone.
  static const Color bg = Color(0xFF090710);

  /// App bars, nav bar, mini players.
  static const Color surface = Color(0xFF151020);

  /// Cards, search fields, dialogs.
  static const Color card = Color(0xFF1C1429);

  /// HUD-style hairline borders.
  static const Color border = Color(0xFF392749);

  /// Moon / neon-sign magenta.
  static const Color accent = Color(0xFFB96BFF);

  /// Brighter bloom for labels and highlights.
  static const Color accentGlow = Color(0xFFD28AFF);

  /// Selected surfaces (nav indicator, pressed tiles).
  static const Color wine = Color(0xFF49216D);

  /// Dim magenta wash behind selected cards.
  static const Color accentMuted = Color(0xFF29183D);

  static const Color onSurface = Color(0xFFF8F2FF);
  static const Color muted = Color(0xFFB9AFCB);
}
