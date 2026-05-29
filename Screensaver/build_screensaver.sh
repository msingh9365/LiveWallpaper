#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NAME="VideoScreenSaver"
SAVER_DIR="${SCRIPT_DIR}/${NAME}.saver"
SRC="${SCRIPT_DIR}/VideoScreenSaver.swift"
OBJ="${SCRIPT_DIR}/${NAME}.o"

echo "Building ${NAME}..."

rm -rf "${SAVER_DIR}" "${OBJ}"
mkdir -p "${SAVER_DIR}/Contents/MacOS"
mkdir -p "${SAVER_DIR}/Contents/Resources"

echo "  Compiling..."
swiftc -parse-as-library -c \
    -module-name "${NAME}" \
    -O \
    -o "${OBJ}" \
    "${SRC}"

echo "  Linking as bundle..."
xcrun clang -bundle \
    -o "${SAVER_DIR}/Contents/MacOS/${NAME}" \
    "${OBJ}" \
    -framework ScreenSaver \
    -framework AVFoundation \
    -framework AppKit \
    -L /usr/lib/swift \
    -lswiftCore \
    -Xlinker -rpath -Xlinker /usr/lib/swift

rm -f "${OBJ}"
cp "${SCRIPT_DIR}/Info.plist" "${SAVER_DIR}/Contents/"

echo "  Signing..."
codesign --force --sign - "${SAVER_DIR}"

TYPE=$(file -b "${SAVER_DIR}/Contents/MacOS/${NAME}" | head -1)
echo ""
echo "Done: ${SAVER_DIR}"
echo "Type: ${TYPE}"
echo ""
echo "Next: ./set-video.sh /path/to/video.mp4"
