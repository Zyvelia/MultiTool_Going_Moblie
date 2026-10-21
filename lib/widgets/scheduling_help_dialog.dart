import 'dart:io';

import 'package:flutter/material.dart';

/// Platform notes for alarms / reminders (exact timing, Focus, force-stop).
void showSchedulingHelpDialog(BuildContext context) {
  final isIos = Platform.isIOS;
  final isAndroid = Platform.isAndroid;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Alarms & reminders'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'These run on your phone only — not through your PC or Tailscale.',
            ),
            const SizedBox(height: 12),
            if (isAndroid) ...[
              const Text(
                'Android',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Allow Notifications and Alarms & reminders (exact alarms) '
                'for this app in system settings.\n'
                '• Battery “optimization” / “sleeping apps” can delay alerts — '
                'exclude Zs Multi Tool Remote if alarms are late.\n'
                '• Force-stopping the app clears in-memory timers until you '
                'open it again; scheduled notifications are re-registered on '
                'boot when possible.\n'
                '• Snooze schedules a new alert a few minutes later.',
              ),
            ],
            if (isIos) ...[
              const Text(
                'iPhone / iPad',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              const Text(
                '• Allow Notifications when prompted; check Settings → '
                'Notifications → this app.\n'
                '• Focus / Do Not Disturb can silence banners — allow Time '
                'Sensitive notifications if iOS offers it.\n'
                '• iOS does not use Android-style exact alarms; very short '
                'snoozes may drift slightly.\n'
                '• If the app was swiped away, open it once so reminders can '
                'reschedule.',
              ),
            ],
            if (!isIos && !isAndroid)
              const Text(
                'Use your system notification settings so this app can alert you on time.',
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
