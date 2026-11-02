#!/usr/bin/env bash
# Builds a universal release app and packages it as build/DynamicNotch.dmg. The file keeps its
# old name on purpose: apps from 1.3.x and earlier look for exactly this name to update.
#
#   SIGN_IDENTITY="Dynamic Ledge" (self-made certificate) or "Developer ID Application: …"
#   NOTARY_PROFILE=profile-name   a `xcrun notarytool store-credentials` profile; when set,
#                                 the DMG is notarized and stapled
#   VERSION / BUILD_NUMBER      see build-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export UNIVERSAL=1
export CONFIG=release

DMG="$ROOT/build/DynamicNotch.dmg"
# The disk gets its own name, with the version, so it's never mistaken for the app in Finder's
# sidebar, and an old disk left open doesn't turn the new one into "Dynamic Ledge 1".
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
VOLUME="Dynamic Ledge $VERSION Installer"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
# Assemble and sign outside synced folders so File Provider cannot reattach Finder metadata
# between signing and packaging. The disk image preserves the signed bundle unchanged.
APP_OUTPUT="$STAGING/Dynamic Ledge.app" "$ROOT/Scripts/build-app.sh"
mkdir -p "$ROOT/build"

echo "› Packaging ${DMG}…"
ln -s /Applications "$STAGING/Applications"
# The window shows an arrow from the app to Applications, drawn at 1x and 2x for Retina.
mkdir "$STAGING/.background"
swift "$ROOT/Scripts/dmg-background.swift" "$STAGING/.background/bg.png" 1
swift "$ROOT/Scripts/dmg-background.swift" "$STAGING/.background/bg@2x.png" 2
tiffutil -cathidpicheck "$STAGING/.background/bg.png" "$STAGING/.background/bg@2x.png" \
    -out "$STAGING/.background/background.tiff" >/dev/null 2>&1
rm "$STAGING/.background/bg.png" "$STAGING/.background/bg@2x.png"

# Build a writable disk, let Finder lay out its window, then compress it.
rm -f "$DMG"
WRITABLE="$(mktemp -d)/writable.dmg"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -size 60m -ov -quiet "$WRITABLE"
MOUNT="/Volumes/$VOLUME"
[[ -d "$MOUNT" ]] && hdiutil detach "$MOUNT" -force -quiet
hdiutil attach "$WRITABLE" -readwrite -noverify -noautoopen -quiet
# Matches the positions in dmg-background.swift. Finder needs permission to be controlled the
# first time; without it the disk still works, just without the arrow window.
osascript <<APPLESCRIPT || echo "! Couldn't lay out the installer window; the DMG works without it"
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 800, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "Dynamic Ledge.app" of container window to {160, 190}
        set position of item "Applications" of container window to {440, 190}
        close
        -- Finder saves the window when it closes; reopening and sizing it again makes the size stick.
        open
        set the bounds of container window to {200, 120, 800, 548}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT
sync
hdiutil detach "$MOUNT" -quiet || { sleep 2; hdiutil detach "$MOUNT" -force -quiet; }
hdiutil convert "$WRITABLE" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -rf "$(dirname "$WRITABLE")"

# Only a Developer ID signature on the disk image means anything to Gatekeeper.
if [[ "${SIGN_IDENTITY:--}" == "Developer ID"* ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ "${SIGN_IDENTITY:--}" != "Developer ID"* ]]; then
        echo "✗ Notarization needs a Developer ID SIGN_IDENTITY" >&2
        exit 1
    fi
    echo "› Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

cp "$STAGING/Dynamic Ledge.app/Contents/Info.plist" "$ROOT/build/ReleaseInfo.plist"
echo "✓ $DMG"
