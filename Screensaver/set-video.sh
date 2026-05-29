#!/bin/bash
# ─────────────────────────────────────────────────────────────────────
#  set-video.sh — Embed a video into the Video Screen Saver bundle
#
#  Usage:  ./set-video.sh /path/to/video.mp4
#
#  IMPORTANT: Use H.264 codec, NOT HEVC.
#  HEVC renders black via AVPlayerLayer on macOS 26.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALID_EXTS="mp4 m4v mov"
INSTALL_DIR="$HOME/Library/Screen Savers"
SAVER_NAME="VideoScreenSaver"
LOCAL_SAVER="${SCRIPT_DIR}/${SAVER_NAME}.saver"
INSTALLED_SAVER="${INSTALL_DIR}/${SAVER_NAME}.saver"

if [ $# -lt 1 ]; then
    echo "Usage: $0 /path/to/video.mp4"
    echo ""
    echo "Embeds the video inside the screensaver bundle and installs it."
    echo "Supported formats: ${VALID_EXTS}"
    echo ""
    echo "IMPORTANT: Use H.264, not HEVC. Convert with:"
    echo "  ffmpeg -i input.mp4 -c:v h264_videotoolbox -b:v 6M -r 24 -an output.mp4"
    exit 1
fi

VIDEO_PATH="$(cd "$(dirname "$1")" 2>/dev/null && pwd)/$(basename "$1")"

if [ ! -f "${VIDEO_PATH}" ]; then
    echo "Error: File not found: ${VIDEO_PATH}"
    exit 1
fi

EXT="${VIDEO_PATH##*.}"
EXT_LOWER=$(echo "${EXT}" | tr '[:upper:]' '[:lower:]')
VALID=false
for e in ${VALID_EXTS}; do
    [ "${EXT_LOWER}" = "$e" ] && VALID=true && break
done

if [ "${VALID}" = false ]; then
    echo "Error: Unsupported format: .${EXT_LOWER}"
    echo "Supported: ${VALID_EXTS}"
    exit 1
fi

if [ ! -d "${LOCAL_SAVER}" ]; then
    echo "Error: ${SAVER_NAME}.saver not found. Run ./build_screensaver.sh first."
    exit 1
fi

# Warn if HEVC
CODEC=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "${VIDEO_PATH}" 2>/dev/null || echo "unknown")
if [ "${CODEC}" = "hevc" ]; then
    echo "WARNING: Video uses HEVC codec which renders BLACK on macOS 26."
    echo "Re-encode with H.264:"
    echo "  ffmpeg -i \"${VIDEO_PATH}\" -c:v h264_videotoolbox -b:v 6M -r 24 -an output.mp4"
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [ "${REPLY}" != "y" ] && [ "${REPLY}" != "Y" ] && exit 1
fi

mkdir -p "${LOCAL_SAVER}/Contents/Resources"
rm -f "${LOCAL_SAVER}/Contents/Resources/video."*

echo "Embedding video..."
cp "${VIDEO_PATH}" "${LOCAL_SAVER}/Contents/Resources/video.${EXT_LOWER}"

echo "Signing..."
codesign --force --sign - "${LOCAL_SAVER}"

echo "Installing to ~/Library/Screen Savers/..."
rm -rf "${INSTALLED_SAVER}"
mkdir -p "${INSTALL_DIR}"
cp -R "${LOCAL_SAVER}" "${INSTALLED_SAVER}"

SIZE=$(du -sh "${VIDEO_PATH}" | cut -f1)
echo ""
echo "Done!"
echo "  Video: $(basename "${VIDEO_PATH}") (${SIZE}) [${CODEC}]"
echo ""
echo "Select in: System Settings > Screen Saver > Video Screen Saver"
