#!/bin/sh
# Embed and re-sign VLCKit for macOS (called from Xcode build phase).
set -e

if [ "${PLATFORM_NAME}" != "macosx" ]; then
  exit 0
fi

FRAMEWORK_SRC="${PROJECT_DIR}/Frameworks/VLCKit.xcframework/macos-arm64_x86_64/VLCKit.framework"
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
FRAMEWORK_DEST="${DEST}/VLCKit.framework"

mkdir -p "${DEST}"
rsync -a --delete "${FRAMEWORK_SRC}" "${DEST}/"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY}"
if [ -z "${SIGN_IDENTITY}" ]; then
  SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"
fi
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
  echo "error: Set a Development signing team for macOS so VLCKit can be re-signed." >&2
  exit 1
fi

find "${FRAMEWORK_DEST}" -type f \( -name '*.dylib' -o -name 'VLCKit' \) | while read -r bin; do
  codesign --force --sign "${SIGN_IDENTITY}" --options runtime --timestamp=none "${bin}"
done
codesign --force --sign "${SIGN_IDENTITY}" --options runtime --timestamp=none "${FRAMEWORK_DEST}"
