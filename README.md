# Zs Multi Tool Remote

Flutter app for **Android** and **unsigned iOS** (sideload). It is the phone side of **Z's Multi Tool v4** (`Zyvelia/Z-s-Multi-Tool-2.0`). You type the PC's Tailscale hostname once; each screen uses a fixed HTTPS port from `APP_HTTPS_PORTS` on the desktop.

There is no separate “python patch.” Start **Remote Hub → Go Live** on the PC (and the module you want, if it is not included in that). Device pairing uses **8455**.

## Tabs

| Tab | Desktop module | HTTPS |
| --- | -------------- | ----- |
| Vault | Secure Vault | **8443** |
| Music | Media Player | **8444** |
| Notes | Notes | **8448** |
| Games | Gaming Hub + GSM + Night (social) | **8446** / **8453** / **8450** |
| YT | YouTube Downloader | **8445** |
| Send | Quick Send | **8449** |
| Clip | Clipboard (hub) | **8451** |
| Messages | Messages (this PC only) | **8452** |
| Chat | AI Chat (same model / agent as the desktop) | **8454** |
| Settings | Hostname, access codes, invite key, chat source | — |

Extra screens opened from those tabs:

| Screen | Port | Notes |
| ------ | ---- | ----- |
| Night | **8450** | Jukebox / soundboard / limited GSM console (invite key) |
| Notifications | hub | Push-style inbox from the PC |

## 1. Build (GitHub Actions, no Mac needed)

1. Create a **private** GitHub repo and push this folder.
2. Open **Actions** → `Build Multi Tool Remote` (runs on push, or **Run workflow**).
3. Download artifacts:
   - `multi-tool-remote-apk` → `app-release.apk` (Android)
   - `multi-tool-remote-ipa-unsigned` → `MultiToolRemote-unsigned.ipa` (iOS)

The workflow generates `android/` and `ios/` on the runner. You do not need Flutter installed locally.

## 2. Install on the phone

**Android:** copy the `.apk` and allow “install unknown apps.”

**iOS (jailbroken / sideload):** the IPA is unsigned on purpose.

- **Filza** — tap the `.ipa` (needs AppSync Unified)
- **TrollStore** — drop the `.ipa` in; no 7-day expiry

## 3. Point it at the PC

1. On the PC: Tailscale up, **Remote Hub → Go Live**. Turn on remote in a module's ⚙ only if Hub does not already start it. Media Player's phone server stays off until its remote settings are used (or Hub starts it).
2. Phone → **Settings** → Tailscale hostname, e.g. `my-pc.tailnet-name.ts.net` — no `https://`, no port.
3. Optional: per-module access codes and the Tailnet Social invite key, same values as on the PC.
4. Switch tabs. Each URL is `https://<hostname>:<port>/`.

## Notes

- **Vault** — master password signs in; session token is memory-only for that run (idle expiry ~20 min), matching the desktop server.
- **Music** — streams the SQLite library the desktop Media Player indexes. The desktop UI is a browser table; this tab is the remote browse/stream client.
- **Games** — Hub launch list (`:8446`), dedicated servers start/stop/ready (`:8453`). Night is a card on this tab (`:8450`).
- **Chat** — same hosted or local model as desktop AI Chat, including agent actions when the PC allows them. Hosted API key stays on the PC.
- **Messages** — this PC only, not a friend-to-friend mesh.
- **Trust** — first pair goes through **8455** (code shown on Remote Hub).

Confirm Tailscale is signed in on both devices if a tab cannot connect.

## Inbox Worker / Messages

The **Messages** tab now uses the Cloudflare Inbox Worker instead of the old
Tailscale messaging transport. The existing Tailscale services/files remain
in the project for the other features that still use them.

The mobile Inbox signs in through the worker's own page, keeps the Better Auth
httpOnly session inside the worker-origin WebView, registers the phone's FCM
token, and polls message history every 10 seconds for catch-up.

### Firebase setup

Before building a release with push notifications, add:

- `firebase/google-services.json` for Android
- `firebase/GoogleService-Info.plist` for iOS

See `firebase/README.md` for the exact Firebase app IDs and setup steps.

Google OAuth is the recommended sign-in option on the worker's login page.
GitHub and passkey remain available there too.

