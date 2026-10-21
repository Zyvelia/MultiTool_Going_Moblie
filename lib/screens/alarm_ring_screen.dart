import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/alarm.dart';
import '../theme/app_colors.dart';

class AlarmRingScreen extends StatelessWidget {
  const AlarmRingScreen({
    super.key,
    required this.alarm,
    required this.onStop,
    required this.onSnooze,
  });

  final Alarm alarm;
  final VoidCallback onStop;
  final void Function(int minutes) onSnooze;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF2A0010),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const Icon(Icons.alarm, size: 88, color: AppColors.accent),
                const SizedBox(height: 16),
                Text(
                  alarm.label,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.w300,
                    color: AppColors.accentGlow,
                  ),
                ),
                const Spacer(),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final min in [5, 10, 15])
                      OutlinedButton(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          onSnooze(min);
                          Navigator.of(context).pop();
                        },
                        child: Text('Snooze $min min'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      onStop();
                      Navigator.of(context).pop();
                    },
                    child: const Text(
                      'STOP',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
