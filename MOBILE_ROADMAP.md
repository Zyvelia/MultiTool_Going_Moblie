# Mobile app — ideas to add (prioritized)

Use this as a backlog; not committed work.

## High impact
- **Navigation hub** — collapse Reminders + Clock + Connection test into a “Tools” tab; free bottom-nav slots.
- **Messages / Clipboard tabs** — match desktop ports `:8452` / `:8451` or drop from README.
- **First-run wizard** — hostname, pair code, test all HTTPS ports, notification permission.
- **Home-screen widget** — WoL + “PC online” status.

## Music
- Album art from desktop API.
- Playlists / favorites synced from Media Player.
- PC speaker mode: queue control if desktop API adds it.

## Reliability
- `workmanager` background task to call `ScheduleBootstrap.rescheduleAll()` after boot without opening UI.
- Reminder notification actions (Done / Snooze) on Android.

## Social / desktop parity
- Tailnet jukebox queue (Night is partial).
- AI chat: offline outbox for failed agent actions.

## Quality
- Widget / integration tests for notes sync, API clients.
- In-app “What’s new” from `CHANGELOG.md` on version bump.
