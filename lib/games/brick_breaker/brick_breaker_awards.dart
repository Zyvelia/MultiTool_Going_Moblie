import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BrickBreakerAwardTier {
  final String id;
  final String name;
  final String icon;
  final int minScore;
  final int color;
  final bool secret;

  const BrickBreakerAwardTier({
    required this.id,
    required this.name,
    required this.icon,
    required this.minScore,
    required this.color,
    this.secret = false,
  });
}

class BrickBreakerAwardStats {
  int bestTierIndex;
  int fullClearCount;
  int bestScore;
  bool surprise9999;

  BrickBreakerAwardStats({
    this.bestTierIndex = -1,
    this.fullClearCount = 0,
    this.bestScore = 0,
    this.surprise9999 = false,
  });

  Map<String, dynamic> toJson() => {
        'bestTierIndex': bestTierIndex,
        'fullClearCount': fullClearCount,
        'bestScore': bestScore,
        'surprise9999': surprise9999,
      };

  factory BrickBreakerAwardStats.fromJson(Map<String, dynamic> json) {
    return BrickBreakerAwardStats(
      bestTierIndex: json['bestTierIndex'] as int? ?? -1,
      fullClearCount: json['fullClearCount'] as int? ?? 0,
      bestScore: (json['bestScore'] as num?)?.toInt() ??
          (json['bestClearLevel'] as num?)?.toInt() ??
          0,
      surprise9999: json['surprise9999'] as bool? ?? false,
    );
  }
}

class BrickBreakerScoreAward {
  final bool fullClear;
  final int score;
  final BrickBreakerAwardTier tier;
  final int tierIndex;
  final bool isNew;
  final bool surprise;
  final int totalClears;

  const BrickBreakerScoreAward({
    this.fullClear = false,
    required this.score,
    required this.tier,
    required this.tierIndex,
    required this.isNew,
    required this.surprise,
    this.totalClears = 0,
  });
}

class BrickBreakerAwards {
  static const _prefsKey = 'zs_brick_breaker_awards';

  static const tiers = <BrickBreakerAwardTier>[
    BrickBreakerAwardTier(id: 'wood', name: 'Wood', icon: '🪵', minScore: 500, color: 0xFF8B6914),
    BrickBreakerAwardTier(id: 'iron', name: 'Iron', icon: '⚙️', minScore: 1500, color: 0xFFB8B8B8),
    BrickBreakerAwardTier(id: 'gold', name: 'Gold', icon: '🪙', minScore: 3500, color: 0xFFFFD54F),
    BrickBreakerAwardTier(id: 'diamond', name: 'Diamond', icon: '💎', minScore: 7500, color: 0xFF80D8FF),
    BrickBreakerAwardTier(id: 'emerald', name: 'Emerald', icon: '🟢', minScore: 15000, color: 0xFF69F0AE),
    BrickBreakerAwardTier(id: 'ruby', name: 'Ruby', icon: '❤️', minScore: 30000, color: 0xFFFF5252),
    BrickBreakerAwardTier(id: 'sapphire', name: 'Sapphire', icon: '🔹', minScore: 60000, color: 0xFF448AFF),
    BrickBreakerAwardTier(id: 'platinum', name: 'Platinum', icon: '⭐', minScore: 120000, color: 0xFFE0E0E0),
    BrickBreakerAwardTier(id: 'obsidian', name: 'Obsidian', icon: '⚫', minScore: 250000, color: 0xFF7C4DFF),
    BrickBreakerAwardTier(id: 'netherite', name: 'Netherite', icon: '🔥', minScore: 500000, color: 0xFF5D4037),
    BrickBreakerAwardTier(id: 'cosmic', name: 'Cosmic', icon: '🌌', minScore: 1000000, color: 0xFFEA80FC),
    BrickBreakerAwardTier(id: 'void', name: 'Void', icon: '🌑', minScore: 2500000, color: 0xFF311B92),
    BrickBreakerAwardTier(
      id: 'transcendent',
      name: 'Transcendent',
      icon: '✨',
      minScore: 9999999,
      color: 0xFFFFF176,
      secret: true,
    ),
  ];

  static int tierIndexForScore(int score) {
    var idx = -1;
    for (var i = 0; i < tiers.length; i++) {
      if (score >= tiers[i].minScore) idx = i;
    }
    return idx;
  }

  static BrickBreakerAwardTier tierForScore(int score) {
    final idx = tierIndexForScore(score);
    return idx >= 0 ? tiers[idx] : tiers.first;
  }

  static String formatScore(int score) {
    final v = score < 0 ? 0 : score;
    if (v >= 1000000) {
      final m = v / 1000000;
      return v >= 10000000 ? '${m.round()}M' : '${m.toStringAsFixed(1)}M';
    }
    if (v >= 10000) return '${(v / 1000).round()}k';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return '$v';
  }

  static Future<BrickBreakerAwardStats> loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return BrickBreakerAwardStats();
    try {
      return BrickBreakerAwardStats.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return BrickBreakerAwardStats();
    }
  }

  static Future<void> saveStats(BrickBreakerAwardStats stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(stats.toJson()));
  }

  static Future<BrickBreakerScoreAward> _applyScore(
    BrickBreakerAwardStats data,
    int score,
  ) async {
    final pts = score < 0 ? 0 : score;
    final idx = tierIndexForScore(pts);
    final tier = idx >= 0 ? tiers[idx] : tiers.first;
    final isNew = idx > data.bestTierIndex;
    final firstSurprise = pts >= 9999999 && !data.surprise9999;

    if (pts > data.bestScore) data.bestScore = pts;
    if (idx > data.bestTierIndex) data.bestTierIndex = idx;
    if (firstSurprise) data.surprise9999 = true;
    await saveStats(data);

    return BrickBreakerScoreAward(
      score: pts,
      tier: tier,
      tierIndex: idx,
      isNew: isNew,
      surprise: firstSurprise,
    );
  }

  static Future<BrickBreakerScoreAward?> updateScore(int score) async {
    final data = await loadStats();
    final prevIdx = data.bestTierIndex;
    final out = await _applyScore(data, score);
    if (!out.isNew && out.tierIndex <= prevIdx) return null;
    return out;
  }

  static Future<BrickBreakerScoreAward> recordFullClear(int score) async {
    final data = await loadStats();
    data.fullClearCount++;
    await saveStats(data);
    final out = await _applyScore(await loadStats(), score);
    return BrickBreakerScoreAward(
      fullClear: true,
      score: out.score,
      tier: out.tier,
      tierIndex: out.tierIndex,
      isNew: out.isNew,
      surprise: out.surprise,
      totalClears: data.fullClearCount,
    );
  }

  static Future<BrickBreakerAwardTier?> getBestTier() async {
    final data = await loadStats();
    if (data.bestTierIndex < 0 || data.bestTierIndex >= tiers.length) return null;
    return tiers[data.bestTierIndex];
  }

  static List<BrickBreakerAwardTier> tiersForDisplay(BrickBreakerAwardStats stats) {
    return tiers.where((t) => !t.secret || stats.surprise9999).toList();
  }
}
