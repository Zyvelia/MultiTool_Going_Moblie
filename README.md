# Zs Multi Tool Remote

A native Flutter app for iOS (sideload) and Android with four tabs that
talk to the matching servers already built into Zs Multi Tool:

| Tab | Talks to | Port |
|---|---|---|
| Vault | `core/services/vault_web_server.py` | 8443 |
| Games | Gaming Hub launches + **dedicated GSM start/stop** + Night page | 8446 / **8453** / **8450** |
| Chat | `modules/AI/web_server.py` — same model/agent as desktop AI Chat | **8454** |
| YT | `modules/yt_downloader/web_server.py` | 8445 |

You only enter your PC's Tailscale hostname once in Settings — each
tab's URL is derived from it using the fixed port above (matches
`APP_HTTPS_PORTS` in `core/services/tailscale_service.py`).

**Before this app can reach anything**, you need to apply the backend
patch (`Z-s-Multi-Tool-python patch` from the same delivery) to your
desktop app, then start remote access from each module's page. See
that patch's own README for setup steps and the new port numbers.

## 1. Get this building on GitHub (no Mac needed)

1. Create a new **private** GitHub repo (e.g. `multi-tool-remote`).
2. Push with the included script — from PowerShell, inside this folder:
   ```powershell
   .\push_to_github.ps1 -RepoUrl "https://github.com/<you>/multi-tool-remote.git"
   ```
   Every run after that, just:
   ```powershell
   .\push_to_github.ps1
   ```
   If you don't have Git installed: `winget install --id Git.Git -e`.
3. Go to the repo's **Actions** tab. The `Build Multi Tool Remote`
   workflow runs automatically on push, or click **Run workflow** to
   trigger it manually.
4. When it finishes (~5-10 min), open the run and download the two
   artifacts under **Artifacts**:
   - `multi-tool-remote-apk` → `app-release.apk` (Android)
   - `multi-tool-remote-ipa-unsigned` → `MultiToolRemote-unsigned.ipa` (iOS)

The workflow runs `flutter create` itself to generate the `android/`
and `ios/` platform folders on the runner — you don't need Flutter
installed locally at all.

## 2. Install on your phone

**Android:** copy the `.apk` to your phone and open it (allow "install
unknown apps").

**iOS (jailbroken):** the IPA is unsigned on purpose — no Apple
Developer account, no 7-day expiry, no Xcode dance.
- **Filza** — tap the `.ipa`, it offers to install directly (needs
  AppSync Unified for unsigned app support).
- **TrollStore** (if installed) — drop the `.ipa` in, installs
  permanently with no expiry.

## 3. Point it at your PC

1. On each module's page in the desktop app, tap **Start Remote
   Access** (Vault/Music/YT already have this in their Settings tab;
   Gaming Hub now has a compact version of the same panel right under
   the header).
2. Open this app → **Settings** tab (bottom nav) → enter your
   Tailscale hostname, e.g. `my-pc.tailnet-name.ts.net` — no
   `https://`, no port. Save.
3. Switch to any of the other four tabs — each one connects
   automatically using that hostname plus its own fixed port.

## Notes

- **Vault**: uses your master password to sign in on your phone; the
  session token lives only in memory for that app run (nothing is
  written to disk), matching the desktop server's own session model
  (idle-expires after 20 min).
- **Games**: Gaming Hub launch list, plus **dedicated servers** (start/stop/ready
  from Game Server Manager on `:8453`). **Night page** is a card on this tab
  — jukebox / soundboard / limited console using an invite key (`:8450`).
  Hub **Go Live** on the PC must be on.
- **YT**: same job queue the desktop page and browser extension use —
  queue from your phone, it downloads on the PC.
- Access codes (if you set any per-module in the desktop Settings
  tabs) go in this app's Settings screen too.
