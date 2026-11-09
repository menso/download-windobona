# DownloadWindobona

Downloads every video from a Windobona media-order page (indoor skydiving /
paragliding footage, e.g. `https://bestellung.windobona.berlin/media/<code>`)
into neatly named per-flight folders.

## Running it

Double-click `DownloadWindobona.app`. It opens a single window that walks
through three steps (the current step is highlighted in green at the top):

1. **Add URLs** — paste one or more order URLs, one per line.
2. **Select Folder** — choose where the videos go.
3. **Download Progress** — one progress bar per order plus an overall bar,
   updating live.

Files land in:

```
<destination>/<HHMMSS>_<TeamName>/<date>_<HH>_<MM>_<SS>_<FF>_cam<N>.mp4
```

**First launch on a new Mac:** macOS will say the app can't be verified
because it isn't signed with a paid Apple Developer ID. Right-click (or
Control-click) the app and choose "Open", then confirm once — that's a
one-time security click, not an install. After that it opens normally.

No Python, no Homebrew, nothing else to install: the engine is a plain
`bash` script using only `curl`, `grep`, `sed`, `awk` and `stat` — all part
of macOS itself on every Mac, with nothing gated behind an Xcode Command
Line Tools prompt.

## What it does

- Reads the order's video list from Windobona's own `/api/media` endpoint.
- Skips any entry with no real thumbnail, and separately detects (via HTTP
  404, not by hard-coding a camera number) links that *look* real but have
  no actual clip behind them — both are reported as "skipped", not
  counted as failures.
- Downloads up to 6 files at once per order (matches a browser's per-host
  connection limit; testing showed Windobona throttles per-order bandwidth
  server-side, so going higher doesn't help, but running multiple *orders*
  at once roughly doubles total throughput — hence the multi-URL queue).
- Retries a failed file up to 3 times before giving up, and names it in the
  final summary.
- Resumable: re-running the same order skips any file already downloaded
  correctly (checked by comparing on-disk size to the server's reported
  size), so a re-run after an interruption only fetches what's missing.
- Checks this repo's latest GitHub release on launch and shows a banner at
  the top of the window if a newer version exists (click it to open the
  release page). This is a simple string comparison against the version
  baked into the app (`CURRENT_VERSION` near the top of the AppleScript
  source), not real semantic-version ordering — fine as long as each
  release bumps that constant.

## Files

- `DownloadWindobona.applescript` — the whole UI: the three-step window
  (AppleScriptObjC/Cocoa — a real window, not `display dialog` boxes), the
  live per-order + overall progress bars, and the update check. It launches
  `download_windobona.sh` as a background process per order and polls each
  order's log file directly via Cocoa file APIs (no shelling out in the
  polling loop, so there's no AppleEvent-timeout risk no matter how long a
  batch takes).
- `download_windobona.sh` — the actual download engine. Fully self
  contained; takes `<media_url> <destination_folder>` as arguments and
  prints `STATE ...` / `FINAL ...` / `ERROR ...` lines that the AppleScript
  side polls from a log file.

## Rebuilding after an edit

Edit either source file, then from this folder:

```bash
osacompile -o DownloadWindobona.app DownloadWindobona.applescript
mkdir -p DownloadWindobona.app/Contents/Resources
cp download_windobona.sh DownloadWindobona.app/Contents/Resources/
chmod +x DownloadWindobona.app/Contents/Resources/download_windobona.sh
```

That's the whole build step — no Xcode project, no signing, no
dependencies to install.

## Handing this to another Claude (or any AI coding assistant)

Both files here are plain, uncompiled source — nothing is hidden inside a
compiled binary. Point it at this folder and it can read and edit either
file directly, then rebuild with the three commands above. The only thing
worth telling it up front: the `STATE`/`FINAL` line protocol between the
two files is the contract to preserve — the shell script emits them, the
AppleScript polls and parses them — so a change to one side's output
format needs a matching change on the other side.
