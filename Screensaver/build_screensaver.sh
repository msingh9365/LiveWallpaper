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

# Step 1: Compile Swift to object file
echo "  Compiling..."
swiftc -parse-as-library -c \
    -module-name "${NAME}" \
    -O \
    -o "${OBJ}" \
    "${SRC}"

# Step 2: Link as MH_BUNDLE (not MH_DYLIB)
# ScreenSaverEngine requires a loadable bundle, not a dynamic library.
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

# Cleanup object file
rm -f "${OBJ}"

# Copy Info.plist
cp "${SCRIPT_DIR}/Info.plist" "${SAVER_DIR}/Contents/"

# Step 3: Ad-hoc codesign (required on modern macOS for system processes to load)
echo "  Signing..."
codesign --force --sign - "${SAVER_DIR}"

# Verify
TYPE=$(file -b "${SAVER_DIR}/Contents/MacOS/${NAME}" | head -1)
echo ""
echo "Done: ${SAVER_DIR}"
echo "Type: ${TYPE}"
echo ""
echo "Install:"
echo "  open ${SAVER_DIR}"
echo ""
echo "Or silently:"
echo "  cp -R ${SAVER_DIR} ~/Library/Screen\ Savers/"
