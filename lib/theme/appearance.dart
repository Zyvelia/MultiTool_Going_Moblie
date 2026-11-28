import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum NeonPreset {
  eclipse('Neon Eclipse', Color(0xFFB96BFF), Color(0xFF090710)),
  crimson('Crimson Void', Color(0xFFFF718C), Color(0xFF10070B)),
  midnight('Midnight Cyber', Color(0xFF51CCFF), Color(0xFF071019)),
  velvet('Velvet Ruins', Color(0xFFFF78D0), Color(0xFF110719)),
  amoled('AMOLED', Color(0xFFB96BFF), Colors.black);

  const NeonPreset(this.label, this.accent, this.background);
  final String label;
  final Color accent;
  final Color background;
}

@immutable
class Appearance extends ThemeExtension<Appearance> {
  const Appearance({
    this.preset = NeonPreset.eclipse,
    this.customAccent,
    this.glow = 0.45,
    this.glass = 0.65,
    this.animations = true,
  });

  final NeonPreset preset;
  final Color? customAccent;
  final double glow;
  final double glass;
  final bool animations;

  static Appearance of(BuildContext context) =>
      Theme.of(context).extension<Appearance>() ?? const Appearance();

  Color get accent => customAccent ?? preset.accent;
  Color get accentGlow => Color.lerp(accent, Colors.white, 0.24)!;
  Color get bg => preset.background;
  Color get surface => Color.alphaBlend(accent.withValues(alpha: 0.035 + glass * 0.045), bg);
  Color get card => Color.alphaBlend(accent.withValues(alpha: 0.055 + glass * 0.075), bg);
  Color get border => Color.alphaBlend(accent.withValues(alpha: 0.23), bg);
  Color get wine => Color.alphaBlend(accent.withValues(alpha: 0.36), bg);
  Color get accentMuted => Color.alphaBlend(accent.withValues(alpha: 0.17), bg);
  Color get onSurface => const Color(0xFFF8F2FF);
  Color get muted => const Color(0xFFC1B8CC);
  Color get onAccent => accent.computeLuminance() > 0.35 ? const Color(0xFF11091B) : Colors.white;

  @override
  Appearance copyWith({
    NeonPreset? preset,
    Color? customAccent,
    bool clearAccent = false,
    double? glow,
    double? glass,
    bool? animations,
  }) => Appearance(
    preset: preset ?? this.preset,
    customAccent: clearAccent ? null : customAccent ?? this.customAccent,
    glow: (glow ?? this.glow).clamp(0.0, 1.0),
    glass: (glass ?? this.glass).clamp(0.0, 1.0),
    animations: animations ?? this.animations,
  );

  @override
  Appearance lerp(covariant Appearance? other, double t) =>
      other == null || t < 0.5 ? this : other;

  Map<String, Object?> toJson() => {
    'preset': preset.name,
    'accent': customAccent?.toARGB32(),
    'glow': glow,
    'glass': glass,
    'animations': animations,
  };

  factory Appearance.fromJson(Map<String, dynamic> json) {
    final name = json['preset'];
    final preset = NeonPreset.values.where((p) => p.name == name).firstOrNull ?? NeonPreset.eclipse;
    final raw = json['accent'];
    final color = raw is int && raw >= 0 && raw <= 0xFFFFFFFF
        ? Color(raw | 0xFF000000) : null;
    double bounded(Object? v, double fallback) =>
        v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : fallback;
    return Appearance(
      preset: preset,
      customAccent: color,
      glow: bounded(json['glow'], 0.45),
      glass: bounded(json['glass'], 0.65),
      animations: json['animations'] is bool ? json['animations'] as bool : true,
    );
  }
}

class AppearanceController extends ValueNotifier<Appearance> {
  AppearanceController() : super(const Appearance());
  static final instance = AppearanceController();
  static const storageKey = 'appearance_studio_v1';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      if (saved != null) {
        value = Appearance.fromJson(Map<String, dynamic>.from(jsonDecode(saved) as Map));
      }
    } catch (error) {
      debugPrint('Appearance settings: $error');
    }
  }

  Future<void> apply(Appearance next) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(storageKey, jsonEncode(next.toJson()));
    if (!ok) throw StateError('Could not save appearance');
    value = next;
  }
}
