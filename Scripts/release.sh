#!/usr/bin/env bash
# Publishes the version in the VERSION file as a GitHub release.
#
# Releases only come from main. Work happens on develop and is merged into main when it's ready.
#
# Before running, on main:
#   1. Set the new version in VERSION (x.y.z, see CHANGELOG.md for the rules).
#   2. Add a "## [x.y.z] - date" section to CHANGELOG.md.
#   3. Commit both.
#
# The script refuses to continue if any of that is missing, then runs the checks, builds the
# DMG, tags the commit, pushes, and creates the release with notes taken from CHANGELOG.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
TAG="v$VERSION"

fail() { echo "✗ $*" >&2; exit 1; }

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must look like 1.2.3 (got '$VERSION')"
BRANCH="$(git symbolic-ref --quiet --short HEAD || echo "(detached)")"
[[ "$BRANCH" == "main" ]] || fail "Releases come from main, but you're on $BRANCH. Merge into main first"
git diff --quiet && git diff --cached --quiet || fail "Commit your changes first"
[[ -n "${UPDATE_SIGNING_KEY_FILE:-}" && -f "$UPDATE_SIGNING_KEY_FILE" ]] || fail "Set UPDATE_SIGNING_KEY_FILE to your private Ed25519 key file"
[[ -s Support/UpdatePublicKey.txt ]] || fail "Configure Support/UpdatePublicKey.txt before publishing"
git fetch --tags --quiet origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "Local main and origin/main differ. Pull or push first"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && fail "$TAG already exists. Bump VERSION"
grep -q "^## \[$VERSION\]" CHANGELOG.md || fail "CHANGELOG.md has no '## [$VERSION]' section"
command -v gh >/dev/null || fail "The GitHub CLI (gh) is needed"

# Release notes: this version's changelog section, plus install steps for new users.
NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
awk -v version="$VERSION" '
    $0 ~ "^## \\[" version "\\]" { inside = 1; next }
    inside && /^## \[/ { exit }
    inside && /^\[[0-9]/ { next }
    inside { print }
' CHANGELOG.md > "$NOTES"
[[ -s "$NOTES" ]] || fail "The CHANGELOG section for $VERSION is empty"
cat >> "$NOTES" <<'EOF'

### Installing
Download **DynamicNotch.dmg** below, open it and drag Dynamic Notch into Applications. The first
time you open it, macOS will ask you to confirm in System Settings › Privacy & Security
(click **Open Anyway**). The [README](https://github.com/shandilyaswagat/dynamic_notch#installing-it)
walks through it step by step.

Updating? Just replace the old app in Applications. Your settings are kept.
EOF

echo "› Releasing Dynamic Notch $VERSION"
./Scripts/check.sh
./Scripts/make-dmg.sh

swift Scripts/sign-update.swift sign "$UPDATE_SIGNING_KEY_FILE" build/DynamicNotch.dmg "$VERSION" "${BUNDLE_ID:-com.rectircle.DynamicNotch}" "build/ReleaseInfo.plist"

git tag -a "$TAG" -m "Dynamic Notch $VERSION"
git push origin main "$TAG"
# Also publish a plain checksum for manual verification and Homebrew.
SHA="$(shasum -a 256 build/DynamicNotch.dmg | awk '{print $1}')"
echo "$SHA" > build/DynamicNotch.dmg.sha256
gh release create "$TAG" build/DynamicNotch.dmg build/DynamicNotch.dmg.sha256 build/DynamicNotch.update.json --title "Dynamic Notch $VERSION" --notes-file "$NOTES"
echo "✓ Released $TAG"
./Scripts/update-cask.sh "$VERSION" "$SHA" || echo "! Couldn't update the Homebrew cask; run Scripts/update-cask.sh $VERSION $SHA"
