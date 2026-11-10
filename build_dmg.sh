#!/bin/bash
# Builds a drag-to-Applications installer DMG from the already-built
# DownloadWindobona.app at the repo root (build it first per README.md).
# Uses only macOS's own hdiutil + Finder scripting -- no third-party tools.
set -euo pipefail

cd "$(dirname "$0")"

APP="DownloadWindobona.app"
VOLNAME="DownloadWindobona"
DMG_FINAL="DownloadWindobona.dmg"
BACKGROUND="dmg_background.png"

if [ ! -d "$APP" ]; then
    echo "ERROR: $APP not found -- build it first (see README.md)." >&2
    exit 1
fi
if [ ! -f "$BACKGROUND" ]; then
    echo "ERROR: $BACKGROUND not found." >&2
    exit 1
fi

STAGING=$(mktemp -d /tmp/dmg_staging.XXXXXX)
trap 'rm -rf "$STAGING"; [ -n "${MOUNT_DIR:-}" ] && hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true' EXIT

cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
mkdir "$STAGING/.background"
cp "$BACKGROUND" "$STAGING/.background/background.png"

RW_DMG=$(mktemp /tmp/dmg_rw.XXXXXX.dmg)
rm -f "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDRW "$RW_DMG" -quiet

MOUNT_DIR="/Volumes/$VOLNAME"
hdiutil attach "$RW_DMG" -quiet -mountpoint "$MOUNT_DIR"

osascript <<OSASCRIPT_EOF
tell application "Finder"
	tell disk "$VOLNAME"
		open
		set current view of container window to icon view
		set toolbar visible of container window to false
		set statusbar visible of container window to false
		set the bounds of container window to {400, 100, 1000, 500}
		set theViewOptions to the icon view options of container window
		set arrangement of theViewOptions to not arranged
		set icon size of theViewOptions to 96
		set background picture of theViewOptions to file ".background:background.png"
		set position of item "$APP" of container window to {150, 180}
		set position of item "Applications" of container window to {450, 180}
		update without registering applications
		delay 1
		close
	end tell
end tell
OSASCRIPT_EOF

sync
hdiutil detach "$MOUNT_DIR" -quiet
MOUNT_DIR=""

rm -f "$DMG_FINAL"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_FINAL" -quiet
rm -f "$RW_DMG"

echo "Built $DMG_FINAL"
