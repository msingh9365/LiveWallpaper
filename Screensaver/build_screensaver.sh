#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="VideoScreenSaver"
SAVER_DIR="${SCRIPT_DIR}/${NAME}.saver"
SRC="${SCRIPT_DIR}/VideoScreenSaver.swift"
OBJ="${SCRIPT_DIR}/${NAME}.o"

echo "Building ${NAME}..."

# Clean
rm -rf "${SAVER_DIR}" "${OBJ}"

# Create bundle structure
mkdir -p "${SAVER_DIR}/Contents/MacOS"

# Compile to object
echo "  Compiling..."
swiftc -parse-as-library -c \
    -module-name "${NAME}" \
    -O \
    -o "${OBJ}" \
    "${SRC}"

# Link as dynamic library
echo "  Linking..."
swiftc \
    -emit-library \
    -module-name "${NAME}" \
    -framework ScreenSaver \
    -framework AVFoundation \
    -framework AppKit \
    -O \
    -o "${SAVER_DIR}/Contents/MacOS/${NAME}" \
    "${OBJ}"

# Cleanup
rm -f "${OBJ}"

# Info.plist
cp "${SCRIPT_DIR}/Info.plist" "${SAVER_DIR}/Contents/"

echo ""
echo "Done: ${SAVER_DIR}"
echo ""
echo "Install:"
echo "  open ${SAVER_DIR}"
echo "  (macOS will prompt to install the screensaver)"
echo ""
echo "Or install silently:"
echo "  cp -R ${SAVER_DIR} ~/Library/Screen\ Savers/"
