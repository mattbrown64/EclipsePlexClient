#!/usr/bin/env bash
# Boots the simulator referenced by an xcodebuild destination string.
set -euo pipefail

dest="${1:-${IOS_SIMULATOR_DESTINATION:-}}"
if [[ -z "$dest" ]]; then
  echo "error: missing iOS simulator destination" >&2
  exit 1
fi

id=$(echo "$dest" | sed -E 's/.*id=([^,} ]+).*/\1/')
if [[ -z "$id" || "$id" == "$dest" ]]; then
  echo "error: could not parse simulator id from: $dest" >&2
  exit 1
fi

xcrun simctl boot "$id" 2>/dev/null || true
xcrun simctl bootstatus "$id" -b
echo "Booted iOS Simulator $id"
