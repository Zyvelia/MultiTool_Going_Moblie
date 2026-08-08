# Zs Music Remote

A native Flutter app for iOS (sideload) and Android that talks to the
music web server already built into Zs Multi Tool
(`modules/media_player/web_server.py` + the Remote Access Settings tab).
It's an independent player: it streams your library straight from
`/api/stream/<id>`, the same way the browser page does — it doesn't
control the desktop app's own playback.

## 1. Get this building on GitHub (no Mac needed)

1. Create a new **private** GitHub repo (e.g. `music-remote`).
2. Push with the included script — from PowerShell, inside this folder:
   ```powershell
   .\push_to_github.ps1 -RepoUrl "https://github.com/<you>/music-remote.git"
   ```
   The first run will pop a browser window to sign in to GitHub if you
   haven't already (via Git Credential Manager, which ships with Git
   for Windows). Every run after that, just:
   ```powershell
   .\push_to_github.ps1
   ```
   and it'll commit + push whatever changed — no need to pass `-RepoUrl`
   again unless you're pointing it at a different repo. If you don't
   have Git installed: `winget install --id Git.Git -e`.

   (Or by hand, if you'd rather not run a script:
   ```
   git init
   git add .
   git commit -m "initial"
   git branch -M main
   git remote add origin https://github.com/<you>/music-remote.git
   git push -u origin main
   ```
   )
3. Go to the repo's **Actions** tab. The `Build Music Remote` workflow
   runs automatically on push, or click **Run workflow** to trigger it
   manually.
4. When it finishes (~5-10 min), open the run and download the two
   artifacts under **Artifacts**:
   - `music-remote-apk` → `app-release.apk` (Android)
   - `music-remote-ipa-unsigned` → `MusicRemote-unsigned.ipa` (iOS)

The workflow runs `flutter create` itself to generate the `android/`
and `ios/` platform folders on the runner — you don't need Flutter
installed locally at all, on Windows or otherwise.

## 2. Install on your phone

**Android:** copy the `.apk` to your phone and open it (allow "install
unknown apps" for whatever app you used to open it).

**iOS (jailbroken):** the IPA is unsigned on purpose — no Apple
Developer account, no 7-day expiry, no Xcode dance. Install it with
whatever you already use for unsigned IPAs:
- **Filza** — tap the `.ipa`, it offers to install directly (needs
  AppSync Unified installed for unsigned app support).
- **TrollStore** (if installed) — drop the `.ipa` in, it installs
  permanently with no expiry and no jailbreak-detection issues most
  sideloaded apps have.

## 3. Point it at your PC

1. In the desktop app: **Music Player → Settings tab → Connect**
   (Tailscale), then **Start Remote Access**.
2. The status line shows your Tailscale hostname. The app always
   listens externally on port **8444** (fixed — this is
   `APP_HTTPS_PORTS["music"]` in `tailscale_service.py`, separate from
   the "Local port" field which is just the loopback port on the PC
   side). So the URL to enter in the phone app is:
   ```
   https://<your-device-name>.<your-tailnet>.ts.net:8444
   ```
3. Open the app on your phone → gear icon (or first-run prompt) → paste
   that URL → **Test connection** → **Save**.

## What's included now

- **Background playback + lock-screen controls** (`just_audio_background`):
  playback survives locking the phone or switching apps, and you get
  play/pause/skip on the lock screen and notification shade. The CI
  workflow patches in the required entitlements after `flutter create`
  scaffolds the platform folders — `UIBackgroundModes: audio` on iOS,
  and the `POST_NOTIFICATIONS`/foreground-service permissions on
  Android — since a fresh `flutter create` doesn't include either.
- **On-device caching** (`LockCachingAudioSource`): each song is written
  to a local cache file as it streams, so replaying something you've
  already played reads from disk instead of re-streaming over
  Tailscale. This is passive (caches what you play), not a "download
  this whole library for offline" feature — that'd be a reasonable next
  step if you want it (a per-song download button, likely backed by the
  same `LockCachingAudioSource`, just pre-triggered instead of on play).
- **Auto-advance**: the next track starts automatically when the
  current one finishes.

## Notes / things you might want to extend later

- Explicit "download for offline" per song/album, rather than
  cache-as-you-play.
- Uses `/api/songs`, `/api/now-playing` (unused by this app currently),
  and `/api/stream/<id>` from `web_server.py`. `/api/control` is *not*
  called — it drives the desktop engine's own playback, a separate
  session by design.
