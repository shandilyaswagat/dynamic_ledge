#!/usr/bin/env bash
# Builds a universal release app and packages it as build/DynamicNotch.dmg.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"   required for distribution
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
APP_OUTPUT="$STAGING/Dynamic Notch.app" "$ROOT/Scripts/build-app.sh"
mkdir -p "$ROOT/build"

echo "› Packaging ${DMG}…"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "Dynamic Notch" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"

if [[ "${SIGN_IDENTITY:--}" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    if [[ "${SIGN_IDENTITY:--}" == "-" ]]; then
        echo "✗ Notarization needs a Developer ID SIGN_IDENTITY" >&2
        exit 1
    fi
    echo "› Notarizing (this can take a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

cp "$STAGING/Dynamic Notch.app/Contents/Info.plist" "$ROOT/build/ReleaseInfo.plist"
echo "✓ $DMG"
