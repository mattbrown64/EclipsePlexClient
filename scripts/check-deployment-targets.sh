#!/usr/bin/env bash
# Fails CI if app deployment targets drift from Podfile baselines.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/EclipsePlexClient.xcodeproj/project.pbxproj"
PODFILE="$ROOT/Podfile"

expect_ios="16.0"
expect_macos="14.0"
expect_tvos="17.0"

ios_pod=$(grep -E "platform :ios," "$PODFILE" | sed -E "s/.*'([0-9.]+)'.*/\1/" | head -1)
ios_pbx=$(grep "IPHONEOS_DEPLOYMENT_TARGET" "$PBX" | head -1 | sed -E 's/.*= ([0-9.]+);/\1/')

if [[ "$ios_pod" != "$ios_pbx" ]]; then
  echo "error: iOS deployment target mismatch: Podfile=$ios_pod project=$ios_pbx" >&2
  exit 1
fi

mac_pbx=$(grep "MACOSX_DEPLOYMENT_TARGET" "$PBX" | head -1 | sed -E 's/.*= ([0-9.]+);/\1/')
if [[ "$mac_pbx" != "$expect_macos" ]]; then
  echo "error: macOS deployment target expected $expect_macos, found $mac_pbx" >&2
  exit 1
fi

tv_pbx=$(grep "TVOS_DEPLOYMENT_TARGET" "$PBX" | head -1 | sed -E 's/.*= ([0-9.]+);/\1/' || true)
if [[ -n "$tv_pbx" && "$tv_pbx" != "$expect_tvos" ]]; then
  echo "error: tvOS deployment target expected $expect_tvos, found $tv_pbx" >&2
  exit 1
fi

echo "Deployment targets OK (iOS $ios_pbx, macOS $mac_pbx, tvOS ${tv_pbx:-n/a})"
