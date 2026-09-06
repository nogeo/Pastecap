#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/.build/pastecap-self-test"
mkdir -p "$ROOT/.build/module-cache"
CLANG_MODULE_CACHE_PATH="$ROOT/.build/module-cache" swiftc \
  -target "arm64-apple-macosx14.0" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  "$ROOT/Sources/Pastecap/Models.swift" \
  "$ROOT/Sources/Pastecap/HotKeyManager.swift" \
  "$ROOT/Sources/Pastecap/Screenshot.swift" \
  "$ROOT/Sources/Pastecap/HistoryView.swift" \
  "$ROOT/Tests/PastecapTests/main.swift" \
  -o "$OUTPUT"
"$OUTPUT"
