#!/usr/bin/env bash
# Quality gate: unit tests plus a release build where any warning fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
export DEVELOPER_DIR
XCODE_SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [[ -z "${SDKROOT:-}" && -d "$XCODE_SDK" ]]; then
    export SDKROOT="$XCODE_SDK"
fi

cd "$ROOT"
echo "› Unit tests…"
SWIFT_TEST_FLAGS=(--build-system native)
if [[ -d "$DEVELOPER_DIR/Library/Developer/Frameworks/Testing.framework" ]]; then
    SWIFT_TEST_FLAGS+=(
        -Xswiftc "-F$DEVELOPER_DIR/Library/Developer/Frameworks"
        -Xlinker -rpath -Xlinker "$DEVELOPER_DIR/Library/Developer/Frameworks"
        -Xlinker -rpath -Xlinker "$DEVELOPER_DIR/Library/Developer/usr/lib"
    )
fi
swift test "${SWIFT_TEST_FLAGS[@]}"
echo "› Release build, warnings as errors…"
swift build --build-system native -c release -Xswiftc -warnings-as-errors -Xcc -Werror
echo "✓ All checks passed"
