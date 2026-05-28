#!/usr/bin/env bash
# Prints an xcodebuild -destination value for the newest available iPhone simulator.
set -euo pipefail

preferred=("iPhone 16 Pro" "iPhone 16" "iPhone 15 Pro" "iPhone 15" "iPhone SE (3rd generation)")

for name in "${preferred[@]}"; do
  id=$(xcrun simctl list devices available | grep -F "${name} (" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/' || true)
  if [[ -n "${id}" ]]; then
    echo "platform=iOS Simulator,id=${id}"
    exit 0
  fi
done

id=$(xcrun simctl list devices available | grep "iPhone" | head -1 | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/')
if [[ -z "${id}" ]]; then
  echo "error: no available iPhone simulator" >&2
  exit 1
fi
echo "platform=iOS Simulator,id=${id}"
