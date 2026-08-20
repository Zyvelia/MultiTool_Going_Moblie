import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'brick_breaker_mode.dart';
import 'brick_breaker_screen.dart';

class BrickBreakerMenuScreen extends StatelessWidget {
  const BrickBreakerMenuScreen({super.key});

  void _openMode(BuildContext context, BrickBreakerMode mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrickBreakerScreen(mode: mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Brick Breaker')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Choose a game mode',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted, fontSize: 14),
                  ),
                  const SizedBox(height: 20),
                  _ModeCard(
                    icon: BrickBreakerMode.endless.icon,
                    title: BrickBreakerMode.endless.title,
                    subtitle: BrickBreakerMode.endless.subtitle,
                    accent: AppColors.accent,
                    onTap: () => _openMode(context, BrickBreakerMode.endless),
                  ),
                  const SizedBox(height: 12),
                  _ModeCard(
                    icon: BrickBreakerMode.siege.icon,
                    title: BrickBreakerMode.siege.title,
                    subtitle: BrickBreakerMode.siege.subtitle,
                    accent: const Color(0xFFFF5252),
                    onTap: () => _openMode(context, BrickBreakerMode.siege),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.12),
                AppColors.card,
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  color: accent == AppColors.accent ? AppColors.accentGlow : accent,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
