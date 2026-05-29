#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/LiveWallpaper.swift"
OUT="$SCRIPT_DIR/LiveWallpaper"

echo "🔨  Compiling LiveWallpaper…"
swiftc "$SRC" -o "$OUT" \
    -framework AVFoundation \
    -framework IOKit \
    -framework AppKit \
    -O                          # optimised build — lower CPU usage

echo "✅  Built:  $OUT"
echo ""
echo "Run:  $OUT /path/to/your/video.mp4"
