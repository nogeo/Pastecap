#!/bin/sh
# Build and launch the native macOS App target. Use Xcode ⌘R for breakpoints.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/.build/xcode-dev/Pastecap.app"
if [ "${1:-}" != "--no-build" ]; then
    xcodebuild -project "$ROOT/Pastecap.xcodeproj" -scheme Pastecap \
        -configuration Debug -destination 'platform=macOS' build
fi
if [ ! -d "$APP" ]; then
    echo "Missing $APP; run scripts/run-dev.sh without --no-build first." >&2
    exit 1
fi
open "$APP"
