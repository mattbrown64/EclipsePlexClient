#!/bin/sh
# Copies MobileVLCKit.xcframework into DerivedData for embed (when not building via Pods scheme).
set -e
if [ -z "${PODS_ROOT:-}" ]; then
  echo "warning: PODS_ROOT unset; run pod install" >&2
  exit 0
fi
SCRIPT="${PODS_ROOT}/Target Support Files/MobileVLCKit/MobileVLCKit-xcframeworks.sh"
if [ ! -f "$SCRIPT" ]; then
  echo "warning: MobileVLCKit pod script missing; run pod install" >&2
  exit 0
fi
/bin/sh "$SCRIPT"
