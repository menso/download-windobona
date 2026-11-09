# DownloadWindobona

A double-clickable macOS app that downloads every video from a
[Windobona](https://windobona.berlin/) media-order page (indoor skydiving /
paragliding footage) into neatly named per-flight folders.

## Download / run

Grab `DownloadWindobona_v03.app` from this repo and double-click it. It will ask
for one or more order URLs (e.g.
`https://bestellung.windobona.berlin/media/<code>`) and a destination
folder, then download everything.

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

- `DownloadWindobona_v03.app` — the runnable app.
- `DownloadWindobona_v03_source/` — plain-text source:
  - `DownloadWindobona.applescript` — the UI shell (URL/folder dialogs,
    live progress panel, final summary).
  - `download_windobona.sh` — the download engine. Self-contained; takes
    `<media_url> <destination_folder>` as arguments and prints
    `STATE ...` / `FINAL ...` / `ERROR ...` lines that the AppleScript side
    polls from a log file.

## Rebuilding after an edit

```bash
cd DownloadWindobona_v03_source
osacompile -o ../DownloadWindobona_v03.app DownloadWindobona.applescript
mkdir -p ../DownloadWindobona_v03.app/Contents/Resources
cp download_windobona.sh ../DownloadWindobona_v03.app/Contents/Resources/
chmod +x ../DownloadWindobona_v03.app/Contents/Resources/download_windobona.sh
```

No Xcode project, no signing, no dependencies to install.

## Contributing

Issues and PRs welcome. The `STATE`/`FINAL` line protocol between the two
source files is the contract to preserve — the shell script emits them,
the AppleScript polls and parses them — so a change to one side's output
format needs a matching change on the other side.

## License

MIT — see [LICENSE](LICENSE).

This project is not affiliated with or endorsed by Windobona.
