#!/usr/bin/env bash
# Builds Support/AppIcon.icns from Support/AppIcon-1024.png, the master artwork: a 1024 × 1024
# PNG with the tile on Apple's icon grid (824 px, centred) and its shadow. Run from anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER="$ROOT/Support/AppIcon-1024.png"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Support/AppIcon.icns"
echo "✓ Wrote Support/AppIcon.icns"
