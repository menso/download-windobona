# DownloadWindobona

A double-clickable macOS app that downloads every video from a
[Windobona](https://windobona.berlin/) media-order page (indoor skydiving 
footage) into neatly named per-flight folders.

## Download / run

**[⬇ Download DownloadWindobona.zip](https://github.com/menso/download-windobona/releases/latest/download/DownloadWindobona.zip)**
(always links to the newest release). Unzip it and double-click
`DownloadWindobona.app`.

Don't grab it by browsing the file list above — `.app` is actually a
folder on disk, so clicking it in GitHub's file browser just opens that
folder instead of downloading anything. The link above is a proper
one-click download.

The app walks you through three steps: paste one or more order URLs
(e.g. `https://bestellung.windobona.berlin/media/<code>`), choose a
destination folder, then watch it download — with a progress bar per
order plus an overall one.

Files land in:

```
<destination>/<HHMMSS>_<TeamName>/<date>_<HH>_<MM>_<SS>_<FF>_cam<N>.mp4
```

**First launch:** macOS will say the app can't be verified because it isn't
signed with a paid Apple Developer ID. Right-click (or Control-click) the
app and choose "Open", then confirm once — that's a one-time security
click, not an install.

No Python, no Homebrew, nothing else to install: the engine is a plain
`bash` script using only `curl`, `grep`, `sed`, `awk` and `stat` — all part
of macOS itself, with nothing gated behind an Xcode Command Line Tools
prompt.

## What it does

- Reads the order's video list from Windobona's own `/api/media` endpoint.
- Skips any entry with no real thumbnail, and separately detects (via HTTP
  404, not by hard-coding a camera number) links that *look* real but have
  no actual clip behind them — both are reported as "skipped," not
  counted as failures.
- Downloads up to 6 files at once per order URL — queue several order URLs
  in one run and they download concurrently too, since each order gets its
  own throttling allowance on Windobona's side.
- Retries a failed file up to 3 times before giving up, and names it in the
  final summary.
- Resumable: re-running the same order skips any file already downloaded
  correctly (checked by comparing on-disk size to the server's reported
  size), so a re-run after an interruption only fetches what's missing.

## Repo layout

This repo tracks source only — the built `.app` is distributed as a zip on
the [Releases page](https://github.com/menso/download-windobona/releases),
not committed here (committing a `.app` bundle to the repo tree is exactly
what made it look like a folder to browse instead of a file to download).

- `source/` — plain-text source:
  - `DownloadWindobona.applescript` — the whole UI (AppleScriptObjC/Cocoa):
    the three-step window, live per-order + overall progress bars, and the
    update check.
  - `download_windobona.sh` — the download engine. Self-contained; takes
    `<media_url> <destination_folder>` as arguments and prints
    `STATE ...` / `FINAL ...` / `ERROR ...` lines that the AppleScript side
    polls from a log file.

## Rebuilding after an edit

```bash
cd source
osacompile -o ../DownloadWindobona.app DownloadWindobona.applescript
mkdir -p ../DownloadWindobona.app/Contents/Resources
cp download_windobona.sh ../DownloadWindobona.app/Contents/Resources/
chmod +x ../DownloadWindobona.app/Contents/Resources/download_windobona.sh
```

No Xcode project, no signing, no dependencies to install.

### Cutting a release

```bash
# bump CURRENT_VERSION in source/DownloadWindobona.applescript first, then:
cd ..  # repo root, with DownloadWindobona.app freshly built there (gitignored)
zip -r DownloadWindobona.zip DownloadWindobona.app
git tag vX.Y.Z && git push origin vX.Y.Z
gh release create vX.Y.Z DownloadWindobona.zip --title vX.Y.Z --notes "..."
```

The asset must always be named `DownloadWindobona.zip` — that's what makes
the `.../releases/latest/download/DownloadWindobona.zip` link above always
resolve to the newest release automatically.

## Contributing

Issues and PRs welcome. The `STATE`/`FINAL` line protocol between the two
source files is the contract to preserve — the shell script emits them,
the AppleScript polls and parses them — so a change to one side's output
format needs a matching change on the other side.

## License

MIT — see [LICENSE](LICENSE).

This project is not affiliated with or endorsed by Windobona.
