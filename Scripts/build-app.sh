#!/usr/bin/env bash
# Builds "Dynamic Notch.app" into ./build.
#
#   CONFIG=release|debug        default: release
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#                               default: "-" (ad-hoc, runs only on this Mac)
#   VERSION=x.y.z               default: the VERSION file
#   BUILD_NUMBER=n              default: number of commits, so it always goes up
#   BUNDLE_ID=com.rectircle.DynamicNotch
#   UNIVERSAL=1                 build for Apple silicon and Intel
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
BUNDLE_ID="${BUNDLE_ID:-com.rectircle.DynamicNotch}"
APP="$ROOT/build/Dynamic Notch.app"
UPDATE_PUBLIC_KEY="$(tr -d '[:space:]' < "$ROOT/Support/UpdatePublicKey.txt")"
if [[ -n "$UPDATE_PUBLIC_KEY" && ! "$UPDATE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "Invalid Support/UpdatePublicKey.txt (expected base64 Ed25519 public key)" >&2
    exit 1
fi

# Use the selected Xcode's SDK. A newer Command Line Tools SDK can contain
# architectures that Xcode's linker doesn't know yet.
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR
XCODE_SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ -z "${SDKROOT:-}" && -d "$XCODE_SDK" ]]; then
    export SDKROOT="$XCODE_SDK"
fi

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

cd "$ROOT"
echo "› Building ($CONFIG)…"
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "› Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/DynamicNotch" "$APP/Contents/MacOS/DynamicNotch"
cp "$BIN_DIR/libNotchMediaBridge.dylib" "$APP/Contents/Frameworks/libNotchMediaBridge.dylib"
cp "$ROOT/Support/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" -e "s/__BUNDLE_ID__/$BUNDLE_ID/" \
    "$ROOT/Support/Info.plist" > "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :DNUpdatePublicKey $UPDATE_PUBLIC_KEY" "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" > /dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ "$CONFIG" == "release" ]]; then
    strip -x "$APP/Contents/MacOS/DynamicNotch"
    strip -x "$APP/Contents/Frameworks/libNotchMediaBridge.dylib"
fi

echo "› Signing with: $SIGN_IDENTITY"
SIGN_FLAGS=(--force --options runtime)
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    SIGN_FLAGS+=(--timestamp=none)
else
    SIGN_FLAGS+=(--timestamp)
fi
# Inside out: the helper library first, then the app.
codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libNotchMediaBridge.dylib"
codesign "${SIGN_FLAGS[@]}" --entitlements "$ROOT/Support/DynamicNotch.entitlements" --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"

echo "✓ Built $APP ($VERSION, build $BUILD_NUMBER)"
