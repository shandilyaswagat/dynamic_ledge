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
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
# Assemble and sign outside synced folders so File Provider cannot reattach Finder metadata
# between signing and packaging. The disk image preserves the signed bundle unchanged.
APP_OUTPUT="$STAGING/Dynamic Ledge.app" "$ROOT/Scripts/build-app.sh"
mkdir -p "$ROOT/build"

echo "› Packaging ${DMG}…"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Dynamic Ledge" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"

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
