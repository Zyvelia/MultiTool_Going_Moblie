# Changelog

## Unreleased

### Added
- **Steps** tab: pedometer-first (Design D arc), Today/Week/Month, local history + optional Health, Android activity permission + manifest patches, goal notification, streak/goal celebration, Android home widget.

## 2.7.0+4 (2026-03-21)

### Added
- **Reminders** tab — dated reminders with early nudge notifications.
- **Clock** tab — alarms with built-in harsh tones or imported audio, repeat days, fullscreen stop UI.
- **Music** — artist play / shuffle, library shuffle & repeat, Apple Music–style now playing sheet with volume.
- **PC** tab — stream service, WoL, remote desktop (existing; grouped in nav).
- Scheduling help dialog (Android exact alarms / iOS Focus notes).
- Snooze for alarms (5 / 10 / 15 min) and reminders.
- Edit reminders in place (tap a row).

### Removed
- Unused PC **notification mirror** screen and API client (never in bottom nav; relied on a missing `notifications` port mapping).

### Fixed
- Restored a valid `.gitignore` (was accidentally overwritten).
- Android manifest patch registers `flutter_local_notifications` boot receivers so scheduled alerts can survive reboot.
- App re-schedules alarms/reminders on resume and startup.

### Notes
- Local alerts still work best when the app is not force-stopped; see in-app **Alarms & reminders** help.

## 2.6.0+3

Earlier remote features: Vault, Music, Notes, Games, YT, Send, Chat, Settings, device pairing, offline music cache.
