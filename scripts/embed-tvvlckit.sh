#!/bin/sh
# Embed and re-sign TVVLCKit for tvOS (called from Xcode build phase).
set -e

if [ "${PLATFORM_NAME}" != "appletvos" ] && [ "${PLATFORM_NAME}" != "appletvsimulator" ]; then
  exit 0
fi

XCFRAMEWORK="${PROJECT_DIR}/Frameworks/TVVLCKit.xcframework"
if [ ! -d "${XCFRAMEWORK}" ]; then
  echo "error: Run ./scripts/fetch-tvvlckit.sh to install Frameworks/TVVLCKit.xcframework" >&2
  exit 1
fi

case "${PLATFORM_NAME}" in
  appletvos) SLICE="tvos-arm64" ;;
  appletvsimulator) SLICE="tvos-arm64_x86_64-simulator" ;;
  *) exit 0 ;;
esac

FRAMEWORK_SRC="${XCFRAMEWORK}/${SLICE}/TVVLCKit.framework"
DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
FRAMEWORK_DEST="${DEST}/TVVLCKit.framework"

mkdir -p "${DEST}"
rsync -a --delete "${FRAMEWORK_SRC}" "${DEST}/"

SIGN_IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY}"
if [ -z "${SIGN_IDENTITY}" ]; then
  SIGN_IDENTITY="${CODE_SIGN_IDENTITY}"
fi
if [ -z "${SIGN_IDENTITY}" ] || [ "${SIGN_IDENTITY}" = "-" ]; then
  echo "warning: No code sign identity; skipping TVVLCKit re-sign" >&2
  exit 0
fi

find "${FRAMEWORK_DEST}" -type f \( -name '*.dylib' -o -name 'TVVLCKit' \) | while read -r bin; do
  codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${bin}"
done
codesign --force --sign "${SIGN_IDENTITY}" --timestamp=none "${FRAMEWORK_DEST}"
