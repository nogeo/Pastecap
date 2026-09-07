#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="${1:-$(uname -m)}"
case "$ARCH" in
  arm64|x86_64) ;;
  *) echo "Usage: $0 [arm64|x86_64]" >&2; exit 2 ;;
esac
OUTPUT="$ROOT/.build/pastecap-self-test-$ARCH"
mkdir -p "$ROOT/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" swiftc \
  -target "$ARCH-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  "$ROOT/Sources/Pastecap/Models.swift" \
  "$ROOT/Sources/Pastecap/HotKeyManager.swift" \
  "$ROOT/Sources/Pastecap/Screenshot.swift" \
  "$ROOT/Sources/Pastecap/HistoryView.swift" \
  "$ROOT/Tests/PastecapTests/main.swift" \
  -o "$OUTPUT"
arch -"$ARCH" "$OUTPUT"
