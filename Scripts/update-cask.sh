#!/usr/bin/env bash
# Points the Homebrew cask at a release: ./Scripts/update-cask.sh 1.4.0 <sha256>
# Writes Casks/dynamic-ledge.rb in the shandilyaswagat/homebrew-tap repository and pushes it.
# The cask used to be called dynamic-notch; cask_renames.json moves existing installs across.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?version, e.g. 1.4.0}"
SHA="${2:?sha256 of DynamicNotch.dmg}"
TAP="${TAP_REPO:-shandilyaswagat/homebrew-tap}"
CASK="Casks/dynamic-ledge.rb"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
gh repo clone "$TAP" "$WORK/tap" -- --quiet
mkdir -p "$WORK/tap/Casks"
sed -e "s/__VERSION__/$VERSION/" -e "s/__SHA256__/$SHA/" \
    "$ROOT/packaging/homebrew/dynamic-ledge.rb.template" > "$WORK/tap/$CASK"
cd "$WORK/tap"
# The old name points at the new one.
if [[ -f Casks/dynamic-notch.rb ]]; then git rm --quiet Casks/dynamic-notch.rb; fi
printf '{\n  "dynamic-notch": "dynamic-ledge"\n}\n' > cask_renames.json
git add "$CASK" cask_renames.json
if git diff --cached --quiet; then
    echo "› Cask already at $VERSION"
    exit 0
fi
git commit --quiet -m "Dynamic Ledge $VERSION"
git push --quiet
echo "✓ Homebrew cask now at $VERSION"
