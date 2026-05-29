#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
#  set-video.sh — Set the video file for the Video Screen Saver
#
#  Usage:  ./set-video.sh /path/to/video.mp4
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

BUNDLE_ID="com.manish.videoscreensaver"
VALID_EXTS="mp4 m4v mov"

if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/video.mp4"
    echo ""
    echo "Sets the video file for the Video Screen Saver."
    echo "Supported formats: $VALID_EXTS"
    echo ""
    echo "Current setting:"
    CURRENT=$(defaults read "$BUNDLE_ID" VideoPath 2>/dev/null || echo "(not set)")
    echo "  $CURRENT"
    exit 1
fi

# Resolve path (expand ~ and relative paths)
VIDEO_PATH="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"

# Check file exists
if [ ! -f "$VIDEO_PATH" ]; then
    echo "Error: File not found: $VIDEO_PATH"
    exit 1
fi

# Check extension
EXT="${VIDEO_PATH##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
VALID=false
for e in $VALID_EXTS; do
    if [ "$EXT_LOWER" = "$e" ]; then
        VALID=true
        break
    fi
done

if [ "$VALID" = false ]; then
    echo "Error: Unsupported format: .$EXT_LOWER"
    echo "Supported: $VALID_EXTS"
    echo ""
    echo "Convert with:"
    echo "  ffmpeg -i \"$1\" -c:v hevc_videotoolbox -b:v 6M -r 24 -an ~/Movies/screensaver.mp4"
    exit 1
fi

# Write to defaults
defaults write "$BUNDLE_ID" VideoPath "$VIDEO_PATH"

echo "Video set: $VIDEO_PATH"
echo ""
echo "The screensaver will use this video next time it activates."
echo "To test: System Settings > Screen Saver > Video Screen Saver"
